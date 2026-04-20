variable "aws_region" {
  description = "AWS region to deploy to. Free Tier is widest in us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment label (dev/stage/prod). Used in tags and resource names."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the Tethys VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (one per AZ). ALB + EC2 live here."
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (one per AZ). RDS only."
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]
}

variable "instance_type" {
  description = "Free-Tier-eligible instance type for Jenkins and K3s nodes."
  type        = string
  default     = "t3.micro"
}

variable "key_pair_name" {
  description = "Name of an existing EC2 key pair you control."
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into the EC2 instances. Use your /32."
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "allowed_ssh_cidr must be a valid CIDR block (e.g. 1.2.3.4/32)."
  }
}

variable "k3s_agent_count" {
  description = "Number of K3s worker nodes. Keep at 1 for free-tier."
  type        = number
  default     = 1

  validation {
    condition     = var.k3s_agent_count >= 1 && var.k3s_agent_count <= 3
    error_message = "k3s_agent_count must be between 1 and 3."
  }
}

variable "db_name" {
  description = "Postgres database name."
  type        = string
  default     = "tethys"
}

variable "db_username" {
  description = "Postgres master username."
  type        = string
  default     = "tethys"
}

variable "db_password" {
  description = "Postgres master password. Generate with: openssl rand -base64 24"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 16
    error_message = "db_password must be at least 16 characters."
  }
}

variable "db_instance_class" {
  description = "RDS instance class. Free Tier = db.t3.micro."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage_gb" {
  description = "RDS storage in GB. Free Tier allows up to 20."
  type        = number
  default     = 20
}

variable "acm_certificate_arn" {
  description = "ARN of an ACM cert in this region for the ALB. Leave empty to use HTTP-only (demo)."
  type        = string
  default     = ""
}

variable "s3_object_expiration_days" {
  description = "Lifecycle rule as a belt-and-suspenders backstop to the wiper CronJob."
  type        = number
  default     = 7
}
