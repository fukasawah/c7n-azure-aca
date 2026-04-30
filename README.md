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
- The current template exposes on/off parameters for watched resource events and for the permissions added to the managed identity custom role.

## Customizing Permissions And Event Filters

If you want to customize the values behind the deploy-button toggles, edit [infra/main.bicep](infra/main.bicep).

- `customRoleActions` uses Azure RBAC action strings. Use the Microsoft Learn Azure permissions reference to find valid values for each resource provider: <https://learn.microsoft.com/azure/role-based-access-control/resource-provider-operations>
- `toggledEventOperationNames` is used as the Event Grid `data.operationName` filter for `Microsoft.Resources.ResourceWriteSuccess` events. Microsoft Learn documents this field and shows examples such as `Microsoft.Compute/virtualMachines/write` and `Microsoft.Storage/storageAccounts/write`: <https://learn.microsoft.com/azure/event-grid/event-schema-subscriptions>
- In practice, the Event Grid `operationName` values for Azure Resource Manager write events follow the same resource-provider operation strings used by Azure RBAC. That means the Azure permissions reference is also the practical master list when you want to add more watched write operations.
- For background on custom roles, assignable scopes, and action formatting, see Microsoft Learn: <https://learn.microsoft.com/azure/role-based-access-control/custom-roles>