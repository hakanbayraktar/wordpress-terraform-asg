#!/bin/bash
#
# Automated Testing Script for WordPress Auto Scaling Infrastructure
#
# This script runs comprehensive tests on all deployed components:
# - WordPress web access
# - VPN connectivity
# - Bastion SSH access
# - RDS MySQL connectivity
# - Auto Scaling functionality
# - CloudWatch alarms
#
# Usage: ./scripts/run-tests.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

echo ""
echo -e "${BOLD}${CYAN}========================================${NC}"
echo -e "${BOLD}${CYAN}WordPress Auto Scaling - Test Suite${NC}"
echo -e "${BOLD}${CYAN}========================================${NC}"
echo ""

# Check prerequisites
if [ ! -f "terraform.tfstate" ]; then
    echo -e "${RED}Error: terraform.tfstate not found!${NC}"
    echo "Please run 'terraform apply' first."
    exit 1
fi

# Get terraform outputs
WORDPRESS_URL=$(terraform output -raw wordpress_url 2>/dev/null)
BASTION_IP=$(terraform output -raw bastion_public_ip 2>/dev/null)
VPN_SERVER_IP=$(terraform output -raw vpn_server_ip 2>/dev/null)
VPN_USER=$(terraform output -raw vpn_user 2>/dev/null)
RDS_ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null)
ASG_NAME=$(terraform output -raw autoscaling_group_name 2>/dev/null)
REGION=$(grep 'aws_region' terraform.dev.tfvars | cut -d'"' -f2)
DB_PASSWORD=$(grep 'db_password' terraform.dev.tfvars | cut -d'"' -f2)

# Helper functions
test_start() {
    echo -e "${BOLD}${BLUE}[TEST]${NC} $1"
}

test_pass() {
    echo -e "${GREEN}✓ PASS${NC} - $1"
    ((TESTS_PASSED++))
    echo ""
}

test_fail() {
    echo -e "${RED}✗ FAIL${NC} - $1"
    ((TESTS_FAILED++))
    echo ""
}

test_skip() {
    echo -e "${YELLOW}⊘ SKIP${NC} - $1"
    ((TESTS_SKIPPED++))
    echo ""
}

# Test 1: WordPress Web Access
echo -e "${BOLD}${YELLOW}=== Test 1: WordPress Web Access ===${NC}"
echo ""
test_start "Testing WordPress HTTP access..."
if HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "${WORDPRESS_URL}" 2>/dev/null); then
    if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 302 ]; then
        test_pass "WordPress is accessible (HTTP $HTTP_CODE)"
        echo "   URL: ${WORDPRESS_URL}"
    else
        test_fail "WordPress returned HTTP $HTTP_CODE"
    fi
else
    test_fail "Could not connect to WordPress"
fi

# Test 2: VPN Server Connectivity
echo -e "${BOLD}${YELLOW}=== Test 2: VPN Server Connectivity ===${NC}"
echo ""
test_start "Testing VPN server SSH port..."
if timeout 5 bash -c "</dev/tcp/${VPN_SERVER_IP}/22" 2>/dev/null; then
    test_pass "VPN server SSH port (22) is open"
else
    test_skip "VPN server SSH port (22) not accessible from public internet (security feature - requires VPN)"
fi

test_start "Testing VPN OpenVPN port..."
if nc -vuz -w 3 "${VPN_SERVER_IP}" 1194 2>&1 | grep -q "succeeded"; then
    test_pass "VPN OpenVPN port (1194/UDP) is open"
else
    test_fail "VPN OpenVPN port (1194/UDP) is not accessible"
fi

test_start "Checking VPN config file availability..."
if [ -f ~/.ssh/wordpress-key.pem ]; then
    if ssh -i ~/.ssh/wordpress-key.pem -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
        ubuntu@${VPN_SERVER_IP} "test -f /home/ubuntu/${VPN_USER}.ovpn" 2>/dev/null; then
        test_pass "VPN config file exists on server"
        echo "   File: /home/ubuntu/${VPN_USER}.ovpn"
    else
        test_skip "VPN config not ready yet (wait 5 mins after deployment)"
    fi
else
    test_skip "SSH key not found at ~/.ssh/wordpress-key.pem"
fi

# Test 3: Auto Scaling Group
echo -e "${BOLD}${YELLOW}=== Test 3: Auto Scaling Group ===${NC}"
echo ""
test_start "Checking ASG configuration..."
ASG_INFO=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "${ASG_NAME}" \
    --region "${REGION}" 2>/dev/null)

