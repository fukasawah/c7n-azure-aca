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

@description('Target subscription IDs for policy enforcement. format: ["id1", "id2"]')
param targetSubscriptionIds array

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

@description('Target queue messages per event job execution. Keep below 32 to preserve visible-only queue counting.')
@minValue(1)
@maxValue(31)
param eventBatchSize int = 30

@description('Queue message visibility timeout in seconds for event processing')
@minValue(1)
param visibilityTimeout int = 300

@description('Maximum concurrent event job executions (KEDA scaling)')
@minValue(1)
@maxValue(100)
param maxExecutions int = 1

param tags object = {}

@description('Create a custom role for the managed identity and assign it to the target scopes')
param createAndAssignCustomRole bool = true

@description('Optional custom role name override. Leave empty to use a deterministic default name.')
param customRoleName string = ''

@description('Include the common read permissions used by many policy checks in the managed identity custom role')
param includeCommonReadPermissions bool = true

@description('Allow resource tag updates through the managed identity custom role')
param allowTagManagement bool = true

@description('Allow start and stop style power operations through the managed identity custom role')
param allowPowerControl bool = false

@description('Watch virtual machine write events in Event Grid')
param watchVirtualMachineWriteEvents bool = true

@description('Watch storage account write events in Event Grid')
param watchStorageAccountWriteEvents bool = false

@description('Watch App Service write events in Event Grid')
param watchAppServiceWriteEvents bool = false

@description('Watch Azure SQL database write events in Event Grid')
param watchSqlDatabaseWriteEvents bool = false

module deployment './main.bicep' = {
  name: 'c7n-azure-aca-deployment'
  params: {
    location: location
    baseName: baseName
    resourceGroupName: resourceGroupName
    environmentName: environmentName
    storageAccountName: storageAccountName
    identityName: identityName
    containerImage: containerImage
    scheduleExpression: scheduleExpression
    targetSubscriptionIds: targetSubscriptionIds
    createAndAssignCustomRole: createAndAssignCustomRole
    customRoleName: customRoleName
    includeCommonReadPermissions: includeCommonReadPermissions
    allowTagManagement: allowTagManagement
    allowPowerControl: allowPowerControl
    watchVirtualMachineWriteEvents: watchVirtualMachineWriteEvents
    watchStorageAccountWriteEvents: watchStorageAccountWriteEvents
    watchAppServiceWriteEvents: watchAppServiceWriteEvents
    watchSqlDatabaseWriteEvents: watchSqlDatabaseWriteEvents
    queueName: queueName
    jobCpu: jobCpu
    jobMemory: jobMemory
    logRetentionInDays: logRetentionInDays
    enableAlerts: enableAlerts
    alertQueueDepthThreshold: alertQueueDepthThreshold
    alertJobFailureThreshold: alertJobFailureThreshold
    eventBatchSize: eventBatchSize
    visibilityTimeout: visibilityTimeout
    maxExecutions: maxExecutions
    tags: tags
  }
}