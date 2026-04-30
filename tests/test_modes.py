"""Tests for execution mode registration via c7n-azure native container-host modes."""

from c7n_azure.entry import initialize_azure
from c7n.policy import execution
from c7n_azure.container_host.modes import AzureContainerPeriodicMode, AzureContainerEventMode

initialize_azure()


def test_container_periodic_registered():
    assert "container-periodic" in execution


def test_container_event_registered():
    assert "container-event" in execution


def test_periodic_mode_run(mocker):
    mock_policy = mocker.MagicMock()
    mode = AzureContainerPeriodicMode(mock_policy)
    mocker.patch("c7n.policy.PullMode.run", return_value=[])
    result = mode.run()
    assert result == []


def test_event_mode_run(mocker):
    mock_policy = mocker.MagicMock()
    mode = AzureContainerEventMode(mock_policy)
    mock_run_for_event = mocker.patch(
        "c7n_azure.policy.AzureModeCommon.run_for_event", return_value=[]
    )
    event = {"data": {"operationName": "test"}}
    result = mode.run(event=event)
    mock_run_for_event.assert_called_once_with(mock_policy, event)
    assert result == []


def test_periodic_provision():
    """provision() should be a no-op for container-host modes."""
    from unittest.mock import MagicMock

    mode = AzureContainerPeriodicMode(MagicMock())
    mode.provision()


def test_event_provision():
    """provision() should be a no-op for container-host modes."""
    from unittest.mock import MagicMock

    mode = AzureContainerEventMode(MagicMock())
    mode.provision()
