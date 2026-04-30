#!/usr/bin/env bash
set -euo pipefail

# Tear down integration test infrastructure
# All test VMs are inside the resource group and will be deleted with it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ENV_FILE="$REPO_ROOT/tests/integration/.test-env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: No test environment to tear down" >&2
  exit 1
fi

source "$ENV_FILE"

# Clean up Event Grid subscription on target subscription (cross-subscription resource)
echo "Deleting Event Grid subscription on $TEST_SUBSCRIPTION_ID..."
az eventgrid event-subscription delete \
  --name "custodian-custodian-events" \
  --source-resource-id "/subscriptions/$TEST_SUBSCRIPTION_ID" \
  2>/dev/null || true

# Delete the entire resource group (includes VMs, storage, jobs, env, identity)
echo "Deleting resource group: $RESOURCE_GROUP ..."
az group delete --name "$RESOURCE_GROUP" --yes --no-wait
az group wait --deleted --name "$RESOURCE_GROUP" --interval 10 --timeout 900

rm -f "$ENV_FILE"
echo "Teardown complete"
