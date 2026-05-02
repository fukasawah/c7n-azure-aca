// Alert rules for monitoring Container Apps Jobs and Storage Queue

param location string
param logAnalyticsWorkspaceId string
param storageAccountName string
param tags object = {}

var queueServiceResourceId = resourceId('Microsoft.Storage/storageAccounts/queueServices', storageAccountName, 'default')

@description('Queue depth threshold to trigger alert')
@minValue(1)
param queueDepthThreshold int = 100

@description('Job failure count threshold to trigger alert (evaluation window: 5 minutes)')
@minValue(1)
param jobFailureThreshold int = 3

@description('Enable alert rules')
param enableAlerts bool = true

// Action Group (email placeholder — customize after deployment)
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'custodian-alerts-ag'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'c7n-alerts'
    enabled: enableAlerts
    emailReceivers: []
  }
}

// Alert: Container Apps Job failures
resource jobFailureAlert 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: 'custodian-job-failure'
  location: location
  tags: tags
  properties: {
    displayName: 'Custodian Job Execution Failures'
    description: 'Alerts when Container Apps Jobs fail repeatedly'
    severity: 2
    enabled: enableAlerts
    evaluationFrequency: 'PT6H'
    windowSize: 'PT6H'
    skipQueryValidation: true
    scopes: [
      logAnalyticsWorkspaceId
    ]
    criteria: {
      allOf: [
        {
          query: '''
            union isfuzzy=true
              (ContainerAppSystemLogs_CL
              | project TimeGenerated, ContainerAppName = tostring(ContainerAppName_s), LogMessage = tostring(Log_s)),
              (ContainerAppConsoleLogs_CL
              | project TimeGenerated, ContainerAppName = tostring(ContainerAppName_s), LogMessage = tostring(Log_s)),
              (datatable(TimeGenerated:datetime, ContainerAppName:string, LogMessage:string)[])
            | where ContainerAppName startswith "custodian-"
            | where LogMessage contains "Error" or LogMessage contains "Failed" or LogMessage contains "Exception"
            | summarize FailureCount = count() by bin(TimeGenerated, 5m)
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThanOrEqual'
          threshold: jobFailureThreshold
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

// Alert: Queue depth too high (messages accumulating)
resource queueDepthAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'custodian-queue-depth'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alerts when the custodian event queue has too many pending messages'
    severity: 3
    enabled: enableAlerts
    evaluationFrequency: 'PT6H'
    windowSize: 'PT6H'
    scopes: [
      queueServiceResourceId
    ]
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'QueueMessageCount'
          metricName: 'QueueMessageCount'
          metricNamespace: 'Microsoft.Storage/storageAccounts/queueServices'
          operator: 'GreaterThan'
          threshold: queueDepthThreshold
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}
