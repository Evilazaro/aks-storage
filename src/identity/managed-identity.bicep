param location string
param tags object

var roleAssignments = [
  '17d1049b-9a84-46fb-8f53-869881c3d3ab'
  '69566ab7-960f-475b-8e7c-b3118f30c6bd'
]

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'aks-demo-${uniqueString(resourceGroup().id)}-identity'
  location: location
  tags: tags
}

output USER_ASSIGNED_IDENTITY_ID string = managedIdentity.properties.clientId
output USER_ASSIGNED_IDENTITY_NAME string = managedIdentity.name

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleId in roleAssignments: {
    name: guid(managedIdentity.id, roleId)
    scope: resourceGroup()
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
      principalId: managedIdentity.properties.principalId
      principalType: 'ServicePrincipal'
    }
  }
]