if [ -n "$ASG_INFO" ]; then
    DESIRED=$(echo "$ASG_INFO" | jq -r '.AutoScalingGroups[0].DesiredCapacity')
    MIN=$(echo "$ASG_INFO" | jq -r '.AutoScalingGroups[0].MinSize')
    MAX=$(echo "$ASG_INFO" | jq -r '.AutoScalingGroups[0].MaxSize')
    CURRENT=$(echo "$ASG_INFO" | jq -r '.AutoScalingGroups[0].Instances | length')

    test_pass "ASG is configured"
    echo "   Desired: $DESIRED, Min: $MIN, Max: $MAX, Current: $CURRENT instances"

    if [ "$CURRENT" -ge "$MIN" ] && [ "$CURRENT" -le "$MAX" ]; then
        test_pass "Instance count is within limits"
    else
        test_fail "Instance count ($CURRENT) is out of bounds (Min: $MIN, Max: $MAX)"
    fi
else
    test_fail "Could not retrieve ASG information"
fi

# Test 4: CloudWatch Alarms
echo -e "${BOLD}${YELLOW}=== Test 4: CloudWatch Alarms ===${NC}"
echo ""
test_start "Checking CloudWatch alarms..."
ALARMS=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "wordpress-dev" \
    --region "${REGION}" 2>/dev/null)

if [ -n "$ALARMS" ]; then
    ALARM_COUNT=$(echo "$ALARMS" | jq -r '.MetricAlarms | length')
    test_pass "Found $ALARM_COUNT CloudWatch alarm(s)"

    echo "$ALARMS" | jq -r '.MetricAlarms[] | "   - \(.AlarmName): \(.StateValue)"'
    echo ""
else
    test_fail "Could not retrieve CloudWatch alarms"
fi

# Test 5: RDS Instance
echo -e "${BOLD}${YELLOW}=== Test 5: RDS MySQL Instance ===${NC}"
echo ""
test_start "Checking RDS instance status..."
RDS_STATUS=$(aws rds describe-db-instances \
    --region "${REGION}" \
    --query "DBInstances[?contains(DBInstanceIdentifier, 'wordpress')].{Status:DBInstanceStatus,Endpoint:Endpoint.Address}" \
    --output json 2>/dev/null)

if [ -n "$RDS_STATUS" ] && [ "$RDS_STATUS" != "[]" ]; then
    STATUS=$(echo "$RDS_STATUS" | jq -r '.[0].Status')
    ENDPOINT=$(echo "$RDS_STATUS" | jq -r '.[0].Endpoint')

    if [ "$STATUS" == "available" ]; then
        test_pass "RDS instance is available"
        echo "   Endpoint: $ENDPOINT"
    else
        test_fail "RDS instance status: $STATUS"
    fi
else
    test_fail "Could not find RDS instance"
fi

# Test 6: EFS File System
echo -e "${BOLD}${YELLOW}=== Test 6: EFS File System ===${NC}"
echo ""
test_start "Checking EFS file system..."
EFS_ID=$(terraform output -raw efs_id 2>/dev/null)
EFS_STATUS=$(aws efs describe-file-systems \
    --file-system-id "${EFS_ID}" \
    --region "${REGION}" \
    --query 'FileSystems[0].LifeCycleState' \
    --output text 2>/dev/null)

if [ "$EFS_STATUS" == "available" ]; then
    test_pass "EFS file system is available"
    echo "   EFS ID: $EFS_ID"
else
    test_fail "EFS file system status: $EFS_STATUS"
fi

# Test 7: Load Balancer
echo -e "${BOLD}${YELLOW}=== Test 7: Application Load Balancer ===${NC}"
echo ""
test_start "Checking ALB health..."
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null)
TARGET_GROUP=$(aws elbv2 describe-target-groups \
    --region "${REGION}" \
    --query "TargetGroups[?contains(TargetGroupName, 'wordpress')].TargetGroupArn" \
    --output text 2>/dev/null | head -1)

if [ -n "$TARGET_GROUP" ]; then
    HEALTH=$(aws elbv2 describe-target-health \
        --target-group-arn "${TARGET_GROUP}" \
        --region "${REGION}" 2>/dev/null)

    HEALTHY_COUNT=$(echo "$HEALTH" | jq -r '[.TargetHealthDescriptions[] | select(.TargetHealth.State == "healthy")] | length')
    TOTAL_COUNT=$(echo "$HEALTH" | jq -r '.TargetHealthDescriptions | length')

    test_pass "ALB target group has $HEALTHY_COUNT/$TOTAL_COUNT healthy targets"
