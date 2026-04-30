"""Tests for policy_loader module."""

from unittest.mock import MagicMock, patch

import yaml

from c7n_azure_aca.policy_loader import load_policies_from_blob


class FakeBlob:
    def __init__(self, name, content):
        self.name = name
        self._content = content

    def readall(self):
        return self._content


class FakeBlobClient:
    def __init__(self, content):
        self._content = content

    def download_blob(self):
        return FakeBlob("", self._content)


class FakeContainerClient:
    def __init__(self, blobs):
        self._blobs = blobs  # list of (name, content_bytes)

    def list_blobs(self):
        return [MagicMock(name=n) for n, _ in self._blobs]

    def get_blob_client(self, name):
        for n, content in self._blobs:
            if n == name:
                return FakeBlobClient(content)
        raise ValueError(f"Blob {name} not found")


def _make_blob_name_mock(name):
    """MagicMock whose .name is a real string (not a mock)."""
    m = MagicMock()
    m.name = name
    return m


@patch("c7n_azure_aca.policy_loader.Azure")
@patch("c7n_azure_aca.policy_loader.load_resources")
@patch("c7n_azure_aca.policy_loader.ContainerClient")
def test_load_periodic_policies(mock_cc_cls, mock_load_res, mock_azure):
    policy_yaml = yaml.dump(
        {
            "policies": [
                {
                    "name": "test-periodic",
                    "resource": "azure.vm",
                    "mode": {"type": "container-periodic"},
                },
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
                },
            ]
        }
    )

    blob_mock = _make_blob_name_mock("policies.yaml")
    blob_client_mock = MagicMock()
    blob_client_mock.download_blob.return_value.readall.return_value = policy_yaml.encode()

    container_client_mock = MagicMock()
    container_client_mock.list_blobs.return_value = [blob_mock]
    container_client_mock.get_blob_client.return_value = blob_client_mock
    mock_cc_cls.from_container_url.return_value = container_client_mock

    mock_azure_instance = MagicMock()
    mock_azure_instance.initialize.return_value = MagicMock()
    mock_azure.return_value = mock_azure_instance

    with patch("c7n_azure_aca.policy_loader.PolicyCollection") as mock_pc:
        mock_pc.from_data.return_value = []
        load_policies_from_blob(
            storage_account_name="testaccount",
            container_name="policies",
            mode_type="container-periodic",
            subscription_id="sub-123",
            output_dir="azure://testaccount/output",
        )

    # from_data should receive only the periodic policy
    call_args = mock_pc.from_data.call_args
    policy_data = call_args[0][0]
    assert len(policy_data["policies"]) == 1
    assert policy_data["policies"][0]["name"] == "test-periodic"


@patch("c7n_azure_aca.policy_loader.ContainerClient")
def test_load_no_matching_policies(mock_cc_cls):
    policy_yaml = yaml.dump(
        {
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
                }
            ]
        }
    )

    blob_mock = _make_blob_name_mock("policies.yaml")
    blob_client_mock = MagicMock()
    blob_client_mock.download_blob.return_value.readall.return_value = policy_yaml.encode()

    container_client_mock = MagicMock()
    container_client_mock.list_blobs.return_value = [blob_mock]
    container_client_mock.get_blob_client.return_value = blob_client_mock
    mock_cc_cls.from_container_url.return_value = container_client_mock

    result = load_policies_from_blob(
        storage_account_name="testaccount",
        container_name="policies",
        mode_type="container-periodic",
        subscription_id="sub-123",
        output_dir="azure://testaccount/output",
    )
    # No matching policies → empty collection
    assert len(result) == 0


@patch("c7n_azure_aca.policy_loader.ContainerClient")
def test_load_skips_non_yaml_files(mock_cc_cls):
    blob_mock = _make_blob_name_mock("readme.txt")

    container_client_mock = MagicMock()
    container_client_mock.list_blobs.return_value = [blob_mock]
    mock_cc_cls.from_container_url.return_value = container_client_mock

    result = load_policies_from_blob(
        storage_account_name="testaccount",
        container_name="policies",
        mode_type="container-periodic",
        subscription_id="sub-123",
        output_dir="azure://testaccount/output",
    )
    assert len(result) == 0


@patch("c7n_azure_aca.policy_loader.ContainerClient")
def test_load_skips_invalid_yaml(mock_cc_cls):
    blob_mock = _make_blob_name_mock("bad.yaml")
    blob_client_mock = MagicMock()
    blob_client_mock.download_blob.return_value.readall.return_value = b"{{invalid yaml"

    container_client_mock = MagicMock()
    container_client_mock.list_blobs.return_value = [blob_mock]
    container_client_mock.get_blob_client.return_value = blob_client_mock
    mock_cc_cls.from_container_url.return_value = container_client_mock

    result = load_policies_from_blob(
        storage_account_name="testaccount",
        container_name="policies",
        mode_type="container-periodic",
        subscription_id="sub-123",
        output_dir="azure://testaccount/output",
    )
    assert len(result) == 0


@patch("c7n_azure_aca.policy_loader.ContainerClient")
def test_load_handles_blob_list_failure(mock_cc_cls):
    """Failure to list blobs should return empty collection gracefully."""
    container_client_mock = MagicMock()
    container_client_mock.list_blobs.side_effect = Exception("connection refused")
    mock_cc_cls.from_container_url.return_value = container_client_mock

    result = load_policies_from_blob(
        storage_account_name="testaccount",
        container_name="policies",
        mode_type="container-periodic",
        subscription_id="sub-123",
        output_dir="azure://testaccount/output",
    )
    assert len(result) == 0


@patch("c7n_azure_aca.policy_loader.ContainerClient")
def test_load_handles_blob_download_failure(mock_cc_cls):
    """Failure to download a single blob should skip it and continue."""
    blob_mock = _make_blob_name_mock("policies.yml")
    blob_client_mock = MagicMock()
    blob_client_mock.download_blob.side_effect = Exception("timeout")

    container_client_mock = MagicMock()
    container_client_mock.list_blobs.return_value = [blob_mock]
    container_client_mock.get_blob_client.return_value = blob_client_mock
    mock_cc_cls.from_container_url.return_value = container_client_mock

    result = load_policies_from_blob(
        storage_account_name="testaccount",
        container_name="policies",
        mode_type="container-periodic",
        subscription_id="sub-123",
        output_dir="azure://testaccount/output",
    )
    assert len(result) == 0


@patch("c7n_azure_aca.policy_loader.ContainerClient")
def test_load_skips_non_dict_yaml(mock_cc_cls):
    """YAML that parses to a list instead of dict should be skipped."""
    blob_mock = _make_blob_name_mock("list.yaml")
    blob_client_mock = MagicMock()
    blob_client_mock.download_blob.return_value.readall.return_value = b"- item1\n- item2\n"

    container_client_mock = MagicMock()
    container_client_mock.list_blobs.return_value = [blob_mock]
    container_client_mock.get_blob_client.return_value = blob_client_mock
    mock_cc_cls.from_container_url.return_value = container_client_mock

    result = load_policies_from_blob(
        storage_account_name="testaccount",
        container_name="policies",
        mode_type="container-periodic",
        subscription_id="sub-123",
        output_dir="azure://testaccount/output",
    )
    assert len(result) == 0
