// RBAC role assignments at target subscription scope
// Deployed once per target subscription to grant Reader (and optionally Contributor)

targetScope = 'subscription'

param identityPrincipalId string
param assignContributorRole bool = false

var readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

// Reader on target subscription (for resource enumeration by policies)
resource readerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, identityPrincipalId, readerRoleId)
  properties: {
    principalId: identityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
    principalType: 'ServicePrincipal'
  }
}

// Contributor on target subscription (optional, for policies with mutating actions)
resource contributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignContributorRole) {
  name: guid(subscription().id, identityPrincipalId, contributorRoleId)
  properties: {
    principalId: identityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalType: 'ServicePrincipal'
  }
}
