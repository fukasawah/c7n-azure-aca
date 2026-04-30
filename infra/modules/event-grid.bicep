// Event Grid subscription at target subscription scope
// Forwards resource write events to a Storage Queue

targetScope = 'subscription'

param storageAccountResourceId string
param queueName string = 'custodian-events'
param eventOperationNames array = []
param eventSubscriptionName string = 'custodian-events'

@description('Blob container resource ID for dead-letter destination (storage account resource ID used)')
param deadLetterContainerName string = 'event-deadletter'

resource eventSub 'Microsoft.EventGrid/eventSubscriptions@2022-06-15' = {
  name: eventSubscriptionName
  properties: {
    destination: {
      endpointType: 'StorageQueue'
      properties: {
        resourceId: storageAccountResourceId
        queueName: queueName
        queueMessageTimeToLiveInSeconds: 86400
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Resources.ResourceWriteSuccess'
      ]
      advancedFilters: empty(eventOperationNames)
        ? []
        : [
            {
              operatorType: 'StringIn'
              key: 'data.operationName'
              values: eventOperationNames
            }
          ]
    }
    deadLetterDestination: {
      endpointType: 'StorageBlob'
      properties: {
        resourceId: storageAccountResourceId
        blobContainerName: deadLetterContainerName
      }
    }
    retryPolicy: {
      maxDeliveryAttempts: 10
      eventTimeToLiveInMinutes: 1440
    }
  }
}
