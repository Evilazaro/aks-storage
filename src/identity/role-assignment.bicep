param principalId string
var roleAssignments = [
  '17d1049b-9a84-46fb-8f53-869881c3d3ab'
  '69566ab7-960f-475b-8e7c-b3118f30c6bd'
]

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleId in roleAssignments: {
    name: guid(resourceGroup().id, resourceGroup().name, principalId, roleId)
    scope: resourceGroup()
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
      principalId: principalId
      principalType: 'ServicePrincipal'
    }
  }
]
