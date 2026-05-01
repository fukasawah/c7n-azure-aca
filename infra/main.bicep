// Cloud Custodian on Azure Container Apps — Main Bicep Orchestrator
// Deploys at subscription scope to create resource group and Event Grid subscriptions

targetScope = 'subscription'

@description('Azure region for all resources')
param location string = 'japaneast'

@description('Base name used to derive resource names when explicit names are not provided')
param baseName string = 'c7n-azure-aca'

@description('Optional resource group name override. Leave empty to derive from baseName.')
param resourceGroupName string = ''

@description('Optional Container Apps Environment name override. Leave empty to derive from baseName.')
param environmentName string = ''

@description('Optional storage account name override. Leave empty to generate a globally unique name from baseName.')
param storageAccountName string = ''

@description('Optional Managed Identity name override. Leave empty to derive from baseName.')
param identityName string = ''

@description('Container image reference')
param containerImage string = 'ghcr.io/fukasawah/c7n-azure-aca:latest'

@description('Cron expression for scheduled policy execution')
param scheduleExpression string = '*/15 * * * *'

@description('Target subscription IDs for policy enforcement')
param targetSubscriptionIds array

@description('Event Grid operation name filter (e.g. ["Microsoft.Compute/virtualMachines/write"])')
param eventOperationNames array = []

@description('Create a custom role for the managed identity and assign it to the target scopes')
param createAndAssignCustomRole bool = false

@description('Optional custom role name override. Leave empty to use a deterministic default name.')
param customRoleName string = ''

@description('Watch virtual machine write events in Event Grid')
param watchVirtualMachineWriteEvents bool = true

@description('Watch storage account write events in Event Grid')
param watchStorageAccountWriteEvents bool = false

@description('Watch App Service write events in Event Grid')
param watchAppServiceWriteEvents bool = false

@description('Watch Azure SQL database write events in Event Grid')
param watchSqlDatabaseWriteEvents bool = false

@description('Allow resource tag updates through the managed identity custom role')
param allowTagManagement bool = false

@description('Allow virtual machine power operations through the managed identity custom role')
param allowVirtualMachinePowerControl bool = false

@description('Allow App Service app setting updates through the managed identity custom role')
param allowAppServiceAppSettingsManagement bool = false

@description('Assign Contributor role to UAI on target subscriptions (for mutating actions)')
param assignContributorRole bool = false

@description('Storage Queue name for events')
param queueName string = 'custodian-events'

@description('Job CPU allocation')
param jobCpu string = '0.25'

@description('Job memory allocation')
param jobMemory string = '0.5Gi'

@description('Log Analytics retention in days (30-730)')
@minValue(30)
@maxValue(730)
param logRetentionInDays int = 90

@description('Enable monitoring alert rules')
param enableAlerts bool = true

@description('Queue depth threshold for alerting')
param alertQueueDepthThreshold int = 100

@description('Job failure count threshold for alerting (per 5-minute window)')
param alertJobFailureThreshold int = 3

@description('Maximum concurrent event job executions (KEDA scaling)')
@minValue(1)
@maxValue(100)
param maxExecutions int = 10

param tags object = {}

// Comma-separated subscription IDs for container env var
var normalizedBaseName = take(replace(replace(toLower(baseName), '-', ''), '_', ''), 11)
var effectiveResourceGroupName = !empty(resourceGroupName) ? resourceGroupName : 'rg-${baseName}'
var effectiveEnvironmentName = !empty(environmentName) ? environmentName : '${baseName}-env'
var effectiveIdentityName = !empty(identityName) ? identityName : '${baseName}-identity'
var storageAccountNamePrefix = take('sa${normalizedBaseName}', 13)
var effectiveStorageAccountName = !empty(storageAccountName)
  ? storageAccountName
  : '${storageAccountNamePrefix}${take(uniqueString(subscription().id, effectiveResourceGroupName, baseName), 11)}'
var subscriptionIdsCsv = join(targetSubscriptionIds, ',')
var toggledEventOperationNames = union(
  watchVirtualMachineWriteEvents ? ['Microsoft.Compute/virtualMachines/write'] : [],
  watchStorageAccountWriteEvents ? ['Microsoft.Storage/storageAccounts/write'] : [],
  watchAppServiceWriteEvents ? ['Microsoft.Web/sites/write'] : [],
  watchSqlDatabaseWriteEvents ? ['Microsoft.Sql/servers/databases/write'] : []
)
var effectiveEventOperationNames = !empty(eventOperationNames) ? eventOperationNames : toggledEventOperationNames
var customRoleAssignableScopes = [for subId in targetSubscriptionIds: '/subscriptions/${subId}']
var effectiveCustomRoleName = !empty(customRoleName)
  ? customRoleName
  : '${effectiveResourceGroupName}-managed-identity-role'
