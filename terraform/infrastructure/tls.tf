# Purpose: Issues and DNS-validates one ACM certificate in each ALB region.
# Modules: None; ACM and Route 53 resources are declared directly.

resource "aws_acm_certificate" "primary" {
  provider          = aws.primary
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle { create_before_destroy = true }
}

resource "aws_acm_certificate" "secondary" {
  provider          = aws.secondary
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle { create_before_destroy = true }
}

# ACM uses the same DNS validation CNAME for this hostname in both regions, so
# one Route 53 record validates both regional certificates.
resource "aws_route53_record" "certificate_validation" {
  provider = aws.primary
  for_each = {
    for option in aws_acm_certificate.primary.domain_validation_options : option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  }

  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "primary" {
  provider                = aws.primary
  certificate_arn         = aws_acm_certificate.primary.arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

resource "aws_acm_certificate_validation" "secondary" {
  provider                = aws.secondary
  certificate_arn         = aws_acm_certificate.secondary.arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}
