# -----------------------------------------------------------------------------
# Per-workload IAM roles. The K3s agent nodes hold these roles via instance
# profiles; pods inherit them through the IMDS hop granted by the kube-proxy
# network, and their scope is narrow enough to approximate IRSA on K3s.
# Switch to irsa-on-k3s (https://github.com/kube-sa/aws-workload-identity)
# if you need per-pod roles in production.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# -------- Vault role: write + read a single bucket --------
resource "aws_iam_role" "vault" {
  name               = "${local.name_prefix}-vault"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "vault" {
  statement {
    sid       = "PutGetOnFiles"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:AbortMultipartUpload"]
    resources = ["${aws_s3_bucket.files.arn}/files/*"]
  }

  statement {
    sid       = "BucketLocation"
    effect    = "Allow"
    actions   = ["s3:GetBucketLocation", "s3:ListBucket"]
    resources = [aws_s3_bucket.files.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["files/*"]
    }
  }
}

resource "aws_iam_policy" "vault" {
  name   = "${local.name_prefix}-vault"
  policy = data.aws_iam_policy_document.vault.json
}

resource "aws_iam_role_policy_attachment" "vault" {
  role       = aws_iam_role.vault.name
  policy_arn = aws_iam_policy.vault.arn
}

# -------- Wiper role: delete + list --------
resource "aws_iam_role" "wiper" {
  name               = "${local.name_prefix}-wiper"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "wiper" {
  statement {
    sid       = "DeleteOnFiles"
    effect    = "Allow"
    actions   = ["s3:DeleteObject", "s3:DeleteObjectVersion"]
    resources = ["${aws_s3_bucket.files.arn}/files/*"]
  }

  statement {
    sid       = "ListFilesPrefix"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:ListBucketVersions"]
    resources = [aws_s3_bucket.files.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["files/*"]
    }
  }
}

resource "aws_iam_policy" "wiper" {
  name   = "${local.name_prefix}-wiper"
  policy = data.aws_iam_policy_document.wiper.json
}

resource "aws_iam_role_policy_attachment" "wiper" {
  role       = aws_iam_role.wiper.name
  policy_arn = aws_iam_policy.wiper.arn
}

# -------- K3s agent instance profile: superset of vault+wiper so pods can AssumeRole as needed --------
resource "aws_iam_role" "k3s_agent" {
  name               = "${local.name_prefix}-k3s-agent"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "k3s_agent" {
  statement {
    sid       = "S3ForWorkloads"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket", "s3:AbortMultipartUpload"]
    resources = [aws_s3_bucket.files.arn, "${aws_s3_bucket.files.arn}/*"]
  }

  statement {
    sid    = "SSMParams"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]
    resources = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/tethys/*"]
  }
}

resource "aws_iam_policy" "k3s_agent" {
  name   = "${local.name_prefix}-k3s-agent"
  policy = data.aws_iam_policy_document.k3s_agent.json
}

resource "aws_iam_role_policy_attachment" "k3s_agent" {
  role       = aws_iam_role.k3s_agent.name
  policy_arn = aws_iam_policy.k3s_agent.arn
}

resource "aws_iam_instance_profile" "k3s_agent" {
  name = "${local.name_prefix}-k3s-agent"
  role = aws_iam_role.k3s_agent.name
}

# -------- Jenkins role: describe EC2 + full ECR on project repos --------
resource "aws_iam_role" "jenkins" {
  name               = "${local.name_prefix}-jenkins"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "jenkins" {
  statement {
    sid       = "DescribeInstances"
    effect    = "Allow"
    actions   = ["ec2:Describe*"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrAuth"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories"
    ]
    resources = [
      for r in aws_ecr_repository.services : r.arn
    ]
  }

  statement {
    sid    = "SsmGetForCiSecrets"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters"
    ]
    resources = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/tethys/ci/*"]
  }
}

resource "aws_iam_policy" "jenkins" {
  name   = "${local.name_prefix}-jenkins"
  policy = data.aws_iam_policy_document.jenkins.json
}

resource "aws_iam_role_policy_attachment" "jenkins" {
  role       = aws_iam_role.jenkins.name
  policy_arn = aws_iam_policy.jenkins.arn
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${local.name_prefix}-jenkins"
  role = aws_iam_role.jenkins.name
}

# -------- ECR repositories for our three images --------
resource "aws_ecr_repository" "services" {
  for_each             = toset(["vault", "wiper", "frontend"])
  name                 = "tethys/${each.key}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = "tethys-${each.key}" }
}

resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
