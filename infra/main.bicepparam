using 'main.bicep'

// Optional: override the default base name used for derived resource names.
// param baseName = 'c7n-azure-aca'

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
