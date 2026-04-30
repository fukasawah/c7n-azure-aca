// Container Apps Job — Schedule trigger (cron-based periodic execution)

param location string
param environmentId string
param identityId string
param identityClientId string
param containerImage string
param storageAccountName string
param subscriptionIdsCsv string
param scheduleExpression string = '*/15 * * * *'
param jobCpu string = '0.25'
param jobMemory string = '0.5Gi'
param tags object = {}

var outputHost = '${storageAccountName}.blob.${environment().suffixes.storage}'

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: 'custodian-schedule'
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
      triggerType: 'Schedule'
      scheduleTriggerConfig: {
        cronExpression: scheduleExpression
        parallelism: 1
        replicaCompletionCount: 1
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
            { name: 'C7N_ACA_MODE', value: 'schedule' }
            { name: 'C7N_ACA_STORAGE_ACCOUNT', value: storageAccountName }
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
