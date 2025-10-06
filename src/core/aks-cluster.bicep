@description('SSH public key for secure access to AKS nodes.')
@secure()
param sshPublicKey string

@description('Admin username for AKS node access.')
param adminUsername string = 'azureuser'

@description('The Azure region where the AKS cluster will be deployed.')
param location string

@description('Tags to be applied to the AKS cluster for resource organization.')
param tags object

@description('User assigned identity for AKS to access Azure Storage resources.')
resource aksUserAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'aksDemoUserIdentity${uniqueString(resourceGroup().id)}'
  location: location
}

@description('User Assigned Identity Name for AKS to access Azure Storage resources.')
output USER_ASSIGNED_IDENTITY_NAME string = aksUserAssignedIdentity.name

@description('User assigned identity for AKS to access Azure Storage resources.')
output USER_ASSIGNED_IDENTITY_ID string = aksUserAssignedIdentity.properties.clientId

@description('Azure Kubernetes Service (AKS) cluster for storage integration demo.')
resource aksCluster 'Microsoft.ContainerService/managedClusters@2025-07-01' = {
  name: 'aks-demo-${uniqueString(resourceGroup().id)}-cluster'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${aksUserAssignedIdentity.id}': {}
    }
  }
  kind: 'ManagedCluster'
  sku: {
    name: 'Base'
    tier: 'Premium'
  }
  tags: tags
  properties: {
    dnsPrefix: 'aks-demo-${uniqueString(resourceGroup().id)}-cluster'
    enableRBAC: true
    oidcIssuerProfile: {
      enabled: true
    }
    publicNetworkAccess: 'Enabled'
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: 3
        vmSize: 'Standard_DS2_v2'
        osDiskSizeGB: 30
        osType: 'Linux'
        mode: 'System'
        type: 'VirtualMachineScaleSets'
      }
      {
        name: 'workloadpool'
        count: 3
        vmSize: 'Standard_DS2_v2'
        osDiskSizeGB: 30
        osType: 'Linux'
        mode: 'User'
        type: 'VirtualMachineScaleSets'
      }
    ]
    linuxProfile: {
      adminUsername: adminUsername
      ssh: {
        publicKeys: [
          {
            keyData: sshPublicKey
          }
        ]
      }
    }
  }
}

@description('The name of the provisioned AKS cluster.')
output AKS_CLUSTER_NAME string = aksCluster.name

@description('The OIDC issuer URL for the AKS cluster.')
output AKS_OIDC_ISSUER string = aksCluster.properties.oidcIssuerProfile.issuerURL

@description('The client ID of the AKS managed identity.')
output AKS_MANAGED_IDENTITY_CLIENT_ID string = aksCluster.identity.principalId

@description('The principal ID of the AKS managed identity.')
output AKS_MANAGED_IDENTITY_PRINCIPAL_ID string = aksCluster.identity.principalId

@description('Deploys the storage account used for AKS file share integration.')
module storageAccount 'storage-account.bicep' = {
  params: {
    location: location
    tags: tags
  }
}

@description('The name of the provisioned Azure Storage Account.')
output AZURE_STORAGE_ACCOUNT_NAME string = storageAccount.outputs.AZURE_STORAGE_ACCOUNT_NAME

@description('Assigns the required role to the AKS managed identity for storage access.')
module roleAssignment '../identity/role-assignment.bicep' = {
  name: 'aksroleAssignmentDeployment'
  scope: resourceGroup()
  params: {
    principalId: aksUserAssignedIdentity.properties.principalId
  }
}
