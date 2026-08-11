module "primary_eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.37.2"

  providers = { aws = aws.primary }

  cluster_name                             = "${var.project_name}-primary"
  cluster_version                          = "1.36"
  cluster_endpoint_public_access           = true
  cluster_endpoint_private_access          = true
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.primary_vpc.vpc_id
  subnet_ids = module.primary_vpc.private_subnets

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true, before_compute = true }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.small"]
      ami_type       = "AL2023_x86_64_STANDARD"
      min_size       = 2
      desired_size   = 2
      max_size       = 2
    }
  }
}

module "secondary_eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.37.2"

  providers = { aws = aws.secondary }

  cluster_name                             = "${var.project_name}-secondary"
  cluster_version                          = "1.36"
  cluster_endpoint_public_access           = true
  cluster_endpoint_private_access          = true
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.secondary_vpc.vpc_id
  subnet_ids = module.secondary_vpc.private_subnets

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true, before_compute = true }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.small"]
      ami_type       = "AL2023_x86_64_STANDARD"
      min_size       = 2
      desired_size   = 2
      max_size       = 2
    }
  }
}

resource "aws_iam_policy" "load_balancer_controller" {
  provider = aws.primary
  name     = "${var.project_name}-load-balancer-controller"
  policy   = file("${path.module}/load-balancer-controller-iam-policy.json")
}

data "aws_iam_policy_document" "primary_load_balancer_controller_assume" {
  provider = aws.primary

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.primary_eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.primary_eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.primary_eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

data "aws_iam_policy_document" "secondary_load_balancer_controller_assume" {
  provider = aws.secondary

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.secondary_eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.secondary_eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.secondary_eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "primary_load_balancer_controller" {
  provider           = aws.primary
  name               = "${var.project_name}-primary-lbc"
  assume_role_policy = data.aws_iam_policy_document.primary_load_balancer_controller_assume.json
}

resource "aws_iam_role" "secondary_load_balancer_controller" {
  provider           = aws.secondary
  name               = "${var.project_name}-secondary-lbc"
  assume_role_policy = data.aws_iam_policy_document.secondary_load_balancer_controller_assume.json
}

resource "aws_iam_role_policy_attachment" "primary_load_balancer_controller" {
  provider   = aws.primary
  role       = aws_iam_role.primary_load_balancer_controller.name
  policy_arn = aws_iam_policy.load_balancer_controller.arn
}

resource "aws_iam_role_policy_attachment" "secondary_load_balancer_controller" {
  provider   = aws.secondary
  role       = aws_iam_role.secondary_load_balancer_controller.name
  policy_arn = aws_iam_policy.load_balancer_controller.arn
}

resource "kubernetes_service_account_v1" "primary_load_balancer_controller" {
  provider = kubernetes.primary

  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.primary_load_balancer_controller.arn
    }
  }
}

resource "kubernetes_service_account_v1" "secondary_load_balancer_controller" {
  provider = kubernetes.secondary

  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.secondary_load_balancer_controller.arn
    }
  }
}

resource "helm_release" "primary_load_balancer_controller" {
  provider = helm.primary

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.5.0"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = module.primary_eks.cluster_name
  }
  set {
    name  = "region"
    value = var.primary_region
  }
  set {
    name  = "vpcId"
    value = module.primary_vpc.vpc_id
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account_v1.primary_load_balancer_controller.metadata[0].name
  }
}

resource "helm_release" "secondary_load_balancer_controller" {
  provider = helm.secondary

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.5.0"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = module.secondary_eks.cluster_name
  }
  set {
    name  = "region"
    value = var.secondary_region
  }
  set {
    name  = "vpcId"
    value = module.secondary_vpc.vpc_id
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account_v1.secondary_load_balancer_controller.metadata[0].name
  }
}