var customRoleActions = union(
  [
    'Microsoft.Resources/subscriptions/read'
    'Microsoft.Resources/subscriptions/resourceGroups/read'
  ],
  allowTagManagement
    ? [
        'Microsoft.Resources/subscriptions/resources/read'
        'Microsoft.Resources/subscriptions/resourceGroups/resources/read'
        'Microsoft.Resources/tags/read'
        'Microsoft.Resources/tags/write'
      ]
    : [],
  allowVirtualMachinePowerControl
    ? [
        'Microsoft.Compute/virtualMachines/read'
        'Microsoft.Compute/virtualMachines/start/action'
        'Microsoft.Compute/virtualMachines/restart/action'
        'Microsoft.Compute/virtualMachines/powerOff/action'
        'Microsoft.Compute/virtualMachines/deallocate/action'
      ]
    : [],
  allowAppServiceAppSettingsManagement
    ? [
        'Microsoft.Web/sites/read'
        'Microsoft.Web/sites/config/read'
        'microsoft.web/sites/config/web/appsettings/write'
        'microsoft.web/sites/config/web/appsettings/delete'
      ]
    : []
)

module customRole 'modules/custom-role-definition.bicep' = if (createAndAssignCustomRole) {
  name: 'custom-role-definition'
  params: {
    roleName: effectiveCustomRoleName
    roleDescription: 'Managed identity role for ${effectiveResourceGroupName}. Generated from template toggle parameters.'
    assignableScopes: customRoleAssignableScopes
    actions: customRoleActions
  }
}

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: effectiveResourceGroupName
  location: location
  tags: tags
}

// User-Assigned Managed Identity
module identity 'modules/identity.bicep' = {
  scope: rg
  name: 'identity'
  params: {
    location: location
    identityName: effectiveIdentityName
    tags: tags
  }
}

// Storage Account (Queue + Blob)
module storage 'modules/storage.bicep' = {
  scope: rg
  name: 'storage'
  params: {
    location: location
    storageAccountName: effectiveStorageAccountName
    queueName: queueName
    tags: tags
  }
}

// Log Analytics Workspace
module logAnalytics 'modules/log-analytics.bicep' = {
  scope: rg
  name: 'log-analytics'
  params: {
    location: location
    workspaceName: '${effectiveEnvironmentName}-logs'
    retentionInDays: logRetentionInDays
    tags: tags
  }
}

// Container Apps Environment
module environment 'modules/container-apps-env.bicep' = {
  scope: rg
  name: 'container-apps-env'
  params: {
    location: location
    environmentName: effectiveEnvironmentName
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: tags
  }
}

// Schedule Job (cron-based periodic execution)
module scheduleJob 'modules/container-apps-job-schedule.bicep' = {
  scope: rg
  name: 'job-schedule'
  params: {
    location: location
    environmentId: environment.outputs.environmentId
    identityId: identity.outputs.identityId
    identityClientId: identity.outputs.identityClientId
    containerImage: containerImage
    storageAccountName: effectiveStorageAccountName
    subscriptionIdsCsv: subscriptionIdsCsv
    scheduleExpression: scheduleExpression
    jobCpu: jobCpu
    jobMemory: jobMemory
    tags: tags
  }
}

// Event Job (queue-triggered, zero-scale)
module eventJob 'modules/container-apps-job-event.bicep' = {
  scope: rg
  name: 'job-event'
  params: {
    location: location
    environmentId: environment.outputs.environmentId
    identityId: identity.outputs.identityId
    identityClientId: identity.outputs.identityClientId
    containerImage: containerImage
    storageAccountName: effectiveStorageAccountName
    queueName: queueName
    subscriptionIdsCsv: subscriptionIdsCsv
    maxExecutions: maxExecutions
    jobCpu: jobCpu
    jobMemory: jobMemory
    tags: tags
  }
}

// Monitoring Alerts
module alerts 'modules/alerts.bicep' = {
  scope: rg
  name: 'alerts'
  params: {
    location: location
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    storageAccountName: effectiveStorageAccountName
    queueDepthThreshold: alertQueueDepthThreshold
    jobFailureThreshold: alertJobFailureThreshold
    enableAlerts: enableAlerts
    tags: tags
  }
  dependsOn: [storage]
}

// RBAC — storage access (resource-group scoped)
module storageRoleAssignments 'modules/role-assignments.bicep' = {
  scope: rg
  name: 'role-assignments-storage'
  params: {
    identityPrincipalId: identity.outputs.identityPrincipalId
    storageAccountName: effectiveStorageAccountName
  }
  dependsOn: [storage]
}

// RBAC — Reader/Contributor on each target subscription
module subscriptionRoleAssignments 'modules/role-assignment-subscription.bicep' = [
  for (subId, i) in targetSubscriptionIds: {
    scope: subscription(subId)
    name: 'role-assignments-sub-${i}'
    params: {
      identityPrincipalId: identity.outputs.identityPrincipalId
      roleDefinitionId: createAndAssignCustomRole ? customRole!.outputs.roleDefinitionId : ''
      assignContributorRole: assignContributorRole
    }
  }
]

// Event Grid — one subscription per target subscription
module eventGrid 'modules/event-grid.bicep' = [
  for (subId, i) in targetSubscriptionIds: {
    scope: subscription(subId)
    name: 'event-grid-${i}'
    params: {
      storageAccountResourceId: storage.outputs.storageAccountId
      queueName: queueName
      eventOperationNames: effectiveEventOperationNames
      eventSubscriptionName: 'custodian-${queueName}'
    }
  }
]
