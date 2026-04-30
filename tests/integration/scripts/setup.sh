#!/usr/bin/env bash
set -euo pipefail

# Integration test setup — deploys Azure infrastructure
# Requires: az cli logged in

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ENV_FILE="$REPO_ROOT/tests/integration/.test-env"

if [[ -z "${TEST_SUBSCRIPTION_ID:-}" ]]; then
  TEST_SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null || true)
fi

if [[ -z "${TEST_SUBSCRIPTION_ID:-}" ]]; then
  echo "ERROR: Could not resolve TEST_SUBSCRIPTION_ID from az account show" >&2
  exit 1
fi

RESOURCE_GROUP="rg-c7n-aca-test-$(date +%Y%m%d%H%M%S)"
STORAGE_ACCOUNT="c7ntest$(openssl rand -hex 4)"
LOCATION="${TEST_LOCATION:-japaneast}"
TEST_EXECUTOR_PRINCIPAL_ID="${TEST_EXECUTOR_PRINCIPAL_ID:-}"
CONTAINER_IMAGE="${CONTAINER_IMAGE:-ghcr.io/fukasawah/c7n-azure-aca:latest}"
DEPLOYMENT_NAME="c7n-aca-setup-$(date +%Y%m%d%H%M%S)"
COMPILED_TEMPLATE="$REPO_ROOT/infra/main.json"
BLOB_ENDPOINT="https://${STORAGE_ACCOUNT}.blob.core.windows.net"
QUEUE_ENDPOINT="https://${STORAGE_ACCOUNT}.queue.core.windows.net"

write_env_file() {
  cat > "$ENV_FILE" <<EOF
RESOURCE_GROUP=$RESOURCE_GROUP
STORAGE_ACCOUNT=$STORAGE_ACCOUNT
TEST_SUBSCRIPTION_ID=$TEST_SUBSCRIPTION_ID
EOF
}

resolve_test_executor_principal_id() {
  if [[ -n "$TEST_EXECUTOR_PRINCIPAL_ID" ]]; then
    return
  fi

  local account_type
  local account_name
  account_type=$(az account show --query user.type -o tsv 2>/dev/null || true)
  account_name=$(az account show --query user.name -o tsv 2>/dev/null || true)

  case "$account_type" in
    user)
      TEST_EXECUTOR_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)
      ;;
    servicePrincipal)
      TEST_EXECUTOR_PRINCIPAL_ID=$(az ad sp show --id "$account_name" --query id -o tsv 2>/dev/null || true)
      ;;
  esac

  if [[ -z "$TEST_EXECUTOR_PRINCIPAL_ID" ]]; then
    echo "ERROR: Could not resolve the test executor principal ID automatically." >&2
    echo "Set TEST_EXECUTOR_PRINCIPAL_ID and rerun setup.sh." >&2
    exit 1
  fi
}

grant_storage_data_access() {
  local storage_account_id
  local role

  storage_account_id=$(az storage account show \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query id -o tsv)

  echo "Granting storage data access to test executor principal $TEST_EXECUTOR_PRINCIPAL_ID..."
  for role in "Storage Blob Data Contributor" "Storage Queue Data Contributor"; do
    az role assignment create \
      --assignee-object-id "$TEST_EXECUTOR_PRINCIPAL_ID" \
      --assignee-principal-type User \
      --role "$role" \
      --scope "$storage_account_id" \
      --output none
  done

  echo "Waiting for storage RBAC propagation..."
  for ((attempt = 1; attempt <= 18; attempt++)); do
    if az storage container list \
      --blob-endpoint "$BLOB_ENDPOINT" \
      --auth-mode login \
      --query "length(@)" -o tsv >/dev/null 2>&1 \
      && az storage queue list \
        --queue-endpoint "$QUEUE_ENDPOINT" \
        --auth-mode login \
        --query "length(@)" -o tsv >/dev/null 2>&1; then
      echo "Storage data access confirmed."
      return
    fi

    sleep 10
  done

  echo "WARNING: Storage RBAC propagation could not be confirmed yet." >&2
  echo "run-tests.sh may need to be retried once the role assignments finish propagating." >&2
}

cleanup_on_exit() {
  local exit_code="$1"

  if [[ "$exit_code" -eq 0 ]]; then
    return
  fi

  echo "Setup failed (exit code: $exit_code). Cleaning up..." >&2

  local group_exists="false"
  if group_exists=$(az group exists --name "$RESOURCE_GROUP" -o tsv 2>/dev/null); then
    if [[ "$group_exists" == "true" ]]; then
      az group delete --name "$RESOURCE_GROUP" --yes --no-wait >/dev/null 2>&1 || true
      az group wait --deleted --name "$RESOURCE_GROUP" --interval 10 --timeout 600 >/dev/null 2>&1 || true
    fi
  fi

  if group_exists=$(az group exists --name "$RESOURCE_GROUP" -o tsv 2>/dev/null); then
    if [[ "$group_exists" == "true" ]]; then
      echo "Automatic cleanup could not confirm deletion of $RESOURCE_GROUP. State kept in $ENV_FILE for manual teardown." >&2
      return
    fi
  fi

  rm -f "$ENV_FILE"
}

write_env_file
trap 'cleanup_on_exit "$?"' EXIT
resolve_test_executor_principal_id

echo "Creating test infrastructure..."
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Storage Account: $STORAGE_ACCOUNT"
echo "  Location: $LOCATION"
echo "  Subscription: $TEST_SUBSCRIPTION_ID"
echo "  Container Image: $CONTAINER_IMAGE"
echo "  Deployment Name: $DEPLOYMENT_NAME"
echo "  Test Executor Principal: $TEST_EXECUTOR_PRINCIPAL_ID"

az bicep build \
  --file "$REPO_ROOT/infra/main.bicep" \
  --outfile "$COMPILED_TEMPLATE"

az deployment sub create \
  --name "$DEPLOYMENT_NAME" \
  --location "$LOCATION" \
  --template-file "$COMPILED_TEMPLATE" \
  --parameters \
    resourceGroupName="$RESOURCE_GROUP" \
    storageAccountName="$STORAGE_ACCOUNT" \
    location="$LOCATION" \
    targetSubscriptionIds="[\"$TEST_SUBSCRIPTION_ID\"]" \
    assignContributorRole=true \
    targetRoleAssignmentScope="resource-group" \
    targetResourceGroupName="$RESOURCE_GROUP" \
    containerImage="$CONTAINER_IMAGE"

grant_storage_data_access

echo "Setup complete. State saved to $ENV_FILE"
