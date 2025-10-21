#!/bin/bash
# WordPress Auto Scaling Stress Test Script

set -e

echo "==================================="
echo "WordPress Auto Scaling Stress Test"
echo "==================================="
echo ""

# Get ALB DNS from Terraform output
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null)

if [ -z "$ALB_DNS" ]; then
    echo "Error: Could not get ALB DNS name from Terraform output"
    echo "Please run 'terraform apply' first"
    exit 1
fi

WORDPRESS_URL="http://${ALB_DNS}"

echo "Target URL: $WORDPRESS_URL"
echo ""

# Check if Apache Bench is installed
if ! command -v ab &> /dev/null; then
    echo "Apache Bench (ab) is not installed."
    echo ""
    echo "Install instructions:"
    echo "  - macOS: brew install httpd"
    echo "  - Ubuntu/Debian: sudo apt-get install apache2-utils"
    echo "  - CentOS/RHEL: sudo yum install httpd-tools"
    exit 1
fi

echo "Starting stress test..."
echo ""

# Test parameters
REQUESTS=10000
CONCURRENCY=50

echo "Test Parameters:"
echo "  - Total Requests: $REQUESTS"
echo "  - Concurrent Requests: $CONCURRENCY"
echo ""

# Run Apache Bench
echo "Running Apache Bench..."
ab -n $REQUESTS -c $CONCURRENCY "${WORDPRESS_URL}/"

echo ""
echo "==================================="
echo "Stress test completed!"
echo ""
echo "Monitor the following:"
echo "1. CloudWatch Dashboard: https://console.aws.amazon.com/cloudwatch/"
echo "2. Auto Scaling Group: https://console.aws.amazon.com/ec2/autoscaling/"
echo "3. Check your email for SNS notifications"
echo ""
echo "Expected behavior:"
echo "- CPU usage should increase on EC2 instances"
echo "- After ~5 minutes of high CPU (>50%), new instances should launch"
echo "- You should receive email notifications"
echo "==================================="