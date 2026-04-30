"""Tests for handler module."""

import base64
import json
import os
from unittest.mock import MagicMock, patch

import pytest

from c7n_azure_aca.handler import extract_subscription_id, _parse_subscription_ids


def test_extract_subscription_id():
    subject = (
        "/subscriptions/sub-111/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm1"
    )
    assert extract_subscription_id(subject) == "sub-111"


def test_extract_subscription_id_empty():
    assert extract_subscription_id("") == ""
    assert extract_subscription_id("/invalid/path") == ""


@patch.dict(
    os.environ,
    {
        "C7N_ACA_MODE": "schedule",
        "C7N_ACA_STORAGE_ACCOUNT": "testaccount",
        "C7N_ACA_SUBSCRIPTION_IDS": "sub-aaa,sub-bbb",
    },
)
@patch("c7n_azure_aca.handler.load_policies_from_blob")
@patch("c7n_azure_aca.handler.reset_session_cache")
def test_run_schedule(mock_reset, mock_load):
    from c7n_azure_aca.handler import run_schedule

    policy1 = MagicMock()
    policy1.name = "p1"
    mock_load.return_value = [policy1]

    run_schedule()

    # Should load policies for both subscriptions
    assert mock_load.call_count == 2
    calls = mock_load.call_args_list
    assert calls[0].kwargs["subscription_id"] == "sub-aaa"
    assert calls[1].kwargs["subscription_id"] == "sub-bbb"
    assert calls[0].kwargs["mode_type"] == "container-periodic"

    # policy.run() should be called for each subscription
    assert policy1.run.call_count == 2


@patch.dict(
    os.environ,
    {
        "C7N_ACA_MODE": "event",
        "C7N_ACA_STORAGE_ACCOUNT": "testaccount",
        "C7N_ACA_SUBSCRIPTION_IDS": "sub-111",
        "C7N_ACA_QUEUE_NAME": "test-queue",
    },
)
@patch("c7n_azure_aca.handler.load_policies_from_blob")
@patch("c7n_azure_aca.handler.QueueClient")
@patch("c7n_azure_aca.handler.DefaultAzureCredential")
@patch("c7n_azure_aca.handler.reset_session_cache")
def test_run_event(mock_reset, mock_cred, mock_queue_cls, mock_load):
    from c7n_azure_aca.handler import run_event

    # Set up a matching policy
    policy = MagicMock()
    policy.name = "test-policy"
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
    mock_load.return_value = [policy]

    # Set up a queue message containing an Event Grid event
    event = {
        "id": "evt-1",
        "subject": "/subscriptions/sub-111/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm1",
        "data": {
            "operationName": "Microsoft.Compute/virtualMachines/write",
        },
    }
    msg = MagicMock()
    msg.content = base64.b64encode(json.dumps(event).encode()).decode()

    queue_client = MagicMock()
    queue_client.receive_messages.return_value = [msg]
    mock_queue_cls.return_value = queue_client

    run_event()

    # Policy should be executed with the event
    policy.push.assert_called_once()
    call_args = policy.push.call_args[0]
    assert call_args[0]["id"] == "evt-1"

    # Message should be deleted after processing
    queue_client.delete_message.assert_called_once_with(msg)


@patch.dict(
    os.environ,
    {
        "C7N_ACA_MODE": "schedule",
        "C7N_ACA_STORAGE_ACCOUNT": "testaccount",
        "C7N_ACA_SUBSCRIPTION_IDS": "sub-aaa",
    },
)
@patch("c7n_azure_aca.handler.load_policies_from_blob")
@patch("c7n_azure_aca.handler.reset_session_cache")
def test_run_schedule_policy_failure_continues(mock_reset, mock_load):
    """A failing policy should not stop other policies from running."""
    from c7n_azure_aca.handler import run_schedule

    p1 = MagicMock()
    p1.name = "fail-policy"
    p1.run.side_effect = RuntimeError("boom")
    p2 = MagicMock()
    p2.name = "ok-policy"
    mock_load.return_value = [p1, p2]

    # Should not raise
    run_schedule()

    p1.run.assert_called_once()
    p2.run.assert_called_once()


# --- _parse_subscription_ids tests ---


@patch.dict(os.environ, {"C7N_ACA_SUBSCRIPTION_IDS": "sub-a, sub-b , sub-c"})
def test_parse_subscription_ids_strips_whitespace():
    result = _parse_subscription_ids()
    assert result == ["sub-a", "sub-b", "sub-c"]


@patch.dict(os.environ, {"C7N_ACA_SUBSCRIPTION_IDS": "sub-a,,, sub-b,"})
def test_parse_subscription_ids_filters_empty():
    result = _parse_subscription_ids()
    assert result == ["sub-a", "sub-b"]


# --- main() env validation tests ---


