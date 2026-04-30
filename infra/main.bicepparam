using 'main.bicep'

param storageAccountName = 'custodianstore${uniqueString(subscription().id)}'

param targetSubscriptionIds = [
  // Add your target subscription IDs here
  // '<subscription-id-1>'
  // '<subscription-id-2>'
]

param eventOperationNames = [
  // Filter Event Grid to specific operations, e.g.:
  // 'Microsoft.Compute/virtualMachines/write'
  // 'Microsoft.Storage/storageAccounts/write'
]
