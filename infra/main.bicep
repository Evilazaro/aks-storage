targetScope = 'subscription'

@description('SSH public key used for secure access to AKS nodes.')
param sshPublicKey string

@description('Admin username for AKS node access.')
param adminUsername string

@description('Azure region where resources will be deployed.')
param location string

@description('Logical environment name (e.g., dev, test, prod).')
param environmentName string

@description('Name of the resource group to create and use for deployments.')
param AZURE_RESOURCE_GROUP_NAME string

@description('Standardized resource tags applied to all deployed resources.')
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

@description('Creates the resource group that hosts AKS and storage resources for the demo.')
resource rg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: AZURE_RESOURCE_GROUP_NAME
  location: location
  tags: tags
}

@description('The name of the resource group created by this deployment.')
output AZURE_RESOURCE_GROUP_NAME string = rg.name

@description('Deploys the AKS cluster and invokes storage integration modules within the resource group.')
module aksClusterModule '../src/core/aks-cluster.bicep' = {
  name: 'deployAksCluster'
  scope: rg
  params: {
    sshPublicKey: sshPublicKey
    adminUsername: adminUsername
    location: location
    tags: tags
  }
}

@description('User Assigned Identity Name for AKS to access Azure Storage resources.')
output USER_ASSIGNED_IDENTITY_NAME string = aksClusterModule.outputs.USER_ASSIGNED_IDENTITY_NAME

@description('User assigned identity for AKS to access Azure Storage resources.')
output USER_ASSIGNED_IDENTITY_ID string = aksClusterModule.outputs.USER_ASSIGNED_IDENTITY_ID

@description('The name of the provisioned Azure Storage Account.')
output AZURE_STORAGE_ACCOUNT_NAME string = aksClusterModule.outputs.AZURE_STORAGE_ACCOUNT_NAME

@description('The name of the provisioned AKS cluster.')
output AKS_CLUSTER_NAME string = aksClusterModule.outputs.AKS_CLUSTER_NAME

@description('The OIDC issuer URL for the AKS cluster.')
output AKS_OIDC_ISSUER string = aksClusterModule.outputs.AKS_OIDC_ISSUER