@patch.dict(os.environ, {"C7N_ACA_MODE": "schedule"}, clear=True)
def test_main_missing_env_vars():
    from c7n_azure_aca.handler import main

    with pytest.raises(SystemExit):
        main()


@patch.dict(
    os.environ,
    {
        "C7N_ACA_MODE": "invalid",
        "C7N_ACA_STORAGE_ACCOUNT": "testaccount",
        "C7N_ACA_SUBSCRIPTION_IDS": "sub-aaa",
    },
)
def test_main_invalid_mode():
    from c7n_azure_aca.handler import main

    with pytest.raises(SystemExit):
        main()


# --- Event mode edge cases ---


@patch.dict(
    os.environ,
    {
        "C7N_ACA_MODE": "event",
        "C7N_ACA_STORAGE_ACCOUNT": "testaccount",
        "C7N_ACA_SUBSCRIPTION_IDS": "sub-111",
        "C7N_ACA_QUEUE_NAME": "test-queue",
    },
)
@patch("c7n_azure_aca.handler.load_policies_from_blob")
@patch("c7n_azure_aca.handler.QueueClient")
@patch("c7n_azure_aca.handler.DefaultAzureCredential")
@patch("c7n_azure_aca.handler.reset_session_cache")
def test_run_event_empty_queue(mock_reset, mock_cred, mock_queue_cls, mock_load):
    """Empty queue should complete gracefully."""
    from c7n_azure_aca.handler import run_event

    mock_load.return_value = []
    queue_client = MagicMock()
    queue_client.receive_messages.return_value = []
    mock_queue_cls.return_value = queue_client

    run_event()

    queue_client.delete_message.assert_not_called()


@patch.dict(
    os.environ,
    {
        "C7N_ACA_MODE": "event",
        "C7N_ACA_STORAGE_ACCOUNT": "testaccount",
        "C7N_ACA_SUBSCRIPTION_IDS": "sub-111",
        "C7N_ACA_QUEUE_NAME": "test-queue",
    },
)
@patch("c7n_azure_aca.handler.load_policies_from_blob")
@patch("c7n_azure_aca.handler.QueueClient")
@patch("c7n_azure_aca.handler.DefaultAzureCredential")
@patch("c7n_azure_aca.handler.reset_session_cache")
def test_run_event_poison_pill_deleted(mock_reset, mock_cred, mock_queue_cls, mock_load):
    """Invalid message content should be deleted (poison pill prevention)."""
    from c7n_azure_aca.handler import run_event

    mock_load.return_value = []
    msg = MagicMock()
    msg.content = "not-valid-base64!!!"

    queue_client = MagicMock()
    queue_client.receive_messages.return_value = [msg]
    mock_queue_cls.return_value = queue_client

    run_event()

    # Even though processing failed, message is deleted
    queue_client.delete_message.assert_called_once_with(msg)


@patch.dict(
    os.environ,
    {
        "C7N_ACA_MODE": "event",
        "C7N_ACA_STORAGE_ACCOUNT": "testaccount",
        "C7N_ACA_SUBSCRIPTION_IDS": "sub-111",
        "C7N_ACA_QUEUE_NAME": "test-queue",
    },
)
@patch("c7n_azure_aca.handler.load_policies_from_blob")
@patch("c7n_azure_aca.handler.QueueClient")
@patch("c7n_azure_aca.handler.DefaultAzureCredential")
@patch("c7n_azure_aca.handler.reset_session_cache")
def test_run_event_unmonitored_subscription(mock_reset, mock_cred, mock_queue_cls, mock_load):
    """Event from an unmonitored subscription should log warning and still delete message."""
    from c7n_azure_aca.handler import run_event

    mock_load.return_value = []

    event = {
        "id": "evt-1",
        "subject": "/subscriptions/unknown-sub/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm1",
        "data": {"operationName": "Microsoft.Compute/virtualMachines/write"},
    }
    msg = MagicMock()
    msg.content = base64.b64encode(json.dumps(event).encode()).decode()

    queue_client = MagicMock()
    queue_client.receive_messages.return_value = [msg]
    mock_queue_cls.return_value = queue_client

    run_event()

    queue_client.delete_message.assert_called_once_with(msg)


@patch.dict(
    os.environ,
    {
        "C7N_ACA_MODE": "schedule",
        "C7N_ACA_STORAGE_ACCOUNT": "testaccount",
        "C7N_ACA_SUBSCRIPTION_IDS": "sub-aaa",
    },
)
@patch("c7n_azure_aca.handler.load_policies_from_blob")
@patch("c7n_azure_aca.handler.reset_session_cache")
def test_run_schedule_no_policies(mock_reset, mock_load):
    """No policies found should complete without error."""
    from c7n_azure_aca.handler import run_schedule

    mock_load.return_value = []

    run_schedule()

    mock_load.assert_called_once()
