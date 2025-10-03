targetScope = 'subscription'

param sshPublicKey string
param adminUsername string
param location string
param environmentName string
param AZURE_RESOURCE_GROUP_NAME string

param tags object = {
  Environment: environmentName
  Project: 'aks-storage'
  Owner: 'Platform Team'
  CostCenter: 'IT-Infrastructure'
  Application: 'AKS-Storage-Solution'
  BusinessUnit: 'Technology'
  Criticality: 'High'
  DataClassification: 'Internal'
  CreatedBy: 'Bicep Template'
  CreatedDate: utcNow('yyyy-MM-dd')
}

resource rg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: AZURE_RESOURCE_GROUP_NAME
  location: location
  tags: tags
}

output AZURE_RESOURCE_GROUP_NAME string = rg.name

module identity '../src/identity/managed-identity.bicep' = {
  scope: rg
  name: 'deployManagedIdentity'
  params: {
    location: location
    tags: tags
  }
}

output USER_ASSIGNED_IDENTITY_ID string = identity.outputs.USER_ASSIGNED_IDENTITY_ID
output USER_ASSIGNED_IDENTITY_NAME string = identity.outputs.USER_ASSIGNED_IDENTITY_NAME

module aksClusterModule '../src/aks-cluster.bicep' = {
  name: 'deployAksCluster'
  scope: rg
  params: {
    sshPublicKey: sshPublicKey
    adminUsername: adminUsername
    location: location
    tags: tags
  }
}

output AKS_CLUSTER_NAME string = aksClusterModule.outputs.AKS_CLUSTER_NAME
output AKS_OIDC_ISSUER string = aksClusterModule.outputs.AKS_OIDC_ISSUER
