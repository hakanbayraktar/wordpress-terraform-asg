#!/bin/bash
# OpenVPN Server Installation Script
# Using Nyr/openvpn-install automated script

set -e

# Update system
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y curl wget git net-tools

# Wait for network to be fully ready
sleep 10

# Get the public IP
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Download OpenVPN installation script
cd /root
wget https://raw.githubusercontent.com/Nyr/openvpn-install/master/openvpn-install.sh -O openvpn-install.sh
chmod +x openvpn-install.sh

# Create auto-install configuration file
cat > /root/openvpn-auto-install.conf << EOF
# Auto-install configuration for OpenVPN
AUTO_INSTALL=y
APPROVE_INSTALL=y
APPROVE_IP=$PUBLIC_IP
IPV6_SUPPORT=n
PORT_CHOICE=1
PROTOCOL_CHOICE=1
DNS=1
COMPRESSION_ENABLED=n
CUSTOMIZE_ENC=n
CLIENT=${vpn_user}
PASS=1
EOF

# Run installation with auto-answers
export AUTO_INSTALL=y
export APPROVE_INSTALL=y
export APPROVE_IP=$PUBLIC_IP
export IPV6_SUPPORT=n
export PORT_CHOICE=1
export PROTOCOL_CHOICE=1
export DNS=1
export COMPRESSION_ENABLED=n
export CUSTOMIZE_ENC=n
export CLIENT=${vpn_user}
export PASS=1

# Install OpenVPN
echo "Installing OpenVPN..."
bash /root/openvpn-install.sh <<ANSWERS
1
1
1
1
${vpn_user}
1
ANSWERS

# Verify installation
sleep 5

# OpenVPN script creates client.ovpn, copy it to user-specific name
if [ -f "/root/client.ovpn" ]; then
    echo "OpenVPN client configuration found: /root/client.ovpn"

    # Copy to user-specific name
    cp /root/client.ovpn /root/${vpn_user}.ovpn
    chmod 600 /root/${vpn_user}.ovpn

    # Also copy to ubuntu home for easy SCP download
    cp /root/${vpn_user}.ovpn /home/ubuntu/${vpn_user}.ovpn
    chown ubuntu:ubuntu /home/ubuntu/${vpn_user}.ovpn
    chmod 644 /home/ubuntu/${vpn_user}.ovpn

    # Create a backup
    cp /root/${vpn_user}.ovpn /root/${vpn_user}-backup.ovpn

    # Log success
    echo "$(date) - OpenVPN installation completed successfully" >> /var/log/openvpn-setup.log
    echo "Config files created:" >> /var/log/openvpn-setup.log
    echo "  /root/client.ovpn" >> /var/log/openvpn-setup.log
    echo "  /root/${vpn_user}.ovpn" >> /var/log/openvpn-setup.log
    echo "  /home/ubuntu/${vpn_user}.ovpn (for SCP download)" >> /var/log/openvpn-setup.log
elif [ -f "/root/${vpn_user}.ovpn" ]; then
    echo "OpenVPN client configuration created successfully: /root/${vpn_user}.ovpn"

    # Copy to ubuntu home for easy download
    cp /root/${vpn_user}.ovpn /home/ubuntu/${vpn_user}.ovpn
    chown ubuntu:ubuntu /home/ubuntu/${vpn_user}.ovpn
    chmod 644 /home/ubuntu/${vpn_user}.ovpn

    # Log success
    echo "$(date) - OpenVPN installation completed successfully" >> /var/log/openvpn-setup.log
else
    echo "ERROR: Client configuration file not found!" >> /var/log/openvpn-setup.log
    ls -la /root/*.ovpn >> /var/log/openvpn-setup.log 2>&1
    exit 1
fi

# Enable IP forwarding (should already be done by script)
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Start and enable OpenVPN service
systemctl enable openvpn-server@server
systemctl start openvpn-server@server

# Check status
systemctl status openvpn-server@server >> /var/log/openvpn-setup.log

# Create a README for admin
cat > /root/README.txt << 'ENDREADME'
OpenVPN Server Setup Complete
==============================

VPN User: ${vpn_user}
Client Config: /root/${vpn_user}.ovpn

To download the .ovpn file to your local machine:
1. From your local terminal, run the download script:
   ./scripts/download-vpn-config.sh

2. Or manually using SCP:
   scp -i ~/.ssh/wordpress-key.pem ubuntu@VPN_SERVER_IP:/root/${vpn_user}.ovpn ~/vpn/

To add more users:
   sudo bash /root/openvpn-install.sh

To remove users:
   sudo bash /root/openvpn-install.sh

To check VPN status:
   sudo systemctl status openvpn-server@server

To view connected clients:
   sudo cat /var/log/openvpn/status.log

Security Notes:
- After VPN is working, remove SSH access from security group
- Only VPN clients should be able to access the bastion host
- Bastion host security group is configured to allow only this VPN server IP

ENDREADME

# Create status script
cat > /root/vpn-status.sh << 'ENDSTATUS'
#!/bin/bash
echo "==================================="
echo "OpenVPN Server Status"
echo "==================================="
echo ""
echo "Service Status:"
systemctl status openvpn-server@server --no-pager
echo ""
echo "==================================="
echo "Connected Clients:"
echo "==================================="
if [ -f /var/log/openvpn/status.log ]; then
    cat /var/log/openvpn/status.log
else
    echo "No status log found"
fi
echo ""
echo "==================================="
echo "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "==================================="
ENDSTATUS

chmod +x /root/vpn-status.sh

# Final log
echo "==================================" >> /var/log/openvpn-setup.log
echo "OpenVPN Setup Completed at $(date)" >> /var/log/openvpn-setup.log
echo "Public IP: $PUBLIC_IP" >> /var/log/openvpn-setup.log
echo "VPN User: ${vpn_user}" >> /var/log/openvpn-setup.log
echo "Config File: /root/${vpn_user}.ovpn" >> /var/log/openvpn-setup.log
echo "==================================" >> /var/log/openvpn-setup.log

# Signal completion
touch /root/openvpn-setup-complete

echo "OpenVPN installation complete!"
