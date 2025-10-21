# OpenVPN Server Module
# Separate VPC for secure VPN access

# VPC for OpenVPN (completely isolated from WordPress VPC)
resource "aws_vpc" "openvpn" {
  cidr_block           = var.vpn_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-openvpn-vpc"
  }
}

# Internet Gateway for VPN VPC
resource "aws_internet_gateway" "openvpn" {
  vpc_id = aws_vpc.openvpn.id

  tags = {
    Name = "${var.project_name}-openvpn-igw"
  }
}

# Public Subnet for OpenVPN Server
resource "aws_subnet" "openvpn_public" {
  vpc_id                  = aws_vpc.openvpn.id
  cidr_block              = var.vpn_subnet_cidr
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-openvpn-public-subnet"
  }
}

# Route Table for VPN VPC
resource "aws_route_table" "openvpn_public" {
  vpc_id = aws_vpc.openvpn.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.openvpn.id
  }

  tags = {
    Name = "${var.project_name}-openvpn-public-rt"
  }
}

# Route Table Association
resource "aws_route_table_association" "openvpn_public" {
  subnet_id      = aws_subnet.openvpn_public.id
  route_table_id = aws_route_table.openvpn_public.id
}

# Security Group for OpenVPN Server
resource "aws_security_group" "openvpn" {
  name        = "${var.project_name}-openvpn-sg"
  description = "Security group for OpenVPN server"
  vpc_id      = aws_vpc.openvpn.id

  # OpenVPN port (UDP 1194)
  ingress {
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "OpenVPN UDP"
  }

  # SSH for initial setup (will be removed after setup)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH for initial setup - REMOVE AFTER VPN WORKS"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-openvpn-sg"
  }
}

# Elastic IP for OpenVPN Server
resource "aws_eip" "openvpn" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-openvpn-eip"
  }

  depends_on = [aws_internet_gateway.openvpn]
}

# IAM Role for OpenVPN Instance
resource "aws_iam_role" "openvpn" {
  name = "${var.project_name}-openvpn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-openvpn-role"
  }
}

# Attach SSM policy for remote management
resource "aws_iam_role_policy_attachment" "openvpn_ssm" {
  role       = aws_iam_role.openvpn.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance Profile
resource "aws_iam_instance_profile" "openvpn" {
  name = "${var.project_name}-openvpn-profile"
  role = aws_iam_role.openvpn.name
}

# Latest Ubuntu AMI (OpenVPN script works best on Ubuntu/Debian)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# OpenVPN Server Instance
resource "aws_instance" "openvpn" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.openvpn_public.id
  vpc_security_group_ids = [aws_security_group.openvpn.id]
  iam_instance_profile   = aws_iam_instance_profile.openvpn.name

  user_data = templatefile("${path.module}/user-data.sh", {
    vpn_user     = var.vpn_user
    project_name = var.project_name
  })

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-openvpn-server"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Associate Elastic IP with OpenVPN Instance
resource "aws_eip_association" "openvpn" {
  instance_id   = aws_instance.openvpn.id
  allocation_id = aws_eip.openvpn.id
}

# Automatic VPN config download after OpenVPN installation
resource "null_resource" "download_vpn_config" {
  # Trigger when VPN instance or EIP changes
  triggers = {
    instance_id = aws_instance.openvpn.id
    eip         = aws_eip.openvpn.public_ip
  }

  # Wait for OpenVPN installation and download config file
  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e

      VPN_IP="${aws_eip.openvpn.public_ip}"
      VPN_USER="${var.vpn_user}"
      VPN_DIR="$HOME/.vpn"
      SSH_KEY="$HOME/.ssh/${var.key_name}.pem"

      echo ""
      echo "=========================================="
      echo "Waiting for OpenVPN installation..."
      echo "=========================================="
      echo ""
      echo "VPN Server IP: $VPN_IP"
      echo "VPN User: $VPN_USER"
      echo ""

      # Check SSH key exists
      if [ ! -f "$SSH_KEY" ]; then
        echo "ERROR: SSH key not found at $SSH_KEY"
        echo "Please create the key pair first:"
        echo "  aws ec2 create-key-pair --key-name ${var.key_name} --query 'KeyMaterial' --output text > $SSH_KEY"
        echo "  chmod 400 $SSH_KEY"
        exit 1
      fi

      # Create VPN directory
      mkdir -p "$VPN_DIR"

      # Wait for instance to be ready (SSH accessible)
      echo "Waiting for VPN instance to be SSH accessible..."
      MAX_SSH_WAIT=60
      SSH_WAIT=0
      while [ $SSH_WAIT -lt $MAX_SSH_WAIT ]; do
        if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            -o BatchMode=yes ubuntu@$VPN_IP "echo 'SSH ready'" >/dev/null 2>&1; then
          echo "✓ SSH connection established"
          break
        fi
        SSH_WAIT=$((SSH_WAIT + 1))
        echo "  Waiting for SSH... ($SSH_WAIT/$MAX_SSH_WAIT)"
        sleep 5
      done

      if [ $SSH_WAIT -eq $MAX_SSH_WAIT ]; then
        echo "WARNING: SSH connection timeout. VPN config download may fail."
      fi

      # Wait for OpenVPN config file to be created
      echo ""
      echo "Waiting for OpenVPN config file to be generated..."
      echo "This can take 3-5 minutes..."
      echo ""

      MAX_ATTEMPTS=40
      ATTEMPT=0

      while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        ATTEMPT=$((ATTEMPT + 1))

        # Check if file exists
        if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
            -o BatchMode=yes ubuntu@$VPN_IP "test -f /home/ubuntu/$VPN_USER.ovpn" 2>/dev/null; then
          echo "✓ OpenVPN config file is ready!"
          break
        fi

        if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
          echo ""
          echo "WARNING: Config file not found after $MAX_ATTEMPTS attempts"
          echo "The OpenVPN installation may still be running in the background."
          echo ""
          echo "You can manually download it later using:"
          echo "  ./scripts/download-vpn-config.sh"
          echo ""
          exit 0  # Don't fail terraform, just warn
        fi

        # Show progress every 5 attempts
        if [ $((ATTEMPT % 5)) -eq 0 ]; then
          echo "  Still waiting... (attempt $ATTEMPT/$MAX_ATTEMPTS)"
        fi

        sleep 10
      done

      # Download the config file
      echo ""
      echo "Downloading VPN configuration file..."

      if scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o BatchMode=yes \
          ubuntu@$VPN_IP:/home/ubuntu/$VPN_USER.ovpn \
          "$VPN_DIR/$VPN_USER.ovpn" 2>/dev/null; then

        echo ""
        echo "=========================================="
        echo "✓ VPN Config Downloaded Successfully!"
        echo "=========================================="
        echo ""
        echo "Config file location: $VPN_DIR/$VPN_USER.ovpn"
        echo ""
        echo "To connect to VPN:"
        echo "  sudo openvpn --config $VPN_DIR/$VPN_USER.ovpn"
        echo ""
        echo "Or import into Tunnelblick/OpenVPN GUI"
        echo ""

      else
        echo ""
        echo "WARNING: Failed to download VPN config automatically"
        echo ""
        echo "You can manually download it using:"
        echo "  ./scripts/download-vpn-config.sh"
        echo ""
      fi
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [
    aws_eip_association.openvpn,
    aws_instance.openvpn
  ]
}
