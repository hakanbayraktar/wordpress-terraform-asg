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

# User data script for WordPress installation
locals {
  user_data = <<-EOF
              #!/bin/bash
              set -e

              # Update system
              dnf update -y

              # Install Apache, PHP, and required modules
              dnf install -y httpd php php-mysqlnd php-fpm php-json php-gd php-mbstring php-xml amazon-efs-utils stress

              # Start and enable Apache
              systemctl start httpd
              systemctl enable httpd

              # Mount EFS
              mkdir -p /var/www/html
              echo "${var.efs_id}:/ /var/www/html efs _netdev,tls,iam 0 0" >> /etc/fstab
              mount -a

              # Download and install WordPress (only if not already installed)
              if [ ! -f /var/www/html/wp-config.php ]; then
                cd /tmp
                curl -O https://wordpress.org/latest.tar.gz
                tar -xzf latest.tar.gz
                cp -r wordpress/* /var/www/html/

                # Create WordPress config
                cd /var/www/html
                cp wp-config-sample.php wp-config.php

                # Configure database settings
                sed -i "s/database_name_here/${var.db_name}/" wp-config.php
                sed -i "s/username_here/${var.db_username}/" wp-config.php
                sed -i "s/password_here/${var.db_password}/" wp-config.php
                sed -i "s/localhost/${var.db_host}/" wp-config.php

                # Add security keys
                curl -s https://api.wordpress.org/secret-key/1.1/salt/ >> wp-config.php
              fi

              # Set permissions
              chown -R apache:apache /var/www/html
              chmod -R 755 /var/www/html

              # Restart Apache
              systemctl restart httpd
              EOF
}

# Launch Template
resource "aws_launch_template" "wordpress" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = var.wordpress_instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [var.wordpress_security_group_id]

  user_data = base64encode(local.user_data)

  iam_instance_profile {
    name = aws_iam_instance_profile.wordpress.name
  }

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-wordpress"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress" {
  name                = "${var.project_name}-asg"
  vpc_zone_identifier = var.private_app_subnet_ids
  target_group_arns   = [var.target_group_arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  launch_template {
    id      = aws_launch_template.wordpress.id
    version = "$Latest"
  }

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances"
  ]

  tag {
    key                 = "Name"
    value               = "${var.project_name}-wordpress-asg"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.project_name}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.wordpress.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.project_name}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.wordpress.name
}

# IAM Role for EC2 instances
resource "aws_iam_role" "wordpress" {
  name_prefix = "${var.project_name}-wordpress-role-"

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
}

# IAM Policy for EFS access
resource "aws_iam_role_policy" "efs_access" {
  name_prefix = "${var.project_name}-efs-policy-"
  role        = aws_iam_role.wordpress.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:DescribeFileSystems"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach SSM policy for session manager
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.wordpress.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "wordpress" {
  name_prefix = "${var.project_name}-wordpress-profile-"
  role        = aws_iam_role.wordpress.name
}