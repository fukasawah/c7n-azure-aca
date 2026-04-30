"""Match Event Grid events to c7n policy event definitions."""

import base64
import json

from c7n_azure.azure_events import AzureEvents


def decode_queue_message(message_content: str) -> dict:
    """Decode a Storage Queue message containing a base64-encoded Event Grid event.

    Raises:
        ValueError: If the decoded content is not a JSON object (dict).
    """
    decoded = base64.b64decode(message_content).decode("utf-8")
    result = json.loads(decoded)
    if not isinstance(result, dict):
        raise ValueError(f"Expected JSON object, got {type(result).__name__}")
    return result


def get_operation_name(event: dict) -> str:
    """Extract operationName from an Event Grid event."""
    return event.get("data", {}).get("operationName", "")


def matches_policy(event: dict, policy) -> bool:
    """Check if an event's operationName matches a policy's event definitions.

    Uses AzureEvents.get_event_operations() to normalize the policy's event
    definitions into operation name strings, then compares case-insensitively.
    """
    operation_name = get_operation_name(event)
    if not operation_name:
        return False
    policy_events = policy.data.get("mode", {}).get("events", [])
    expected_operations = AzureEvents.get_event_operations(policy_events)
    return operation_name.upper() in (op.upper() for op in expected_operations)
