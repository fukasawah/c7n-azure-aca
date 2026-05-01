// Container Apps Job — Event trigger (queue-based, zero-scale)

param location string
param environmentId string
param identityId string
param identityClientId string
param containerImage string
param storageAccountName string
param queueName string = 'custodian-events'
param subscriptionIdsCsv string
@minValue(1)
@maxValue(31)
param eventBatchSize int = 30
@minValue(1)
param visibilityTimeout int = 300
param maxExecutions int = 1
param jobCpu string = '0.25'
param jobMemory string = '0.5Gi'
param tags object = {}

var outputHost = '${storageAccountName}.blob.${environment().suffixes.storage}'

resource job 'Microsoft.App/jobs@2024-10-02-preview' = {
  name: 'custodian-event'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    configuration: {
      triggerType: 'Event'
      eventTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
        scale: {
          minExecutions: 0
          maxExecutions: maxExecutions
          pollingInterval: 30
          rules: [
            {
              name: 'queue-rule'
              type: 'azure-queue'
              identity: identityId
              metadata: {
                accountName: storageAccountName
                queueName: queueName
                queueLength: string(eventBatchSize)
                queueLengthStrategy: 'visibleonly'
                cloud: 'AzurePublicCloud'
              }
            }
          ]
        }
      }
      replicaTimeout: 1800
      replicaRetryLimit: 1
    }
    template: {
      containers: [
        {
          name: 'custodian'
          image: containerImage
          resources: {
            cpu: json(jobCpu)
            memory: jobMemory
          }
          env: [
            { name: 'C7N_ACA_MODE', value: 'event' }
            { name: 'C7N_ACA_STORAGE_ACCOUNT', value: storageAccountName }
            { name: 'C7N_ACA_QUEUE_NAME', value: queueName }
            { name: 'C7N_ACA_EVENT_BATCH_SIZE', value: string(eventBatchSize) }
            { name: 'C7N_ACA_QUEUE_VISIBILITY_TIMEOUT', value: string(visibilityTimeout) }
            { name: 'C7N_ACA_SUBSCRIPTION_IDS', value: subscriptionIdsCsv }
            { name: 'C7N_ACA_OUTPUT_DIR', value: 'azure://${outputHost}/output' }
            { name: 'AZURE_CLIENT_ID', value: identityClientId }
            { name: 'AZURE_USE_MSI', value: 'true' }
          ]
        }
      ]
    }
  }
}

output jobId string = job.id
