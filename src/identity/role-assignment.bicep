@description('The object ID of the principal (e.g., AKS managed identity) to assign roles to.')
param principalId string

@description('List of role definition IDs (GUIDs) to assign to the principal at resource group scope.')
var roleAssignments = [
  'b8eda974-7b85-4f76-af95-65846b26df6d'
  '69566ab7-960f-475b-8e7c-b3118f30c6bd' 
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
