#!/bin/bash
# RDS SSH Tunnel Script

set -e

echo "===================================="
echo "RDS SSH Tunnel via Bastion Host"
echo "===================================="
echo ""

# Get Terraform outputs
RDS_ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null | cut -d: -f1)
BASTION_IP=$(terraform output -raw bastion_public_ip 2>/dev/null)
LOCAL_PORT=3306

if [ -z "$RDS_ENDPOINT" ] || [ -z "$BASTION_IP" ]; then
    echo "Error: Could not get Terraform outputs"
    echo "Please run 'terraform apply' first"
    exit 1
fi

# Check if port is already in use
if lsof -Pi :$LOCAL_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "Warning: Port $LOCAL_PORT is already in use"
    echo ""
    echo "Options:"
    echo "  1. Stop the service using port $LOCAL_PORT"
    echo "  2. Edit this script to use a different LOCAL_PORT (e.g., 3307)"
    echo ""
    exit 1
fi

echo "Creating SSH tunnel to RDS..."
echo "  Local Port: $LOCAL_PORT"
echo "  RDS Endpoint: $RDS_ENDPOINT"
echo "  Bastion IP: $BASTION_IP"
echo ""
echo "===================================="
echo "MySQL Connection Details:"
echo "===================================="
echo "  Host: 127.0.0.1"
echo "  Port: $LOCAL_PORT"
echo "  Username: admin"
echo "  Database: wordpress"
echo "  Password: <your db_password from terraform.tfvars>"
echo ""
echo "Example MySQL command:"
echo "  mysql -h 127.0.0.1 -P $LOCAL_PORT -u admin -p"
echo ""
echo "Press Ctrl+C to close tunnel"
echo "===================================="
echo ""

ssh -i ~/.ssh/wordpress-key.pem \
    -N -L ${LOCAL_PORT}:${RDS_ENDPOINT}:3306 \
    ec2-user@${BASTION_IP}
