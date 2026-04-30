// RBAC role assignments at target resource group scope
// Deployed once per target resource group to grant Reader (and optionally Contributor)

targetScope = 'resourceGroup'

param identityPrincipalId string
param roleDefinitionId string = ''
param assignContributorRole bool = false

var readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

// Reader on target resource group (for resource enumeration by policies)
resource readerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (empty(roleDefinitionId)) {
  name: guid(resourceGroup().id, identityPrincipalId, readerRoleId)
  properties: {
    principalId: identityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
    principalType: 'ServicePrincipal'
  }
}

resource customRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(roleDefinitionId)) {
  name: guid(resourceGroup().id, identityPrincipalId, roleDefinitionId)
  properties: {
    principalId: identityPrincipalId
    roleDefinitionId: roleDefinitionId
    principalType: 'ServicePrincipal'
  }
}

// Contributor on target resource group (optional, for policies with mutating actions)
resource contributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (empty(roleDefinitionId) && assignContributorRole) {
  name: guid(resourceGroup().id, identityPrincipalId, contributorRoleId)
  properties: {
    principalId: identityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalType: 'ServicePrincipal'
  }
}