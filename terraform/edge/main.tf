data "aws_lb" "primary" {
  provider = aws.primary
  name     = "${var.project_name}-primary"
}

data "aws_lb" "secondary" {
  provider = aws.secondary
  name     = "${var.project_name}-secondary"
}

resource "aws_globalaccelerator_accelerator" "this" {
  provider        = aws.primary
  name            = var.project_name
  enabled         = true
  ip_address_type = "IPV4"
}

resource "aws_globalaccelerator_listener" "web" {
  provider        = aws.primary
  accelerator_arn = aws_globalaccelerator_accelerator.this.id
  protocol        = "TCP"
  client_affinity = "NONE"

  port_range {
    from_port = 80
    to_port   = 80
  }

  port_range {
    from_port = 443
    to_port   = 443
  }
}

resource "aws_globalaccelerator_endpoint_group" "primary" {
  provider                = aws.primary
  listener_arn            = aws_globalaccelerator_listener.web.id
  endpoint_group_region   = var.primary_region
  traffic_dial_percentage = var.primary_traffic_dial

  endpoint_configuration {
    endpoint_id                    = data.aws_lb.primary.arn
    client_ip_preservation_enabled = false
    weight                         = 100
  }
}

resource "aws_globalaccelerator_endpoint_group" "secondary" {
  provider                = aws.primary
  listener_arn            = aws_globalaccelerator_listener.web.id
  endpoint_group_region   = var.secondary_region
  traffic_dial_percentage = var.secondary_traffic_dial

  endpoint_configuration {
    endpoint_id                    = data.aws_lb.secondary.arn
    client_ip_preservation_enabled = false
    weight                         = 100
  }
}

resource "aws_route53_record" "application" {
  provider = aws.primary
  zone_id  = var.route53_zone_id
  name     = var.domain_name
  type     = "A"

  alias {
    name                   = aws_globalaccelerator_accelerator.this.dns_name
    zone_id                = aws_globalaccelerator_accelerator.this.hosted_zone_id
    evaluate_target_health = false
  }
}
