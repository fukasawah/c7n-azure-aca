import pytest


@pytest.fixture
def sample_event():
    """A minimal Event Grid event as received from Storage Queue."""
    return {
        "id": "test-event-id",
        "topic": "/subscriptions/sub-111/resourceGroups/rg-test",
        "subject": "/subscriptions/sub-111/resourceGroups/rg-test/providers/Microsoft.Compute/virtualMachines/vm1",
        "eventType": "Microsoft.Resources.ResourceWriteSuccess",
        "data": {
            "operationName": "Microsoft.Compute/virtualMachines/write",
            "resourceUri": "/subscriptions/sub-111/resourceGroups/rg-test/providers/Microsoft.Compute/virtualMachines/vm1",
        },
        "dataVersion": "2",
        "metadataVersion": "1",
        "eventTime": "2025-01-01T00:00:00Z",
    }


@pytest.fixture
def periodic_policy_yaml():
    return {
        "policies": [
            {
                "name": "test-periodic",
                "resource": "azure.vm",
                "mode": {"type": "container-periodic"},
                "filters": [{"type": "value", "key": "name", "value": "test"}],
            }
        ]
    }


@pytest.fixture
def event_policy_yaml():
    return {
        "policies": [
            {
                "name": "test-event",
                "resource": "azure.vm",
                "mode": {
                    "type": "container-event",
                    "events": [
                        {
                            "resourceProvider": "Microsoft.Compute/virtualMachines",
                            "event": "write",
                        }
                    ],
                },
                "filters": [{"type": "value", "key": "name", "value": "test"}],
            }
        ]
    }
