#!/usr/bin/env bash
set -euo pipefail

# Integration test setup — deploys Azure infrastructure
# Requires: az cli logged in, TEST_SUBSCRIPTION_ID set

if [[ -z "${TEST_SUBSCRIPTION_ID:-}" ]]; then
  echo "ERROR: TEST_SUBSCRIPTION_ID is required" >&2
  exit 1
fi

RESOURCE_GROUP="rg-c7n-aca-test-$(date +%Y%m%d%H%M%S)"
STORAGE_ACCOUNT="c7ntest$(openssl rand -hex 4)"
LOCATION="${TEST_LOCATION:-japaneast}"

echo "Creating test infrastructure..."
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Storage Account: $STORAGE_ACCOUNT"
echo "  Location: $LOCATION"

az deployment sub create \
  --location "$LOCATION" \
  --template-file infra/main.bicep \
  --parameters \
    resourceGroupName="$RESOURCE_GROUP" \
    storageAccountName="$STORAGE_ACCOUNT" \
    location="$LOCATION" \
    targetSubscriptionIds="[\"$TEST_SUBSCRIPTION_ID\"]" \
    containerImage="ghcr.io/fukasawah/c7n-azure-aca:latest"

# Save state for run-tests.sh and teardown.sh
cat > tests/integration/.test-env <<EOF
RESOURCE_GROUP=$RESOURCE_GROUP
STORAGE_ACCOUNT=$STORAGE_ACCOUNT
TEST_SUBSCRIPTION_ID=$TEST_SUBSCRIPTION_ID
EOF

echo "Setup complete. State saved to tests/integration/.test-env"
