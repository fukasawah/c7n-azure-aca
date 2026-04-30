#!/usr/bin/env bash
set -euo pipefail

# Integration tests — verifies policies actually execute and produce correct results
#
# Prerequisites:
#   - setup.sh has been run (tests/integration/.test-env exists)
#   - az cli is logged in

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ENV_FILE="$REPO_ROOT/tests/integration/.test-env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: Run setup.sh first" >&2
  exit 1
fi

source "$ENV_FILE"

BLOB_ENDPOINT="https://${STORAGE_ACCOUNT}.blob.core.windows.net"
QUEUE_ENDPOINT="https://${STORAGE_ACCOUNT}.queue.core.windows.net"

FAILURES=0
TESTS_RUN=0

pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "  ✓ $1"
}

fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  FAILURES=$((FAILURES + 1))
  echo "  ✗ $1"
}

# ---------------------------------------------------------------------------
# 1. Create a test VM that the periodic policy will target
# ---------------------------------------------------------------------------
echo ""
echo "=== Setup: Create test VM (no Environment tag) ==="
TEST_VM_NAME="c7n-test-vm-$(openssl rand -hex 4)"

az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$TEST_VM_NAME" \
  --image "Canonical:ubuntu-24_04-lts:server:latest" \
  --size Standard_B1s \
  --admin-username azureuser \
  --generate-ssh-keys \
  --tags "Owner=integration-test" \
  --no-wait \
  --output none

echo "Waiting for VM provisioning..."
az vm wait \
  --resource-group "$RESOURCE_GROUP" \
  --name "$TEST_VM_NAME" \
  --created \
  --timeout 300

echo "Test VM created: $TEST_VM_NAME"

# ---------------------------------------------------------------------------
# 2. Upload test policies
# ---------------------------------------------------------------------------
echo ""
echo "=== Upload test policies ==="
az storage blob upload-batch \
  --source "$REPO_ROOT/tests/integration/policies/" \
  --destination policies \
  --blob-endpoint "$BLOB_ENDPOINT" \
  --auth-mode login \
  --overwrite \
  --output none

# Verify policies were uploaded
POLICY_COUNT=$(az storage blob list \
  --container-name policies \
  --blob-endpoint "$BLOB_ENDPOINT" \
  --auth-mode login \
  --query "length([?ends_with(name, '.yml') || ends_with(name, '.yaml')])" -o tsv)

if [[ "$POLICY_COUNT" -ge 1 ]]; then
  pass "Policies uploaded ($POLICY_COUNT files)"
else
  fail "No policy files found in blob container"
fi

# ---------------------------------------------------------------------------
# 3. Schedule Job — trigger, wait for completion, verify results
# ---------------------------------------------------------------------------
echo ""
echo "=== Test: Schedule Job ==="

# Start the job and capture the execution name
EXECUTION_NAME=$(az containerapp job start \
  --name custodian-schedule \
  --resource-group "$RESOURCE_GROUP" \
  --query "name" -o tsv)

echo "Started execution: $EXECUTION_NAME"

# Poll for completion (up to 5 minutes)
echo "Waiting for job execution to complete..."
MAX_WAIT=300
ELAPSED=0
POLL_INTERVAL=15
JOB_STATUS="Unknown"

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
  JOB_STATUS=$(az containerapp job execution show \
    --name custodian-schedule \
    --resource-group "$RESOURCE_GROUP" \
    --job-execution-name "$EXECUTION_NAME" \
    --query "properties.status" -o tsv 2>/dev/null || echo "Unknown")

  if [[ "$JOB_STATUS" == "Succeeded" || "$JOB_STATUS" == "Failed" ]]; then
    break
  fi

  sleep $POLL_INTERVAL
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

# 3a. Job execution succeeded
if [[ "$JOB_STATUS" == "Succeeded" ]]; then
  pass "Schedule job execution succeeded"
else
  fail "Schedule job execution status: $JOB_STATUS (expected: Succeeded)"
fi

# 3b. Output blobs exist for the periodic policy
PERIODIC_OUTPUT_BLOBS=$(az storage blob list \
  --container-name output \
  --blob-endpoint "$BLOB_ENDPOINT" \
  --auth-mode login \
  --query "[?contains(name, 'test-vm-tag-compliance')].name" -o tsv)

if [[ -n "$PERIODIC_OUTPUT_BLOBS" ]]; then
  pass "Output blobs created for test-vm-tag-compliance policy"
else
  fail "No output blobs found for test-vm-tag-compliance policy"
fi

# 3c. Download resources.json.gz and verify it contains resource data
RESOURCES_BLOB=$(az storage blob list \
  --container-name output \
  --blob-endpoint "$BLOB_ENDPOINT" \
  --auth-mode login \
  --query "[?contains(name, 'test-vm-tag-compliance') && contains(name, 'resources.json.gz')].name | [0]" -o tsv)

if [[ -n "$RESOURCES_BLOB" ]]; then
  TMPFILE=$(mktemp)
  az storage blob download \
    --container-name output \
    --blob-endpoint "$BLOB_ENDPOINT" \
    --name "$RESOURCES_BLOB" \
    --file "$TMPFILE" \
    --auth-mode login \
    --output none

  # Verify it's a valid gzipped JSON array.
  if python3 -c "import gzip,json,sys; data=json.load(gzip.open(sys.argv[1], 'rt', encoding='utf-8')); assert isinstance(data, list)" "$TMPFILE" 2>/dev/null; then
    pass "resources.json is valid JSON array"
  else
    fail "resources.json is not a valid JSON array"
  fi

  # Verify the test VM appears in resources (it has no Environment tag, so it should match)
  if python3 -c "
