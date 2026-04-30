"""Main handler for Azure Container Apps Job execution.

Entry point that dispatches to schedule or event mode based on C7N_ACA_MODE env var.
"""

import logging
import os
import sys

from azure.identity import DefaultAzureCredential
from azure.storage.queue import QueueClient

from c7n.utils import reset_session_cache

from c7n_azure_container_apps.event_matcher import decode_queue_message, matches_policy
from c7n_azure_container_apps.policy_loader import load_policies_from_blob

log = logging.getLogger("c7n_aca.handler")


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
    )

    # Validate required environment variables
    required_vars = ["C7N_ACA_STORAGE_ACCOUNT", "C7N_ACA_SUBSCRIPTION_IDS"]
    missing = [v for v in required_vars if not os.environ.get(v)]
    if missing:
        log.error("Missing required environment variables: %s", ", ".join(missing))
        sys.exit(1)

    mode = os.environ.get("C7N_ACA_MODE", "schedule")
    if mode == "schedule":
        run_schedule()
    elif mode == "event":
        run_event()
    else:
        log.error("Unknown C7N_ACA_MODE: %s", mode)
        sys.exit(1)


def _parse_subscription_ids() -> list[str]:
    """Parse and filter C7N_ACA_SUBSCRIPTION_IDS into a clean list."""
    raw = os.environ["C7N_ACA_SUBSCRIPTION_IDS"].split(",")
    return [s.strip() for s in raw if s.strip()]


def run_schedule():
    """Execute all container-periodic policies across all target subscriptions."""
    storage_account = os.environ["C7N_ACA_STORAGE_ACCOUNT"]
    output_dir = os.environ.get(
        "C7N_ACA_OUTPUT_DIR",
        f"azure://{storage_account}/output",
    )
    subscription_ids = _parse_subscription_ids()

    for sub_id in subscription_ids:
        log.info("Running periodic policies for subscription %s", sub_id)
        policies = load_policies_from_blob(
            storage_account_name=storage_account,
            container_name="policies",
            mode_type="container-periodic",
            subscription_id=sub_id,
            output_dir=output_dir,
        )
        if not policies:
            log.info("No periodic policies found for %s", sub_id)
            continue

        for policy in policies:
            try:
                policy.run()
            except Exception:
                log.exception("Policy failed: %s", policy.name)

        reset_session_cache()

    log.info("Schedule run complete")


def run_event():
    """Process queue messages and run matching container-event policies."""
    storage_account = os.environ["C7N_ACA_STORAGE_ACCOUNT"]
    queue_name = os.environ.get("C7N_ACA_QUEUE_NAME", "custodian-events")
    output_dir = os.environ.get(
        "C7N_ACA_OUTPUT_DIR",
        f"azure://{storage_account}/output",
    )
    subscription_ids = _parse_subscription_ids()

    credential = DefaultAzureCredential()
    queue_client = QueueClient(
        account_url=f"https://{storage_account}.queue.core.windows.net",
        queue_name=queue_name,
        credential=credential,
    )

    # Load event policies per subscription
    policies_by_sub: dict = {}
    for sub_id in subscription_ids:
        policies_by_sub[sub_id] = load_policies_from_blob(
            storage_account_name=storage_account,
            container_name="policies",
            mode_type="container-event",
            subscription_id=sub_id,
            output_dir=output_dir,
        )

    # Process queue messages
    messages = queue_client.receive_messages(
        max_messages=32,
        visibility_timeout=300,
    )
    for message in messages:
        try:
            event = decode_queue_message(message.content)
            subject = event.get("subject", "")
            event_sub_id = extract_subscription_id(subject)

            if event_sub_id not in policies_by_sub:
                log.warning(
                    "Event from unmonitored subscription %s, skipping", event_sub_id or "(empty)"
                )
            else:
                policies = policies_by_sub[event_sub_id]
                for policy in policies:
                    if matches_policy(event, policy):
                        log.info(
                            "Running policy %s for event %s",
                            policy.name,
                            event.get("data", {}).get("operationName"),
                        )
                        try:
                            policy.push(event, None)
                        except Exception:
                            log.exception("Policy failed: %s", policy.name)
        except Exception:
            log.exception("Failed to process queue message")
        finally:
            # Always delete the message to prevent poison-pill loops
            try:
                queue_client.delete_message(message)
            except Exception:
                log.exception("Failed to delete queue message")

        reset_session_cache()

    log.info("Event run complete")


def extract_subscription_id(subject: str) -> str:
    """Extract subscription ID from an Event Grid event subject (resource ID).

    Example subject:
        /subscriptions/xxxx/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm1
    Returns: xxxx
    """
    parts = subject.split("/")
    try:
        idx = parts.index("subscriptions")
        return parts[idx + 1]
    except (ValueError, IndexError):
        return ""
