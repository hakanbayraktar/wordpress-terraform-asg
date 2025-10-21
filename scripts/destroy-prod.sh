#!/bin/bash
# Destroy Production Environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "===================================="
echo "Destroy Production Environment"
echo "===================================="
echo ""
echo "⚠️⚠️⚠️  DANGER  ⚠️⚠️⚠️"
echo ""
echo "This will PERMANENTLY DESTROY all production resources!"
echo "  - All WordPress data will be LOST"
echo "  - Database will be DELETED"
echo "  - Backups will be DELETED (after retention period)"
echo ""
echo "Environment: PRODUCTION"
echo "Config File: terraform.prod.tfvars"
echo ""

read -p "Type 'destroy-production' to confirm: " -r
echo

if [[ $REPLY != "destroy-production" ]]; then
    echo "Destruction cancelled."
    exit 0
fi

echo ""
read -p "Are you ABSOLUTELY sure? This cannot be undone! (type 'yes'): " -r
echo

if [[ $REPLY != "yes" ]]; then
    echo "Destruction cancelled."
    exit 0
fi

echo ""
echo "Destroying production environment..."
echo ""

terraform destroy -var-file="terraform.prod.tfvars" -auto-approve

echo ""
echo "===================================="
echo "✓ Production Environment Destroyed"
echo "===================================="
