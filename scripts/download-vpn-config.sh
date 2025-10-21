#!/bin/bash
# Download OpenVPN client configuration file
# This script can be used if the automatic download during terraform apply failed

set -e

echo "===================================="
echo "OpenVPN Config Download Script"
echo "===================================="
echo ""

# Check if terraform state exists
if [ ! -f "terraform.tfstate" ]; then
    echo "Error: terraform.tfstate not found"
    echo "Please run 'terraform apply' first"
    exit 1
fi

# Check if VPN is enabled
if ! terraform output -raw vpn_server_ip &>/dev/null; then
    echo "Error: Cannot get VPN server IP from Terraform outputs"
    echo "Make sure you've run 'terraform apply' with enable_vpn=true"
    exit 1
fi

VPN_SERVER_IP=$(terraform output -raw vpn_server_ip 2>/dev/null)
VPN_USER=$(terraform output -raw vpn_user 2>/dev/null)
KEY_NAME=$(grep 'key_name' terraform.dev.tfvars | cut -d'"' -f2 | head -1)

if [ "$VPN_SERVER_IP" == "VPN not enabled" ]; then
    echo "Error: VPN is not enabled in your configuration"
    echo ""
    echo "To enable VPN:"
    echo "1. Edit terraform.tfvars"
    echo "2. Add: enable_vpn = true"
    echo "3. Run: terraform apply"
    echo ""
    exit 1
fi

if [ -z "$VPN_SERVER_IP" ] || [ -z "$VPN_USER" ] || [ -z "$KEY_NAME" ]; then
    echo "Error: Could not retrieve VPN configuration from Terraform"
    exit 1
fi

# SSH key location
SSH_KEY="$HOME/.ssh/${KEY_NAME}.pem"

# Check if SSH key exists
if [ ! -f "$SSH_KEY" ]; then
    echo "Error: SSH key not found at $SSH_KEY"
    echo ""
    echo "Please create the SSH key pair first:"
    echo "  aws ec2 delete-key-pair --key-name $KEY_NAME  # Delete old key if exists"
    echo "  aws ec2 create-key-pair --key-name $KEY_NAME --query 'KeyMaterial' --output text > $SSH_KEY"
    echo "  chmod 400 $SSH_KEY"
    echo ""
    exit 1
fi

# Verify SSH key permissions
SSH_KEY_PERMS=$(stat -f %A "$SSH_KEY" 2>/dev/null || stat -c %a "$SSH_KEY" 2>/dev/null)
if [ "$SSH_KEY_PERMS" != "400" ] && [ "$SSH_KEY_PERMS" != "600" ]; then
    echo "Warning: SSH key has incorrect permissions ($SSH_KEY_PERMS)"
    echo "Fixing permissions..."
    chmod 400 "$SSH_KEY"
fi

# Create vpn directory in home folder
VPN_DIR="$HOME/.vpn"
mkdir -p "$VPN_DIR"

echo "VPN Server IP: $VPN_SERVER_IP"
echo "VPN User: $VPN_USER"
echo "SSH Key: $SSH_KEY"
echo "Download directory: $VPN_DIR"
echo ""

# Wait for OpenVPN installation to complete
echo "Checking if OpenVPN installation is complete..."
echo "This may take up to 5 minutes after terraform apply..."
echo ""

# Try to check if the file exists
MAX_ATTEMPTS=30
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))

    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
        ubuntu@${VPN_SERVER_IP} "test -f /home/ubuntu/${VPN_USER}.ovpn" 2>/dev/null; then
        echo "✓ OpenVPN config file is ready!"
        break
    fi

    if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
        echo ""
        echo "Warning: Config file not found after $MAX_ATTEMPTS attempts"
        echo "The OpenVPN installation may still be running."
        echo ""
        echo "You can:"
        echo "1. Wait a few more minutes and run this script again"
        echo "2. Check installation status:"
        echo "   ssh -i $SSH_KEY ubuntu@${VPN_SERVER_IP}"
        echo "   sudo tail -f /var/log/cloud-init-output.log"
        echo ""
        read -p "Do you want to try downloading anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
        break
    fi

    # Show progress
    if [ $((ATTEMPT % 3)) -eq 0 ]; then
        echo "Waiting for OpenVPN installation... (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    fi
    sleep 10
done

echo ""
echo "Downloading VPN configuration file..."
echo ""

# Download the .ovpn file
scp -i "$SSH_KEY" \
    -o StrictHostKeyChecking=no \
    -o BatchMode=yes \
    ubuntu@${VPN_SERVER_IP}:/home/ubuntu/${VPN_USER}.ovpn \
    "${VPN_DIR}/${VPN_USER}.ovpn"

if [ $? -eq 0 ]; then
    echo ""
    echo "===================================="
    echo "✓ Success!"
    echo "===================================="
    echo ""
    echo "VPN config downloaded to: ${VPN_DIR}/${VPN_USER}.ovpn"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Connect to VPN:"
    echo ""
    echo "   macOS/Linux (Terminal):"
    echo "   sudo openvpn --config ${VPN_DIR}/${VPN_USER}.ovpn"
    echo ""
    echo "   macOS (Tunnelblick):"
    echo "   - Install Tunnelblick from https://tunnelblick.net/"
    echo "   - Double-click ${VPN_DIR}/${VPN_USER}.ovpn"
    echo "   - Click 'Connect'"
    echo ""
    echo "   Windows:"
    echo "   - Install OpenVPN GUI"
    echo "   - Import ${VPN_DIR}/${VPN_USER}.ovpn"
    echo "   - Right-click system tray icon -> Connect"
    echo ""
    echo "2. After VPN is connected, access bastion:"
    echo "   ssh -i ~/.ssh/wordpress-key.pem ec2-user@$(terraform output -raw bastion_public_ip)"
    echo ""
    echo "3. Security Note:"
    echo "   - Bastion host now ONLY accepts SSH from VPN server IP"
    echo "   - You MUST be connected to VPN to access bastion"
    echo ""
    echo "===================================="
else
    echo ""
    echo "Error: Failed to download VPN configuration"
    echo ""
    echo "Manual download command:"
    echo "scp -i ~/.ssh/wordpress-key.pem ubuntu@${VPN_SERVER_IP}:/home/ubuntu/${VPN_USER}.ovpn ${VPN_DIR}/"
    echo ""
    exit 1
fi
