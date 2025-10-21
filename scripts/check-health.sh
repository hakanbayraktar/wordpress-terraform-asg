#!/bin/bash
# WordPress Infrastructure Health Check Script

set -e

echo "========================================="
echo "WordPress Infrastructure Health Check"
echo "========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_terraform() {
    echo -n "Checking Terraform state... "
    if terraform state list > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        echo "  Error: No Terraform state found"
        exit 1
    fi
}

check_vpc() {
    echo -n "Checking VPC... "
    VPC_ID=$(terraform output -raw vpc_id 2>/dev/null)
    if [ -n "$VPC_ID" ]; then
        echo -e "${GREEN}✓${NC} ($VPC_ID)"
    else
        echo -e "${RED}✗${NC}"
    fi
}

check_alb() {
    echo -n "Checking ALB... "
    ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null)
    if [ -n "$ALB_DNS" ]; then
        echo -e "${GREEN}✓${NC} ($ALB_DNS)"

        echo -n "  Checking ALB accessibility... "
        if curl -s -o /dev/null -w "%{http_code}" "http://${ALB_DNS}" | grep -q "200\|302"; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${YELLOW}⚠${NC} (ALB is up but WordPress may not be ready)"
        fi
    else
        echo -e "${RED}✗${NC}"
    fi
}

check_rds() {
    echo -n "Checking RDS... "
    RDS_ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null)
    if [ -n "$RDS_ENDPOINT" ]; then
        echo -e "${GREEN}✓${NC} ($RDS_ENDPOINT)"

        echo -n "  Checking RDS status... "
        DB_ID=$(aws rds describe-db-instances \
            --query 'DBInstances[?Endpoint.Address==`'$(echo $RDS_ENDPOINT | cut -d: -f1)'`].DBInstanceIdentifier' \
            --output text 2>/dev/null)

        if [ -n "$DB_ID" ]; then
            DB_STATUS=$(aws rds describe-db-instances \
                --db-instance-identifier "$DB_ID" \
                --query 'DBInstances[0].DBInstanceStatus' \
                --output text 2>/dev/null)

            if [ "$DB_STATUS" = "available" ]; then
                echo -e "${GREEN}✓${NC} (available)"
            else
                echo -e "${YELLOW}⚠${NC} ($DB_STATUS)"
            fi
        fi
    else
        echo -e "${RED}✗${NC}"
    fi
}

check_efs() {
    echo -n "Checking EFS... "
    EFS_ID=$(terraform output -raw efs_id 2>/dev/null)
    if [ -n "$EFS_ID" ]; then
        echo -e "${GREEN}✓${NC} ($EFS_ID)"

        echo -n "  Checking EFS lifecycle state... "
        EFS_STATE=$(aws efs describe-file-systems \
            --file-system-id "$EFS_ID" \
            --query 'FileSystems[0].LifeCycleState' \
            --output text 2>/dev/null)

        if [ "$EFS_STATE" = "available" ]; then
            echo -e "${GREEN}✓${NC} (available)"
        else
            echo -e "${YELLOW}⚠${NC} ($EFS_STATE)"
        fi
    else
        echo -e "${RED}✗${NC}"
    fi
}

check_asg() {
    echo -n "Checking Auto Scaling Group... "
    ASG_NAME=$(terraform output -raw autoscaling_group_name 2>/dev/null)
    if [ -n "$ASG_NAME" ]; then
        echo -e "${GREEN}✓${NC} ($ASG_NAME)"

        ASG_INFO=$(aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "$ASG_NAME" \
            --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize]' \
            --output text 2>/dev/null)

        if [ -n "$ASG_INFO" ]; then
            MIN=$(echo $ASG_INFO | awk '{print $1}')
            DESIRED=$(echo $ASG_INFO | awk '{print $2}')
            MAX=$(echo $ASG_INFO | awk '{print $3}')
            echo "  Capacity: Min=$MIN, Desired=$DESIRED, Max=$MAX"
        fi

        INSTANCE_COUNT=$(aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "$ASG_NAME" \
            --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`] | length(@)' \
            --output text 2>/dev/null)

        echo "  In-Service Instances: $INSTANCE_COUNT"
    else
        echo -e "${RED}✗${NC}"
    fi
}

check_target_health() {
    echo -n "Checking Target Group Health... "
    TG_ARN=$(aws elbv2 describe-target-groups \
        --names "wordpress-autoscaling-tg" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null)

    if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
        HEALTH=$(aws elbv2 describe-target-health \
            --target-group-arn "$TG_ARN" \
            --query 'TargetHealthDescriptions[*].TargetHealth.State' \
            --output text 2>/dev/null)

        HEALTHY_COUNT=$(echo "$HEALTH" | grep -o "healthy" | wc -l)
        TOTAL_COUNT=$(echo "$HEALTH" | wc -w)

        if [ "$TOTAL_COUNT" -gt 0 ]; then
            if [ "$HEALTHY_COUNT" -eq "$TOTAL_COUNT" ]; then
                echo -e "${GREEN}✓${NC} ($HEALTHY_COUNT/$TOTAL_COUNT healthy)"
            else
                echo -e "${YELLOW}⚠${NC} ($HEALTHY_COUNT/$TOTAL_COUNT healthy)"
            fi
        else
            echo -e "${YELLOW}⚠${NC} (No targets registered)"
        fi
    else
        echo -e "${YELLOW}⚠${NC} (Target group not found)"
    fi
}

check_bastion() {
    echo -n "Checking Bastion Host... "
    BASTION_IP=$(terraform output -raw bastion_public_ip 2>/dev/null)
    if [ -n "$BASTION_IP" ]; then
        echo -e "${GREEN}✓${NC} ($BASTION_IP)"
    else
        echo -e "${RED}✗${NC}"
    fi
}

check_cloudwatch() {
    echo -n "Checking CloudWatch Alarms... "
    ALARM_COUNT=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "wordpress-autoscaling" \
        --query 'length(MetricAlarms)' \
        --output text 2>/dev/null)

    if [ "$ALARM_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} ($ALARM_COUNT alarms configured)"

        OK_COUNT=$(aws cloudwatch describe-alarms \
            --alarm-name-prefix "wordpress-autoscaling" \
            --state-value OK \
            --query 'length(MetricAlarms)' \
            --output text 2>/dev/null)

        ALARM_STATE_COUNT=$(aws cloudwatch describe-alarms \
            --alarm-name-prefix "wordpress-autoscaling" \
            --state-value ALARM \
            --query 'length(MetricAlarms)' \
            --output text 2>/dev/null)

        echo "  States: OK=$OK_COUNT, ALARM=$ALARM_STATE_COUNT"
    else
        echo -e "${YELLOW}⚠${NC} (No alarms found)"
    fi
}

# Run all checks
echo "Running health checks..."
echo ""

check_terraform
check_vpc
check_alb
check_rds
check_efs
check_asg
check_target_health
check_bastion
check_cloudwatch

echo ""
echo "========================================="
echo "Health check completed!"
echo "========================================="
echo ""
echo "Quick Links:"
echo "  WordPress: http://$(terraform output -raw alb_dns_name 2>/dev/null)"
echo "  CloudWatch: https://console.aws.amazon.com/cloudwatch/home?region=$(terraform output -raw aws_region 2>/dev/null || echo 'us-east-1')"
echo "  EC2 Console: https://console.aws.amazon.com/ec2/home?region=$(terraform output -raw aws_region 2>/dev/null || echo 'us-east-1')"
echo ""