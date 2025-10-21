#!/bin/bash
#
# Post-Deployment Information and Access Guide
#
# This script displays all access information and provides step-by-step
# instructions after terraform apply completes successfully.
#
# Usage: ./scripts/post-deployment.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo ""
echo -e "${BOLD}${CYAN}========================================${NC}"
echo -e "${BOLD}${CYAN}WordPress Auto Scaling - Deployment Complete!${NC}"
echo -e "${BOLD}${CYAN}========================================${NC}"
echo ""

# Check if terraform state exists
if [ ! -f "terraform.tfstate" ]; then
    echo -e "${RED}Error: terraform.tfstate not found!${NC}"
    echo "Please run 'terraform apply' first."
    exit 1
fi

# Get outputs from terraform
echo -e "${YELLOW}Fetching deployment information...${NC}"
echo ""

WORDPRESS_URL=$(terraform output -raw wordpress_url 2>/dev/null || echo "N/A")
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "N/A")
BASTION_IP=$(terraform output -raw bastion_public_ip 2>/dev/null || echo "N/A")
VPN_SERVER_IP=$(terraform output -raw vpn_server_ip 2>/dev/null || echo "N/A")
VPN_USER=$(terraform output -raw vpn_user 2>/dev/null || echo "N/A")
RDS_ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null || echo "N/A")
EFS_ID=$(terraform output -raw efs_id 2>/dev/null || echo "N/A")
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "N/A")
ASG_NAME=$(terraform output -raw autoscaling_group_name 2>/dev/null || echo "N/A")
REGION=$(grep 'aws_region' terraform.dev.tfvars | cut -d'"' -f2)
DB_PASSWORD=$(grep 'db_password' terraform.dev.tfvars | cut -d'"' -f2)

# Display main access information
echo -e "${BOLD}${GREEN}=== MAIN ACCESS INFORMATION ===${NC}"
echo ""

echo -e "${BOLD}1. WordPress Website${NC}"
echo -e "   URL: ${CYAN}${WORDPRESS_URL}${NC}"
echo -e "   Test: ${YELLOW}curl -I ${WORDPRESS_URL}${NC}"
echo ""

echo -e "${BOLD}2. VPN Server${NC}"
echo -e "   IP: ${CYAN}${VPN_SERVER_IP}${NC}"
echo -e "   User: ${CYAN}${VPN_USER}${NC}"
echo -e "   Config: ${CYAN}~/.vpn/${VPN_USER}.ovpn${NC}"
echo ""

echo -e "${BOLD}3. Bastion Host${NC}"
echo -e "   IP: ${CYAN}${BASTION_IP}${NC}"
echo -e "   User: ${CYAN}ec2-user${NC}"
echo -e "   Key: ${CYAN}~/.ssh/wordpress-key.pem${NC}"
echo -e "   ${RED}Note: Only accessible through VPN!${NC}"
echo ""

echo -e "${BOLD}4. RDS MySQL${NC}"
echo -e "   Endpoint: ${CYAN}${RDS_ENDPOINT}${NC}"
echo -e "   Username: ${CYAN}admin${NC}"
echo -e "   Password: ${CYAN}${DB_PASSWORD}${NC}"
echo -e "   Database: ${CYAN}wordpress_db${NC}"
echo -e "   ${RED}Note: Private subnet - SSH tunnel required${NC}"
echo ""

echo -e "${BOLD}5. AWS Resources${NC}"
echo -e "   VPC ID: ${CYAN}${VPC_ID}${NC}"
echo -e "   EFS ID: ${CYAN}${EFS_ID}${NC}"
echo -e "   ASG Name: ${CYAN}${ASG_NAME}${NC}"
echo -e "   Region: ${CYAN}${REGION}${NC}"
echo ""

# Step-by-step access guide
echo -e "${BOLD}${GREEN}=== STEP-BY-STEP ACCESS GUIDE ===${NC}"
echo ""

echo -e "${BOLD}${YELLOW}Step 1: Download VPN Configuration (Wait 5 minutes for OpenVPN installation)${NC}"
echo ""
echo "   ${CYAN}# Wait 5 minutes after deployment${NC}"
echo "   sleep 300"
echo ""
echo "   ${CYAN}# Run the automated download script${NC}"
echo "   ./scripts/download-vpn-config.sh"
echo ""
echo "   ${CYAN}# Or download manually:${NC}"
echo "   ssh -i ~/.ssh/wordpress-key.pem ubuntu@${VPN_SERVER_IP} \\"
echo "       'sudo cp /home/ubuntu/${VPN_USER}.ovpn /tmp/ && sudo chmod 644 /tmp/${VPN_USER}.ovpn'"
echo "   scp -i ~/.ssh/wordpress-key.pem ubuntu@${VPN_SERVER_IP}:/tmp/${VPN_USER}.ovpn ~/.vpn/"
echo ""

echo -e "${BOLD}${YELLOW}Step 2: Connect to VPN${NC}"
echo ""
echo "   ${CYAN}# Terminal 1 - Start VPN (keep running)${NC}"
echo "   sudo openvpn --config ~/.vpn/${VPN_USER}.ovpn"
echo ""
echo "   ${GREEN}Wait for: \"Initialization Sequence Completed\"${NC}"
echo ""

echo -e "${BOLD}${YELLOW}Step 3: Access Bastion Host (New Terminal - VPN must be running)${NC}"
echo ""
echo "   ssh -i ~/.ssh/wordpress-key.pem ec2-user@${BASTION_IP}"
echo ""

