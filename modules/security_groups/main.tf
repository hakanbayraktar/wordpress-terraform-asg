# ALB Security Group
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-sg-"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Bastion Host Security Group
resource "aws_security_group" "bastion" {
  name_prefix = "${var.project_name}-bastion-sg-"
  description = "Security group for Bastion Host - SSH only from VPN Server"
  vpc_id      = var.vpc_id

  # SSH access from VPN server ONLY (when VPN is enabled)
  # This provides secure access - users must connect to VPN first
  dynamic "ingress" {
    for_each = var.vpn_server_ip != "" ? [1] : []
    content {
      description = "SSH from OpenVPN Server ONLY"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["${var.vpn_server_ip}/32"]
    }
  }

  # Fallback: SSH from allowed CIDR (when VPN is not configured yet)
  # Remove this after VPN is set up for maximum security
  dynamic "ingress" {
    for_each = var.vpn_server_ip == "" ? [1] : []
    content {
      description = "SSH from allowed CIDR (TEMPORARY - use VPN)"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.allowed_ssh_cidr]
    }
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-bastion-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# WordPress Security Group
resource "aws_security_group" "wordpress" {
  name_prefix = "${var.project_name}-wordpress-sg-"
  description = "Security group for WordPress instances"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-wordpress-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# RDS Security Group
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-rds-sg-"
  description = "Security group for RDS MySQL"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL from WordPress"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress.id]
  }

  ingress {
    description     = "MySQL from Bastion (for SSH tunnel and management)"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# EFS Security Group
resource "aws_security_group" "efs" {
  name_prefix = "${var.project_name}-efs-sg-"
  description = "Security group for EFS"
  vpc_id      = var.vpc_id

  ingress {
    description     = "NFS from WordPress"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-efs-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}