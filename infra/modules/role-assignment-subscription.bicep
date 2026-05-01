// RBAC role assignments at target subscription scope
// Deployed once per target subscription to grant either Reader or the generated custom role

targetScope = 'subscription'

param identityPrincipalId string
param roleDefinitionId string = ''

var readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

// Reader on target subscription (for resource enumeration by policies)
resource readerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (empty(roleDefinitionId)) {
  name: guid(subscription().id, identityPrincipalId, readerRoleId)
  properties: {
    principalId: identityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
    principalType: 'ServicePrincipal'
  }
}

resource customRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(roleDefinitionId)) {
  name: guid(subscription().id, identityPrincipalId, roleDefinitionId)
  properties: {
    principalId: identityPrincipalId
    roleDefinitionId: roleDefinitionId
    principalType: 'ServicePrincipal'
  }
}
