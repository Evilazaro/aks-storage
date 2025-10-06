@description('The object ID of the principal (e.g., AKS managed identity) to assign roles to.')
param principalId string

@description('List of role definition IDs (GUIDs) to assign to the principal at resource group scope.')
var roleAssignments = [
  '17d1049b-9a84-46fb-8f53-869881c3d3ab' // Storage File Data Privileged Contributor
  '69566ab7-960f-475b-8e7c-b3118f30c6bd' // Storage File Data SMB Share Contributor
]

@description('Creates role assignments for the specified principal across the listed role definitions.')
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
