locals {
  jenkins_user_data = <<-EOT
    #!/bin/bash
    set -eux
    dnf update -y
    dnf install -y git python3 python3-pip
    hostnamectl set-hostname tethys-jenkins
    echo "tethys-jenkins" > /etc/hostname
  EOT

  k3s_server_user_data = <<-EOT
    #!/bin/bash
    set -eux
    dnf update -y
    dnf install -y git python3 python3-pip
    hostnamectl set-hostname tethys-k3s-server
  EOT

  k3s_agent_user_data = <<-EOT
    #!/bin/bash
    set -eux
    dnf update -y
    dnf install -y git python3 python3-pip
    hostnamectl set-hostname tethys-k3s-agent
  EOT
}

resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.jenkins.id]
  iam_instance_profile   = aws_iam_instance_profile.jenkins.name
  user_data              = local.jenkins_user_data

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = {
    Name = "${local.name_prefix}-jenkins"
    Role = "jenkins"
  }
}

resource "aws_instance" "k3s_server" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.k3s_server.id]
  user_data              = local.k3s_server_user_data

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = {
    Name = "${local.name_prefix}-k3s-server"
    Role = "k3s-server"
  }
}

resource "aws_instance" "k3s_agent" {
  count                  = var.k3s_agent_count
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.public[count.index % length(aws_subnet.public)].id
  vpc_security_group_ids = [aws_security_group.k3s_agent.id]
  iam_instance_profile   = aws_iam_instance_profile.k3s_agent.name
  user_data              = local.k3s_agent_user_data

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = {
    Name = "${local.name_prefix}-k3s-agent-${count.index}"
    Role = "k3s-agent"
  }
}

# Render an Ansible inventory file so the user can `ansible-playbook` right away.
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory.ini"
  file_permission = "0600"

  content = <<-EOT
    [jenkins]
    jenkins ansible_host=${aws_instance.jenkins.public_ip}

    [k3s_server]
    k3s-server ansible_host=${aws_instance.k3s_server.public_ip} k3s_server_private_ip=${aws_instance.k3s_server.private_ip}

    [k3s_agents]
    %{for i, ip in aws_instance.k3s_agent[*].public_ip~}
    k3s-agent-${i} ansible_host=${ip}
    %{endfor~}

    [k3s_cluster:children]
    k3s_server
    k3s_agents

    [all:vars]
    ansible_user=ec2-user
    ansible_ssh_private_key_file=~/.ssh/${var.key_pair_name}.pem
    ansible_ssh_common_args='-o StrictHostKeyChecking=no'
    k3s_server_url=https://${aws_instance.k3s_server.private_ip}:6443
    s3_bucket=${aws_s3_bucket.files.bucket}
    aws_region=${var.aws_region}
    rds_endpoint=${aws_db_instance.postgres.address}
    rds_port=${aws_db_instance.postgres.port}
    rds_database=${var.db_name}
    rds_username=${var.db_username}
  EOT
}