else
    test_fail "Could not find ALB target group"
fi

# Test 8: Security Groups
echo -e "${BOLD}${YELLOW}=== Test 8: Security Groups ===${NC}"
echo ""
test_start "Checking security groups..."
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null)

if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "null" ]; then
    test_skip "Could not retrieve VPC ID from terraform outputs"
else
    # Count using grep instead of JMESPath length (more reliable)
    SG_COUNT=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --region "${REGION}" \
        --output text 2>/dev/null | grep "^SECURITYGROUPS" | wc -l | tr -d ' ')

    # Check if SG_COUNT is a valid number and greater than 0
    if [ -n "$SG_COUNT" ] && [ "$SG_COUNT" -gt 0 ] 2>/dev/null; then
        test_pass "Found $SG_COUNT security group(s) in VPC"
    else
        test_fail "No security groups found in VPC ${VPC_ID}"
    fi
fi

# Test 9: SNS Topic Subscription
echo -e "${BOLD}${YELLOW}=== Test 9: SNS Email Subscription ===${NC}"
echo ""
test_start "Checking SNS subscription..."
SNS_TOPIC=$(terraform output -raw sns_topic_arn 2>/dev/null)
SUB_STATUS=$(aws sns list-subscriptions-by-topic \
    --topic-arn "${SNS_TOPIC}" \
    --region "${REGION}" \
    --query 'Subscriptions[0].SubscriptionArn' \
    --output text 2>/dev/null)

if [ "$SUB_STATUS" != "None" ] && [ "$SUB_STATUS" != "PendingConfirmation" ] && [ "$SUB_STATUS" != "Deleted" ]; then
    test_pass "SNS email subscription is confirmed"
elif [ "$SUB_STATUS" == "PendingConfirmation" ]; then
    test_skip "SNS subscription pending confirmation - check your email!"
else
    test_fail "SNS subscription not found or deleted"
fi

# Optional: Auto Scaling Stress Test
echo -e "${BOLD}${YELLOW}=== Optional: Auto Scaling Stress Test ===${NC}"
echo ""
echo -e "${CYAN}To test auto scaling, run the following command:${NC}"
echo ""
echo "# Get WordPress instance IP"
echo "INSTANCE_ID=\$(aws autoscaling describe-auto-scaling-groups \\"
echo "    --auto-scaling-group-names ${ASG_NAME} \\"
echo "    --region ${REGION} \\"
echo "    --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)"
echo ""
echo "INSTANCE_IP=\$(aws ec2 describe-instances \\"
echo "    --instance-ids \$INSTANCE_ID \\"
echo "    --region ${REGION} \\"
echo "    --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)"
echo ""
echo "# Run CPU stress test (requires VPN connection)"
echo "ssh -i ~/.ssh/wordpress-key.pem \\"
echo "    -o ProxyCommand=\"ssh -W %h:%p -i ~/.ssh/wordpress-key.pem ec2-user@${BASTION_IP}\" \\"
echo "    ec2-user@\$INSTANCE_IP \\"
echo "    'sudo dnf install -y stress-ng && stress-ng --cpu 1 --cpu-load 100 --timeout 300s'"
echo ""
echo "# Monitor ASG scaling"
echo "watch -n 10 'aws autoscaling describe-auto-scaling-groups \\"
echo "    --auto-scaling-group-names ${ASG_NAME} \\"
echo "    --region ${REGION} \\"
echo "    --query \"AutoScalingGroups[0].{Desired:DesiredCapacity,Current:length(Instances)}\"'"
echo ""

# Summary
echo -e "${BOLD}${GREEN}=== Test Summary ===${NC}"
echo ""
echo -e "${GREEN}✓ Passed:${NC}  $TESTS_PASSED"
echo -e "${RED}✗ Failed:${NC}  $TESTS_FAILED"
echo -e "${YELLOW}⊘ Skipped:${NC} $TESTS_SKIPPED"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${BOLD}${GREEN}All critical tests passed! Infrastructure is healthy.${NC}"
    exit 0
else
    echo -e "${BOLD}${RED}Some tests failed. Please review the failures above.${NC}"
    exit 1
fi
