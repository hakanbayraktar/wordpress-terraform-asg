# EFS File System
resource "aws_efs_file_system" "wordpress" {
  creation_token = "${var.project_name}-efs"
  encrypted      = true

  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name = "${var.project_name}-efs"
  }
}

# EFS Mount Targets
resource "aws_efs_mount_target" "wordpress" {
  count           = length(var.private_app_subnet_ids)
  file_system_id  = aws_efs_file_system.wordpress.id
  subnet_id       = var.private_app_subnet_ids[count.index]
  security_groups = [var.efs_security_group_id]
}

# EFS Access Point for WordPress
resource "aws_efs_access_point" "wordpress" {
  file_system_id = aws_efs_file_system.wordpress.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/wordpress"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = {
    Name = "${var.project_name}-efs-ap"
  }
}