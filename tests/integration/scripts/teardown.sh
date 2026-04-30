#!/usr/bin/env bash
set -euo pipefail

# Tear down integration test infrastructure
# All test VMs are inside the resource group and will be deleted with it.

if [[ ! -f tests/integration/.test-env ]]; then
  echo "ERROR: No test environment to tear down" >&2
  exit 1
fi

source tests/integration/.test-env

# Clean up Event Grid subscription on target subscription (cross-subscription resource)
echo "Deleting Event Grid subscription on $TEST_SUBSCRIPTION_ID..."
az eventgrid event-subscription delete \
  --name "custodian-custodian-events" \
  --source-resource-id "/subscriptions/$TEST_SUBSCRIPTION_ID" \
  2>/dev/null || true

# Delete the entire resource group (includes VMs, storage, jobs, env, identity)
echo "Deleting resource group: $RESOURCE_GROUP (async)..."
az group delete --name "$RESOURCE_GROUP" --yes --no-wait

rm -f tests/integration/.test-env
echo "Teardown complete"