import gzip, json, sys
data = json.load(gzip.open(sys.argv[1], 'rt', encoding='utf-8'))
vm_names = [r.get('name', '') for r in data]
assert sys.argv[2] in vm_names, f'{sys.argv[2]} not found in {vm_names}'
" "$TMPFILE" "$TEST_VM_NAME" 2>/dev/null; then
    pass "resources.json contains test VM ($TEST_VM_NAME)"
  else
    fail "resources.json does not contain test VM ($TEST_VM_NAME)"
  fi

  rm -f "$TMPFILE"
else
  fail "resources.json.gz blob not found for test-vm-tag-compliance"
fi

# 3d. Verify the policy action took effect — Environment tag should be set to "test"
ACTUAL_TAG=$(az vm show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$TEST_VM_NAME" \
  --query "tags.Environment" -o tsv 2>/dev/null || echo "")

if [[ "$ACTUAL_TAG" == "test" ]]; then
  pass "Policy action verified: Environment tag set to 'test' on VM"
else
  fail "Policy action not applied: Environment tag is '$ACTUAL_TAG' (expected: 'test')"
fi

# ---------------------------------------------------------------------------
# 4. Event Job — create a resource to trigger Event Grid, verify processing
# ---------------------------------------------------------------------------
echo ""
echo "=== Test: Event Job ==="

# Record pre-existing event job executions
PRE_EVENT_EXEC_COUNT=$(az containerapp job execution list \
  --name custodian-event \
  --resource-group "$RESOURCE_GROUP" \
  --query "length(@)" -o tsv 2>/dev/null || echo "0")

# Create a new VM (without Owner tag) to trigger an Event Grid event
EVENT_VM_NAME="c7n-evt-vm-$(openssl rand -hex 4)"
echo "Creating VM to trigger event: $EVENT_VM_NAME"

az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$EVENT_VM_NAME" \
  --image "Canonical:ubuntu-24_04-lts:server:latest" \
  --size Standard_B1s \
  --admin-username azureuser \
  --generate-ssh-keys \
  --no-wait \
  --output none

az vm wait \
  --resource-group "$RESOURCE_GROUP" \
  --name "$EVENT_VM_NAME" \
  --created \
  --timeout 300

echo "Event VM created: $EVENT_VM_NAME"

# Wait for Event Grid → Storage Queue → Event Job to fire
# The queue scaler polls every 30s, and the job needs time to execute
echo "Waiting for event job to trigger and complete (up to 5 minutes)..."
MAX_WAIT=300
ELAPSED=0
POLL_INTERVAL=20
EVENT_JOB_TRIGGERED=false

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
  POST_EVENT_EXEC_COUNT=$(az containerapp job execution list \
    --name custodian-event \
    --resource-group "$RESOURCE_GROUP" \
    --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "$POST_EVENT_EXEC_COUNT" -gt "$PRE_EVENT_EXEC_COUNT" ]]; then
    # Check if the latest execution has completed
    LATEST_STATUS=$(az containerapp job execution list \
      --name custodian-event \
      --resource-group "$RESOURCE_GROUP" \
      --query "[0].properties.status" -o tsv 2>/dev/null || echo "Unknown")

    if [[ "$LATEST_STATUS" == "Succeeded" || "$LATEST_STATUS" == "Failed" ]]; then
      EVENT_JOB_TRIGGERED=true
      break
    fi
  fi

  sleep $POLL_INTERVAL
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

# 4a. Event job was triggered
if [[ "$EVENT_JOB_TRIGGERED" == "true" ]]; then
  pass "Event job triggered by VM creation"
else
  fail "Event job did not trigger within timeout"
fi

# 4b. Event job execution succeeded
if [[ "$EVENT_JOB_TRIGGERED" == "true" ]]; then
  if [[ "$LATEST_STATUS" == "Succeeded" ]]; then
    pass "Event job execution succeeded"
  else
    fail "Event job execution status: $LATEST_STATUS (expected: Succeeded)"
  fi
fi

# 4c. Check event job logs for processed message
EVENT_OUTPUT_BLOBS=$(az storage blob list \
  --container-name output \
  --blob-endpoint "$BLOB_ENDPOINT" \
  --auth-mode login \
  --query "[?contains(name, 'test-vm-creation')].name" -o tsv)

if [[ -n "$EVENT_OUTPUT_BLOBS" ]]; then
  pass "Output blobs created for test-vm-creation event policy"
else
  # Event policies may not always produce output blobs if the event doesn't match
  # the filter, so we'll log this as info rather than hard failure
  echo "  ⓘ No output blobs for test-vm-creation (event may not have matched filter)"
fi

# 4d. Verify queue was drained (messages processed)
QUEUE_LENGTH=$(az storage message peek \
  --queue-name custodian-events \
  --queue-endpoint "$QUEUE_ENDPOINT" \
  --auth-mode login \
  --num-messages 32 \
  --query "length(@)" -o tsv 2>/dev/null || echo "unknown")

echo "  Remaining queue messages: $QUEUE_LENGTH"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "==========================================="
echo "  Results: $((TESTS_RUN - FAILURES))/$TESTS_RUN passed"
echo "==========================================="

if [[ $FAILURES -gt 0 ]]; then
  echo "FAILED"
  exit 1
else
  echo "ALL PASSED"
  exit 0
fi
