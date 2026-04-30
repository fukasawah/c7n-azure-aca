targetScope = 'subscription'

@description('Display name of the custom role')
param roleName string

@description('Description of the custom role')
param roleDescription string

@description('Assignable scopes for the custom role')
param assignableScopes array

@description('Allowed control-plane actions for the custom role')
param actions array

@description('Excluded control-plane actions for the custom role')
param notActions array = []

var roleDefinitionGuid = guid(roleName)

resource roleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: roleDefinitionGuid
  properties: {
    roleName: roleName
    description: roleDescription
    type: 'CustomRole'
    permissions: [
      {
        actions: actions
        notActions: notActions
      }
    ]
    assignableScopes: assignableScopes
  }
}

output roleDefinitionId string = roleDefinition.id