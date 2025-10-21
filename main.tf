terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  project_name            = var.project_name
  vpc_cidr                = var.vpc_cidr
  public_subnet_cidrs     = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs = var.private_db_subnet_cidrs
  availability_zones      = var.availability_zones
}

# OpenVPN Module (Separate VPC for secure access)
module "openvpn" {
  source = "./modules/openvpn"
  count  = var.enable_vpn ? 1 : 0

  project_name       = var.project_name
  vpn_vpc_cidr       = var.vpn_vpc_cidr
  vpn_subnet_cidr    = var.vpn_subnet_cidr
  availability_zones = var.availability_zones
  instance_type      = var.vpn_instance_type
  key_name           = var.key_name
  vpn_user           = var.vpn_user
}

# Security Groups Module
module "security_groups" {
  source = "./modules/security_groups"

  project_name     = var.project_name
  vpc_id           = module.vpc.vpc_id
  vpc_cidr         = var.vpc_cidr
  allowed_ssh_cidr = var.allowed_ssh_cidr
  vpn_server_ip    = var.enable_vpn ? module.openvpn[0].vpn_server_public_ip : ""
}

# RDS Module
module "rds" {
  source = "./modules/rds"

  project_name           = var.project_name
  db_subnet_group_name   = module.vpc.db_subnet_group_name
  db_security_group_id   = module.security_groups.rds_sg_id
  db_name                = var.db_name
  db_username            = var.db_username
  db_password            = var.db_password
  db_instance_class      = var.db_instance_class
  allocated_storage      = var.allocated_storage
}

# EFS Module
module "efs" {
  source = "./modules/efs"

  project_name             = var.project_name
  private_app_subnet_ids   = module.vpc.private_app_subnet_ids
  efs_security_group_id    = module.security_groups.efs_sg_id
}

# ALB Module
module "alb" {
  source = "./modules/alb"

  project_name         = var.project_name
  vpc_id               = module.vpc.vpc_id
  public_subnet_ids    = module.vpc.public_subnet_ids
  alb_security_group_id = module.security_groups.alb_sg_id
}

# Bastion Host Module
module "bastion" {
  source = "./modules/bastion"

  project_name              = var.project_name
  public_subnet_id          = module.vpc.public_subnet_ids[0]
  bastion_security_group_id = module.security_groups.bastion_sg_id
  key_name                  = var.key_name
  bastion_instance_type     = var.bastion_instance_type
}

# Auto Scaling Module
module "autoscaling" {
  source = "./modules/autoscaling"

  project_name              = var.project_name
  private_app_subnet_ids    = module.vpc.private_app_subnet_ids
  wordpress_security_group_id = module.security_groups.wordpress_sg_id
  target_group_arn          = module.alb.target_group_arn
  key_name                  = var.key_name
  wordpress_instance_type   = var.wordpress_instance_type
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity

  # WordPress Configuration
  db_host     = module.rds.db_endpoint
  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password
  efs_id      = module.efs.efs_id
}

# CloudWatch Alarms Module
module "cloudwatch" {
  source = "./modules/cloudwatch"

  project_name           = var.project_name
  autoscaling_group_name = module.autoscaling.autoscaling_group_name
  scale_up_policy_arn    = module.autoscaling.scale_up_policy_arn
  scale_down_policy_arn  = module.autoscaling.scale_down_policy_arn
  alarm_email            = var.alarm_email
}