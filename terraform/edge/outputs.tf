# Purpose: Exposes the Global Accelerator address and public application hostname.
# Modules: None; every value comes from resources declared in this edge root.

output "global_accelerator_dns_name" { value = aws_globalaccelerator_accelerator.this.dns_name }
output "global_accelerator_static_ips" { value = aws_globalaccelerator_accelerator.this.ip_sets[0].ip_addresses }
output "application_hostname" { value = aws_route53_record.application.fqdn }
