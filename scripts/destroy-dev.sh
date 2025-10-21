#!/bin/bash
# Destroy Development Environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "===================================="
echo "Destroy Dev Environment"
echo "===================================="
echo ""
echo "⚠️  WARNING: This will destroy all dev resources!"
echo ""
echo "Environment: DEV"
echo "Config File: terraform.dev.tfvars"
echo ""

read -p "Are you sure you want to destroy dev environment? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy](es)?$ ]]; then
    echo "Destruction cancelled."
    exit 0
fi

echo ""
echo "Destroying dev environment..."
echo ""

terraform destroy -var-file="terraform.dev.tfvars" -auto-approve

echo ""
echo "===================================="
echo "✓ Dev Environment Destroyed"
echo "===================================="
