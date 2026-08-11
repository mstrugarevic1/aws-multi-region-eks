output "primary_vpc_id" { value = module.primary_vpc.vpc_id }
output "secondary_vpc_id" { value = module.secondary_vpc.vpc_id }
output "primary_eks_cluster_name" { value = module.primary_eks.cluster_name }
output "secondary_eks_cluster_name" { value = module.secondary_eks.cluster_name }

output "primary_alb_dns_name" {
  value = try(kubernetes_ingress_v1.primary.status[0].load_balancer[0].ingress[0].hostname, "pending-controller-reconciliation")
}

output "secondary_alb_dns_name" {
  value = try(kubernetes_ingress_v1.secondary.status[0].load_balancer[0].ingress[0].hostname, "pending-controller-reconciliation")
}

output "aurora_global_writer_endpoint" { value = aws_rds_global_cluster.this.endpoint }
output "aurora_secondary_reader_endpoint" { value = aws_rds_cluster.secondary.reader_endpoint }
