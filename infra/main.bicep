// Cloud Custodian on Azure Container Apps — Main Bicep Orchestrator
// Deploys at subscription scope to create resource group and Event Grid subscriptions

targetScope = 'subscription'

@description('Azure region for all resources')
param location string = 'japaneast'

@description('Resource group name')
param resourceGroupName string = 'rg-custodian'

@description('Container Apps Environment name')
param environmentName string = 'custodian-env'

@description('Storage account name (globally unique)')
param storageAccountName string

@description('Managed Identity name')
param identityName string = 'custodian-identity'

@description('Container image reference')
param containerImage string = 'ghcr.io/fukasawah/c7n-azure-aca:latest'

@description('Cron expression for scheduled policy execution')
param scheduleExpression string = '*/15 * * * *'

@description('Target subscription IDs for policy enforcement')
param targetSubscriptionIds array

@description('Event Grid operation name filter (e.g. ["Microsoft.Compute/virtualMachines/write"])')
param eventOperationNames array = []

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
var subscriptionIdsCsv = join(targetSubscriptionIds, ',')

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// User-Assigned Managed Identity
module identity 'modules/identity.bicep' = {
  scope: rg
  name: 'identity'
  params: {
    location: location
    identityName: identityName
    tags: tags
  }
}

// Storage Account (Queue + Blob)
module storage 'modules/storage.bicep' = {
  scope: rg
  name: 'storage'
  params: {
    location: location
    storageAccountName: storageAccountName
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
    workspaceName: '${environmentName}-logs'
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
    environmentName: environmentName
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
    storageAccountName: storageAccountName
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
    storageAccountName: storageAccountName
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
    storageAccountName: storageAccountName
    queueDepthThreshold: alertQueueDepthThreshold
    jobFailureThreshold: alertJobFailureThreshold
    enableAlerts: enableAlerts
    tags: tags
  }
  dependsOn: [storage, logAnalytics]
}

// RBAC — storage access (resource-group scoped)
module storageRoleAssignments 'modules/role-assignments.bicep' = {
  scope: rg
  name: 'role-assignments-storage'
  params: {
    identityPrincipalId: identity.outputs.identityPrincipalId
    storageAccountName: storageAccountName
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
      eventOperationNames: eventOperationNames
      eventSubscriptionName: 'custodian-${queueName}'
    }
  }
]
