"""Tests for event_matcher module."""

import base64
import json

import pytest

from c7n_azure_container_apps.event_matcher import (
    decode_queue_message,
    get_operation_name,
    matches_policy,
)


def test_decode_queue_message():
    event = {"data": {"operationName": "Microsoft.Compute/virtualMachines/write"}}
    encoded = base64.b64encode(json.dumps(event).encode()).decode()
    result = decode_queue_message(encoded)
    assert result == event


def test_get_operation_name(sample_event):
    assert get_operation_name(sample_event) == "Microsoft.Compute/virtualMachines/write"


def test_get_operation_name_missing():
    assert get_operation_name({}) == ""
    assert get_operation_name({"data": {}}) == ""


def test_matches_policy_match(mocker, sample_event):
    policy = mocker.MagicMock()
    policy.data = {
        "mode": {
            "type": "container-event",
            "events": [
                {
                    "resourceProvider": "Microsoft.Compute/virtualMachines",
                    "event": "write",
                }
            ],
        }
    }
    assert matches_policy(sample_event, policy) is True


def test_matches_policy_no_match(mocker, sample_event):
    policy = mocker.MagicMock()
    policy.data = {
        "mode": {
            "type": "container-event",
            "events": [
                {
                    "resourceProvider": "Microsoft.Storage/storageAccounts",
                    "event": "write",
                }
            ],
        }
    }
    assert matches_policy(sample_event, policy) is False


def test_matches_policy_case_insensitive(mocker):
    event = {
        "data": {"operationName": "MICROSOFT.COMPUTE/VIRTUALMACHINES/WRITE"},
    }
    policy = mocker.MagicMock()
    policy.data = {
        "mode": {
            "type": "container-event",
            "events": [
                {
                    "resourceProvider": "Microsoft.Compute/virtualMachines",
                    "event": "write",
                }
            ],
        }
    }
    assert matches_policy(event, policy) is True


def test_matches_policy_empty_operation_name(mocker):
    event = {"data": {}}
    policy = mocker.MagicMock()
    policy.data = {
        "mode": {
            "type": "container-event",
            "events": [
                {
                    "resourceProvider": "Microsoft.Compute/virtualMachines",
                    "event": "write",
                }
            ],
        }
    }
    assert matches_policy(event, policy) is False


def test_decode_queue_message_non_dict():
    """Non-dict JSON (e.g. list or string) should raise ValueError."""
    encoded = base64.b64encode(json.dumps([1, 2, 3]).encode()).decode()
    with pytest.raises(ValueError, match="Expected JSON object"):
        decode_queue_message(encoded)


def test_decode_queue_message_invalid_base64():
    """Invalid base64 should raise an error."""
    with pytest.raises(Exception):
        decode_queue_message("not-valid-base64!!!")


def test_matches_policy_string_shortcut(mocker):
    """String event shortcuts like 'VmWrite' should be resolved via AzureEvents registry."""
    event = {"data": {"operationName": "Microsoft.Compute/virtualMachines/write"}}
    policy = mocker.MagicMock()
    policy.data = {
        "mode": {
            "type": "container-event",
            "events": ["VmWrite"],
        }
    }
    assert matches_policy(event, policy) is True


def test_matches_policy_no_events_field(mocker):
    """Policy with no 'events' in mode should never match."""
    event = {"data": {"operationName": "Microsoft.Compute/virtualMachines/write"}}
    policy = mocker.MagicMock()
    policy.data = {"mode": {"type": "container-event"}}
    assert matches_policy(event, policy) is False
