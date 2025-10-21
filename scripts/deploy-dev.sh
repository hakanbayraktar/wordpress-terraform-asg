#!/bin/bash
# Deploy Development Environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "===================================="
echo "WordPress Dev Environment Deployment"
echo "===================================="
echo ""
echo "Environment: DEV"
echo "Config File: terraform.dev.tfvars"
echo ""
echo "Configuration:"
echo "  - WordPress: t2.micro"
echo "  - Bastion: t2.micro"
echo "  - RDS: db.t3.micro"
echo "  - ASG: 1-2 instances (desired: 1)"
echo "  - VPN: Enabled"
echo ""

# Check if tfvars file exists
if [ ! -f "terraform.dev.tfvars" ]; then
    echo "Error: terraform.dev.tfvars not found!"
    exit 1
fi

# Initialize if needed
if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
fi

# Show what will be created/changed
echo ""
echo "===================================="
echo "Planning changes..."
echo "===================================="
terraform plan -var-file="terraform.dev.tfvars" -out=dev.tfplan

echo ""
read -p "Do you want to apply these changes? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy](es)?$ ]]; then
    echo "Deployment cancelled."
    rm -f dev.tfplan
    exit 0
fi

# Apply the plan
echo ""
echo "===================================="
echo "Applying changes..."
echo "===================================="
terraform apply dev.tfplan

# Clean up plan file
rm -f dev.tfplan

echo ""
echo "===================================="
echo "✓ Dev Environment Deployed!"
echo "===================================="
echo ""

# Show outputs
terraform output

echo ""
echo "Next steps:"
echo "1. Wait 5-10 minutes for VPN installation"
echo "2. Download VPN config: ./scripts/download-vpn-config.sh"
echo "3. Connect to VPN: sudo openvpn --config ~/.vpn/hakan.ovpn"
echo "4. Access WordPress: Check wordpress_url output above"
echo ""
