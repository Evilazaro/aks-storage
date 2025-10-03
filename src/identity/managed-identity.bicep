param location string
param tags object

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'aks-demo-${uniqueString(resourceGroup().id)}-identity'
  location: location
  tags: tags
}

output USER_ASSIGNED_IDENTITY_ID string = managedIdentity.properties.clientId
output USER_ASSIGNED_IDENTITY_NAME string = managedIdentity.name

module roleAssignment 'role-assignment.bicep' = {
  name: 'roleAssignmentDeployment'
  scope: resourceGroup()
  params: {
    principalId: managedIdentity.properties.principalId
  }
  dependsOn: [
    managedIdentity
  ]
}

var rgName = 'MC_${resourceGroup().name}_aks-demo-${uniqueString(resourceGroup().id)}-cluster_${location}'

module roleAssignment2 'role-assignment.bicep' = {
  name: 'roleAssignmentDeployment2'
  scope: resourceGroup(rgName)
  params: {
    principalId: managedIdentity.properties.principalId
  }
  dependsOn: [
    managedIdentity
  ]
}