echo -e "${BOLD}${YELLOW}Step 4: Access RDS MySQL via SSH Tunnel${NC}"
echo ""
echo "   ${CYAN}# Terminal 2 - SSH Tunnel (keep running, VPN must be active)${NC}"
echo "   ssh -i ~/.ssh/wordpress-key.pem \\"
echo "       -L 3306:${RDS_ENDPOINT%:*}:3306 \\"
echo "       ec2-user@${BASTION_IP} \\"
echo "       -N"
echo ""
echo "   ${CYAN}# Terminal 3 - MySQL Client${NC}"
echo "   mysql -h 127.0.0.1 -P 3306 -u admin -p${DB_PASSWORD}"
echo ""
echo "   ${CYAN}# Inside MySQL:${NC}"
echo "   USE wordpress_db;"
echo "   SHOW TABLES;"
echo ""

echo -e "${BOLD}${YELLOW}Step 5: Access WordPress Instances (Through Bastion)${NC}"
echo ""
echo "   ${CYAN}# First SSH to Bastion${NC}"
echo "   ssh -i ~/.ssh/wordpress-key.pem ec2-user@${BASTION_IP}"
echo ""
echo "   ${CYAN}# From Bastion, find WordPress instances:${NC}"
echo "   aws ec2 describe-instances \\"
echo "       --filters \"Name=tag:aws:autoscaling:groupName,Values=${ASG_NAME}\" \\"
echo "                 \"Name=instance-state-name,Values=running\" \\"
echo "       --query 'Reservations[*].Instances[*].[InstanceId,PrivateIpAddress]' \\"
echo "       --region ${REGION} \\"
echo "       --output table"
echo ""
echo "   ${CYAN}# SSH to WordPress instance (using ProxyCommand is easier):${NC}"
echo "   ssh -i ~/.ssh/wordpress-key.pem \\"
echo "       -o ProxyCommand=\"ssh -W %h:%p -i ~/.ssh/wordpress-key.pem ec2-user@${BASTION_IP}\" \\"
echo "       ec2-user@<WORDPRESS_PRIVATE_IP>"
echo ""

# Quick reference commands
echo -e "${BOLD}${GREEN}=== QUICK REFERENCE COMMANDS ===${NC}"
echo ""

echo -e "${BOLD}Monitor Auto Scaling:${NC}"
echo "   watch -n 10 'aws autoscaling describe-auto-scaling-groups \\"
echo "       --auto-scaling-group-names ${ASG_NAME} \\"
echo "       --region ${REGION} \\"
echo "       --query \"AutoScalingGroups[0].{Desired:DesiredCapacity,Current:length(Instances)}\"'"
echo ""

echo -e "${BOLD}Check CloudWatch Alarms:${NC}"
echo "   aws cloudwatch describe-alarms \\"
echo "       --alarm-name-prefix wordpress-dev \\"
echo "       --region ${REGION} \\"
echo "       --output table"
echo ""

echo -e "${BOLD}View WordPress Instances:${NC}"
echo "   aws ec2 describe-instances \\"
echo "       --filters \"Name=tag:aws:autoscaling:groupName,Values=${ASG_NAME}\" \\"
echo "                 \"Name=instance-state-name,Values=running\" \\"
echo "       --region ${REGION} \\"
echo "       --output table"
echo ""

# Testing section
echo -e "${BOLD}${GREEN}=== AUTOMATED TESTING ===${NC}"
echo ""
echo "Run comprehensive tests:"
echo "   ${CYAN}./scripts/run-tests.sh${NC}"
echo ""
echo "This will test:"
echo "   - WordPress web access"
echo "   - VPN connectivity"
echo "   - Bastion access"
echo "   - RDS connectivity"
echo "   - Auto Scaling triggers"
echo "   - CloudWatch alarms"
echo ""

# SNS Email reminder
echo -e "${BOLD}${RED}=== IMPORTANT: SNS EMAIL CONFIRMATION ===${NC}"
echo ""
echo "Check your email: ${YELLOW}$(grep 'alarm_email' terraform.dev.tfvars | cut -d'"' -f2)${NC}"
echo ""
echo "You should have received an email from AWS SNS:"
echo "   Subject: ${CYAN}AWS Notification - Subscription Confirmation${NC}"
echo ""
echo "Click the \"Confirm subscription\" link to receive CloudWatch alarm emails!"
echo ""
echo "Verify subscription:"
echo "   aws sns list-subscriptions-by-topic \\"
echo "       --topic-arn $(terraform output -raw sns_topic_arn 2>/dev/null) \\"
echo "       --region ${REGION}"
echo ""

# Summary
echo -e "${BOLD}${GREEN}=== DEPLOYMENT SUMMARY ===${NC}"
echo ""
echo -e "${GREEN}✓${NC} Infrastructure deployed successfully"
echo -e "${GREEN}✓${NC} WordPress: ${WORDPRESS_URL}"
echo -e "${GREEN}✓${NC} VPN Server: ${VPN_SERVER_IP}"
echo -e "${GREEN}✓${NC} Bastion Host: ${BASTION_IP}"
echo -e "${GREEN}✓${NC} RDS MySQL: ${RDS_ENDPOINT}"
echo -e "${YELLOW}⏳${NC} VPN Config: Wait 5 minutes, then run ./scripts/download-vpn-config.sh"
echo -e "${YELLOW}⏳${NC} SNS Email: Confirm subscription in your email"
echo ""

echo -e "${BOLD}${CYAN}========================================${NC}"
echo -e "${BOLD}${CYAN}For detailed testing: ./scripts/run-tests.sh${NC}"
echo -e "${BOLD}${CYAN}========================================${NC}"
echo ""
