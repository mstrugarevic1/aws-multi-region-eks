# Purpose: Builds the two-region Aurora Global Database and access controls.
# Modules: None; this file consumes database subnet outputs from the VPC modules.

resource "aws_security_group" "primary_database" {
  provider    = aws.primary
  name_prefix = "${var.project_name}-primary-db-"
  description = "Aurora PostgreSQL access from both application VPCs"
  vpc_id      = module.primary_vpc.vpc_id

  ingress {
    description = "PostgreSQL from application VPCs"
    protocol    = "tcp"
    from_port   = 5432
    to_port     = 5432
    cidr_blocks = [var.primary_vpc_cidr, var.secondary_vpc_cidr]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle { create_before_destroy = true }
}

resource "aws_security_group" "secondary_database" {
  provider    = aws.secondary
  name_prefix = "${var.project_name}-secondary-db-"
  description = "Aurora PostgreSQL access from the secondary application VPC"
  vpc_id      = module.secondary_vpc.vpc_id

  ingress {
    description = "PostgreSQL from secondary application VPC"
    protocol    = "tcp"
    from_port   = 5432
    to_port     = 5432
    cidr_blocks = [var.secondary_vpc_cidr]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle { create_before_destroy = true }
}

# The primary and secondary regional clusters join this shared replication
# topology as writer and read-only members, respectively.
resource "aws_rds_global_cluster" "this" {
  provider                  = aws.primary
  global_cluster_identifier = var.project_name
  engine                    = "aurora-postgresql"
  engine_version            = "16.6"
  database_name             = var.db_name
  deletion_protection       = false
  force_destroy             = true
}

resource "random_password" "database" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}:?"
}

resource "aws_secretsmanager_secret" "database" {
  provider                = aws.primary
  name                    = "${var.project_name}/aurora-master"
  recovery_window_in_days = 0
}

resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier        = "${var.project_name}-primary"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  database_name             = var.db_name
  master_username           = var.db_username
  master_password           = random_password.database.result
  db_subnet_group_name      = module.primary_vpc.database_subnet_group_name
  vpc_security_group_ids    = [aws_security_group.primary_database.id]
  storage_encrypted         = true
  backup_retention_period   = 1
  skip_final_snapshot       = true
}

resource "aws_secretsmanager_secret_version" "database" {
  provider  = aws.primary
  secret_id = aws_secretsmanager_secret.database.id

  # The global endpoint follows the writer after a managed switchover or failover.
  secret_string = jsonencode({
    engine   = "postgres"
    host     = aws_rds_global_cluster.this.endpoint
    port     = 5432
    dbname   = var.db_name
    username = var.db_username
    password = random_password.database.result
  })
}

resource "aws_rds_cluster_instance" "primary" {
  provider = aws.primary

  identifier         = "${var.project_name}-primary-1"
  cluster_identifier = aws_rds_cluster.primary.id
  instance_class     = "db.r6g.large"
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version
}

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = "${var.project_name}-secondary"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  db_subnet_group_name      = module.secondary_vpc.database_subnet_group_name
  vpc_security_group_ids    = [aws_security_group.secondary_database.id]
  storage_encrypted         = true
  skip_final_snapshot       = true

  # Aurora requires a provisioned primary instance before adding a secondary member.
  depends_on = [aws_rds_cluster_instance.primary]
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary

  identifier         = "${var.project_name}-secondary-1"
  cluster_identifier = aws_rds_cluster.secondary.id
  instance_class     = "db.r6g.large"
  engine             = aws_rds_cluster.secondary.engine
  engine_version     = aws_rds_cluster.secondary.engine_version
}
