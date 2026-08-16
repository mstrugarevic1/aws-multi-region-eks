# Purpose: Deploys regional workloads, Services, and ALB Ingresses to both EKS clusters.
# Modules: None; these resources target the clusters created in eks.tf.

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

resource "kubernetes_config_map_v1" "primary_application" {
  provider = kubernetes.primary

  metadata { name = "regional-test" }
  data = { "application.sh" = file("${path.module}/application.sh") }
}

resource "kubernetes_config_map_v1" "secondary_application" {
  provider = kubernetes.secondary

  metadata { name = "regional-test" }
  data = { "application.sh" = file("${path.module}/application.sh") }
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
        container {
          name    = "app"
          image   = "postgres:16-alpine"
          command = ["/app/application.sh"]
          args    = ["serve"]

          port { container_port = 8080 }

          env_from {
            secret_ref { name = kubernetes_secret_v1.primary_database.metadata[0].name }
          }
          env {
            name  = "DB_WRITER_ENDPOINT"
            value = aws_rds_global_cluster.this.endpoint
          }
          env {
            name  = "PGSSLMODE"
            value = "require"
          }
          env {
            name  = "REGION"
            value = var.primary_region
          }

          readiness_probe {
            http_get {
              path   = "/readyz"
              port   = 8080
              scheme = "HTTP"
            }
            initial_delay_seconds = 2
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 2
          }

          liveness_probe {
            http_get {
              path   = "/healthz"
              port   = 8080
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 2
            failure_threshold     = 3
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_group               = 70
            run_as_non_root            = true
            run_as_user                = 70

            capabilities { drop = ["ALL"] }
          }

          volume_mount {
            name       = "application"
            mount_path = "/app"
            read_only  = true
          }
        }

        volume {
          name = "application"
          config_map {
            name         = kubernetes_config_map_v1.primary_application.metadata[0].name
            default_mode = "0555"
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
        container {
          name    = "app"
          image   = "postgres:16-alpine"
          command = ["/app/application.sh"]
          args    = ["serve"]

          port { container_port = 8080 }

          env_from {
            secret_ref { name = kubernetes_secret_v1.secondary_database.metadata[0].name }
          }
          env {
            name  = "DB_WRITER_ENDPOINT"
            value = aws_rds_global_cluster.this.endpoint
          }
          env {
            name  = "PGSSLMODE"
            value = "require"
          }
          env {
            name  = "REGION"
            value = var.secondary_region
          }

          readiness_probe {
            http_get {
              path   = "/readyz"
              port   = 8080
              scheme = "HTTP"
            }
            initial_delay_seconds = 2
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 2
          }

          liveness_probe {
            http_get {
              path   = "/healthz"
              port   = 8080
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 2
            failure_threshold     = 3
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_group               = 70
            run_as_non_root            = true
            run_as_user                = 70

            capabilities { drop = ["ALL"] }
          }

          volume_mount {
            name       = "application"
            mount_path = "/app"
            read_only  = true
          }
        }

        volume {
          name = "application"
          config_map {
            name         = kubernetes_config_map_v1.secondary_application.metadata[0].name
            default_mode = "0555"
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

# Stable ALB names are the handoff contract with the separate edge state.
resource "kubernetes_ingress_v1" "primary" {
  provider = kubernetes.primary

  metadata {
    name = "regional-test"
    annotations = {
      "alb.ingress.kubernetes.io/certificate-arn"    = aws_acm_certificate_validation.primary.certificate_arn
      "alb.ingress.kubernetes.io/healthcheck-path"   = "/readyz"
      "alb.ingress.kubernetes.io/listen-ports"       = jsonencode([{ HTTP = 80 }, { HTTPS = 443 }])
      "alb.ingress.kubernetes.io/load-balancer-name" = "${var.project_name}-primary"
      "alb.ingress.kubernetes.io/scheme"             = "internal"
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
      "alb.ingress.kubernetes.io/healthcheck-path"   = "/readyz"
      "alb.ingress.kubernetes.io/listen-ports"       = jsonencode([{ HTTP = 80 }, { HTTPS = 443 }])
      "alb.ingress.kubernetes.io/load-balancer-name" = "${var.project_name}-secondary"
      "alb.ingress.kubernetes.io/scheme"             = "internal"
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
