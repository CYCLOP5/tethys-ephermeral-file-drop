output "alb_dns_name" {
  description = "Public DNS name of the ALB. Point your domain CNAME here."
  value       = aws_lb.this.dns_name
}

output "jenkins_url" {
  description = "Jenkins web UI. Accessible only from allowed_ssh_cidr."
  value       = "http://${aws_instance.jenkins.public_ip}:8080"
}

output "jenkins_ssh" {
  description = "SSH command to the Jenkins host."
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_instance.jenkins.public_ip}"
}

output "k3s_server_ssh" {
  description = "SSH command to the K3s control-plane."
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_instance.k3s_server.public_ip}"
}

output "k3s_agents_ssh" {
  description = "SSH commands to the K3s agent nodes."
  value       = [for i, ip in aws_instance.k3s_agent[*].public_ip : "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${ip}"]
}

output "rds_endpoint" {
  description = "Postgres endpoint (hostname only)."
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  value = aws_db_instance.postgres.port
}

output "s3_bucket_name" {
  description = "Encrypted file bucket."
  value       = aws_s3_bucket.files.bucket
}

output "ecr_repositories" {
  description = "ECR repo URLs."
  value       = { for k, r in aws_ecr_repository.services : k => r.repository_url }
}

output "vault_role_arn" {
  value = aws_iam_role.vault.arn
}

output "wiper_role_arn" {
  value = aws_iam_role.wiper.arn
}
