# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Bastion Host
resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.bastion_instance_type
  key_name      = var.key_name

  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [var.bastion_security_group_id]
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y mysql telnet
              EOF

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "${var.project_name}-bastion"
  }
}

# Elastic IP for Bastion (optional, for consistent IP)
resource "aws_eip" "bastion" {
  domain   = "vpc"
  instance = aws_instance.bastion.id

  tags = {
    Name = "${var.project_name}-bastion-eip"
  }
}