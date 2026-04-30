"""Load c7n policies from Azure Blob Storage."""

import logging

import yaml
from azure.identity import DefaultAzureCredential
from azure.storage.blob import ContainerClient

from c7n.config import Config
from c7n.policy import PolicyCollection
from c7n.resources import load_resources
from c7n.structure import StructureParser

from c7n_azure.provider import Azure

log = logging.getLogger("c7n_aca.policy_loader")


def load_policies_from_blob(
    storage_account_name: str,
    container_name: str,
    mode_type: str,
    subscription_id: str,
    output_dir: str,
) -> PolicyCollection:
    """Download all YAML from a blob container and return policies matching mode_type.

    Args:
        storage_account_name: Azure Storage account name.
        container_name: Blob container holding policy YAML files.
        mode_type: Filter policies to this mode (e.g. "container-periodic" or "container-event").
        subscription_id: Target Azure subscription ID for policy execution.
        output_dir: c7n output directory URI (e.g. "azure://account.blob.core.windows.net/output").

    Returns:
        A PolicyCollection containing only policies whose mode.type matches mode_type.
    """
    credential = DefaultAzureCredential()
    container_url = f"https://{storage_account_name}.blob.core.windows.net/{container_name}"
    container_client = ContainerClient.from_container_url(container_url, credential=credential)

    all_policy_data: dict = {"policies": []}
    try:
        blobs = list(container_client.list_blobs())
    except Exception:
        log.exception("Failed to list blobs from %s/%s", storage_account_name, container_name)
        return PolicyCollection([], Config.empty())

    for blob in blobs:
        if not (blob.name.endswith(".yml") or blob.name.endswith(".yaml")):
            continue
        try:
            blob_client = container_client.get_blob_client(blob.name)
            content = blob_client.download_blob().readall()
        except Exception:
            log.exception("Failed to download blob %s, skipping", blob.name)
            continue
        try:
            parsed = yaml.safe_load(content)
        except yaml.YAMLError:
            log.warning("Failed to parse %s, skipping", blob.name)
            continue
        if isinstance(parsed, dict) and "policies" in parsed:
            for p in parsed["policies"]:
                if p.get("mode", {}).get("type") == mode_type:
                    all_policy_data["policies"].append(p)

    if not all_policy_data["policies"]:
        return PolicyCollection([], Config.empty())

    # Load resource types referenced by the policies
    resource_types = StructureParser().get_resource_types(all_policy_data)
    load_resources(resource_types)

    # Initialize Azure provider with target subscription
    options = Config.empty(
        account_id=subscription_id,
        output_dir=output_dir,
    )
    options = Azure().initialize(options)

    policies = PolicyCollection.from_data(all_policy_data, options)
    valid_policies = []
    for p in policies:
        try:
            p.validate()
            valid_policies.append(p)
        except Exception:
            log.exception("Policy validation failed: %s, skipping", p.name)
    return PolicyCollection(valid_policies, options)
