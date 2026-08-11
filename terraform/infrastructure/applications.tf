resource "kubernetes_secret_v1" "primary_database" {
  provider = kubernetes.primary

  metadata { name = "database-credentials" }

  data = {
    PGDATABASE = var.db_name
    PGPASSWORD = random_password.database.result
    PGUSER     = var.db_username
  }
}

resource "kubernetes_secret_v1" "secondary_database" {
  provider = kubernetes.secondary

  metadata { name = "database-credentials" }

  data = {
    PGDATABASE = var.db_name
    PGPASSWORD = random_password.database.result
    PGUSER     = var.db_username
  }
}

resource "kubernetes_deployment_v1" "primary" {
  provider = kubernetes.primary

  depends_on = [aws_rds_cluster_instance.primary]

  metadata { name = "regional-test" }

  spec {
    replicas = 2

    selector { match_labels = { app = "regional-test" } }

    template {
      metadata { labels = { app = "regional-test" } }

      spec {
        init_container {
          name    = "database-read-write-check"
          image   = "postgres:16-alpine"
          command = ["/bin/sh", "-c"]
          args = [<<-EOT
            until psql -h "$DB_WRITER_ENDPOINT" -v ON_ERROR_STOP=1 -c "CREATE TABLE IF NOT EXISTS regional_probe (region text PRIMARY KEY, checked_at timestamptz NOT NULL); INSERT INTO regional_probe VALUES ('primary', now()) ON CONFLICT (region) DO UPDATE SET checked_at = excluded.checked_at; SELECT * FROM regional_probe WHERE region = 'primary';"; do
              sleep 5
            done
          EOT
          ]

          env_from {
            secret_ref { name = kubernetes_secret_v1.primary_database.metadata[0].name }
          }
          env {
            name  = "DB_WRITER_ENDPOINT"
            value = aws_rds_global_cluster.this.endpoint
          }
        }

        container {
          name  = "app"
          image = "hashicorp/http-echo:1.0"
          args  = ["-listen=:8080", "-text=region=primary"]

          port { container_port = 8080 }

          env {
            name  = "DB_WRITER_ENDPOINT"
            value = aws_rds_global_cluster.this.endpoint
          }
          env {
            name  = "DB_READER_ENDPOINT"
            value = aws_rds_cluster.primary.reader_endpoint
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment_v1" "secondary" {
  provider = kubernetes.secondary

  depends_on = [aws_rds_cluster_instance.secondary]

  metadata { name = "regional-test" }

  spec {
    replicas = 2

    selector { match_labels = { app = "regional-test" } }

    template {
      metadata { labels = { app = "regional-test" } }

      spec {
        init_container {
          name    = "global-writer-check"
          image   = "postgres:16-alpine"
          command = ["/bin/sh", "-c"]
          args = [<<-EOT
            until psql -h "$DB_WRITER_ENDPOINT" -v ON_ERROR_STOP=1 -c "CREATE TABLE IF NOT EXISTS regional_probe (region text PRIMARY KEY, checked_at timestamptz NOT NULL); INSERT INTO regional_probe VALUES ('secondary', now()) ON CONFLICT (region) DO UPDATE SET checked_at = excluded.checked_at;"; do
              sleep 5
            done
          EOT
          ]

          env_from {
            secret_ref { name = kubernetes_secret_v1.secondary_database.metadata[0].name }
          }
          env {
            name  = "DB_WRITER_ENDPOINT"
            value = aws_rds_global_cluster.this.endpoint
          }
        }

        init_container {
          name    = "local-reader-check"
          image   = "postgres:16-alpine"
          command = ["/bin/sh", "-c"]
          args = [<<-EOT
            until psql -h "$DB_READER_ENDPOINT" -v ON_ERROR_STOP=1 -c "SELECT * FROM regional_probe WHERE region = 'secondary';" | grep -q secondary; do
              sleep 5
            done
          EOT
          ]

          env_from {
            secret_ref { name = kubernetes_secret_v1.secondary_database.metadata[0].name }
          }
          env {
            name  = "DB_READER_ENDPOINT"
            value = aws_rds_cluster.secondary.reader_endpoint
          }
        }

        container {
          name  = "app"
          image = "hashicorp/http-echo:1.0"
          args  = ["-listen=:8080", "-text=region=secondary"]

          port { container_port = 8080 }

          env {
            name  = "DB_WRITER_ENDPOINT"
            value = aws_rds_global_cluster.this.endpoint
          }
          env {
            name  = "DB_READER_ENDPOINT"
            value = aws_rds_cluster.secondary.reader_endpoint
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "primary" {
  provider = kubernetes.primary

  metadata { name = "regional-test" }

  spec {
    selector = { app = "regional-test" }
    port {
      port        = 80
      target_port = 8080
    }
  }
}

resource "kubernetes_service_v1" "secondary" {
  provider = kubernetes.secondary

  metadata { name = "regional-test" }

  spec {
    selector = { app = "regional-test" }
    port {
      port        = 80
      target_port = 8080
    }
  }
}

resource "kubernetes_ingress_v1" "primary" {
  provider = kubernetes.primary

  metadata {
    name = "regional-test"
    annotations = {
      "alb.ingress.kubernetes.io/certificate-arn"    = aws_acm_certificate_validation.primary.certificate_arn
      "alb.ingress.kubernetes.io/listen-ports"       = jsonencode([{ HTTP = 80 }, { HTTPS = 443 }])
      "alb.ingress.kubernetes.io/load-balancer-name" = "${var.project_name}-primary"
      "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
      "alb.ingress.kubernetes.io/ssl-redirect"       = "443"
      "alb.ingress.kubernetes.io/target-type"        = "ip"
    }
  }

  spec {
    ingress_class_name = "alb"
    rule {
      host = var.domain_name
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.primary.metadata[0].name
              port { number = 80 }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.primary_load_balancer_controller]
}

resource "kubernetes_ingress_v1" "secondary" {
  provider = kubernetes.secondary

  metadata {
    name = "regional-test"
    annotations = {
      "alb.ingress.kubernetes.io/certificate-arn"    = aws_acm_certificate_validation.secondary.certificate_arn
      "alb.ingress.kubernetes.io/listen-ports"       = jsonencode([{ HTTP = 80 }, { HTTPS = 443 }])
      "alb.ingress.kubernetes.io/load-balancer-name" = "${var.project_name}-secondary"
      "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
      "alb.ingress.kubernetes.io/ssl-redirect"       = "443"
      "alb.ingress.kubernetes.io/target-type"        = "ip"
    }
  }

  spec {
    ingress_class_name = "alb"
    rule {
      host = var.domain_name
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.secondary.metadata[0].name
              port { number = 80 }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.secondary_load_balancer_controller]
}
