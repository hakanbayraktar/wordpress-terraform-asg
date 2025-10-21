#!/bin/bash
# Deploy Production Environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "===================================="
echo "WordPress Prod Environment Deployment"
echo "===================================="
echo ""
echo "⚠️  WARNING: Production Deployment ⚠️"
echo ""
echo "Environment: PRODUCTION"
echo "Config File: terraform.prod.tfvars"
echo ""
echo "Configuration:"
echo "  - WordPress: t3.medium"
echo "  - Bastion: t2.micro"
echo "  - RDS: db.t3.small (50GB)"
echo "  - ASG: 2-6 instances (desired: 2)"
echo "  - VPN: Enabled"
echo ""

# Check if tfvars file exists
if [ ! -f "terraform.prod.tfvars" ]; then
    echo "Error: terraform.prod.tfvars not found!"
    exit 1
fi

# Extra confirmation for production
echo "⚠️  This will deploy to PRODUCTION"
read -p "Are you sure you want to continue? (type 'yes' to proceed): " -r
echo

if [[ $REPLY != "yes" ]]; then
    echo "Deployment cancelled."
    exit 0
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
terraform plan -var-file="terraform.prod.tfvars" -out=prod.tfplan

echo ""
read -p "Do you want to apply these changes? (type 'yes' to proceed): " -r
echo

if [[ $REPLY != "yes" ]]; then
    echo "Deployment cancelled."
    rm -f prod.tfplan
    exit 0
fi

# Apply the plan
echo ""
echo "===================================="
echo "Applying changes..."
echo "===================================="
terraform apply prod.tfplan

# Clean up plan file
rm -f prod.tfplan

echo ""
echo "===================================="
echo "✓ Production Environment Deployed!"
echo "===================================="
echo ""

# Show outputs
terraform output

echo ""
echo "Next steps:"
echo "1. Wait 5-10 minutes for VPN installation"
echo "2. Download VPN config: ./scripts/download-vpn-config.sh"
echo "3. Connect to VPN: sudo openvpn --config ~/.vpn/hakan.ovpn"
echo "4. Confirm SNS email subscription"
echo "5. Access WordPress: Check wordpress_url output above"
echo "6. Complete WordPress installation"
echo "7. Set up monitoring and backups"
echo ""
