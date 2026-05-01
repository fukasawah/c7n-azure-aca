# ⚠️Work In Progress⚠️

# c7n-azure-aca

Cloud Custodian policy execution on Azure Container Apps Jobs.

## Quick Deploy

This repository includes a subscription-scope ARM template for Azure Portal deployment.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ffukasawah%2Fc7n-azure-aca%2Fmain%2Finfra%2Fazuredeploy.json)

The button opens the Azure Portal parameter form for the current template in [infra/azuredeploy.json](infra/azuredeploy.json).

## Template Source

- Authoring template: [infra/azuredeploy.bicep](infra/azuredeploy.bicep)
- Main deployment logic: [infra/main.bicep](infra/main.bicep)
- Built ARM template for the deploy button: [infra/azuredeploy.json](infra/azuredeploy.json)

To rebuild the ARM template after editing the Bicep source:

```bash
az bicep build --file infra/azuredeploy.bicep --outfile infra/azuredeploy.json
```

## Notes

- The Deploy to Azure button uses the standard Azure Portal parameter form for the ARM template.
- The current template exposes on/off parameters for watched resource events and three managed identity permission presets: common reads, tag updates, and power operations.
- The deploy template now uses `baseName` to derive default names such as the resource group, managed identity, Container Apps environment, and storage account. You can still override each name individually when needed.

## Customizing Permissions And Event Filters

If you want to customize the values behind the deploy-button toggles, edit [infra/main.bicep](infra/main.bicep).
- `baseName` is the common naming seed. By default, the template derives names such as `rg-${baseName}`, `${baseName}-env`, `${baseName}-identity`, and a globally unique storage account name like `sac7nazureaca...`.
- If `storageAccountName` is left empty, the template generates a compliant storage account name automatically from `baseName` plus a deterministic unique suffix.
- The managed identity custom role exposes three preset switches: `includeCommonReadPermissions=true`, `allowTagManagement=true`, and `allowPowerControl=false`.
- `includeCommonReadPermissions` is intentionally a pragmatic starter set for common policy checks, not a full Azure Reader replacement. If your policy needs more provider operations, extend `commonReadActions` in [infra/main.bicep](infra/main.bicep).
- `customRoleActions` uses Azure RBAC action strings. Use the Microsoft Learn Azure permissions reference to find valid values for each resource provider: <https://learn.microsoft.com/azure/role-based-access-control/resource-provider-operations>
- `toggledEventOperationNames` is used as the Event Grid `data.operationName` filter for `Microsoft.Resources.ResourceWriteSuccess` events. Microsoft Learn documents this field and shows examples such as `Microsoft.Compute/virtualMachines/write` and `Microsoft.Storage/storageAccounts/write`: <https://learn.microsoft.com/azure/event-grid/event-schema-subscriptions>
- In practice, the Event Grid `operationName` values for Azure Resource Manager write events follow the same resource-provider operation strings used by Azure RBAC. That means the Azure permissions reference is also the practical master list when you want to add more watched write operations.
- For background on custom roles, assignable scopes, and action formatting, see Microsoft Learn: <https://learn.microsoft.com/azure/role-based-access-control/custom-roles>