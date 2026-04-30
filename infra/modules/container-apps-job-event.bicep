// Container Apps Job — Event trigger (queue-based, zero-scale)

param location string
param environmentId string
param identityId string
param identityClientId string
param containerImage string
param storageAccountName string
param queueName string = 'custodian-events'
param subscriptionIdsCsv string
param maxExecutions int = 10
param jobCpu string = '0.25'
param jobMemory string = '0.5Gi'
param tags object = {}

resource job 'Microsoft.App/jobs@2024-03-01' = {
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
                queueLength: '1'
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
            { name: 'C7N_ACA_SUBSCRIPTION_IDS', value: subscriptionIdsCsv }
            { name: 'C7N_ACA_OUTPUT_DIR', value: 'azure://${storageAccountName}/output' }
            { name: 'AZURE_CLIENT_ID', value: identityClientId }
          ]
        }
      ]
    }
  }
}

output jobId string = job.id
