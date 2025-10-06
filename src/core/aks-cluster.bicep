@description('SSH public key for secure access to AKS nodes.')
@secure()
param sshPublicKey string

@description('Admin username for AKS node access.')
param adminUsername string = 'azureuser'

@description('The Azure region where the AKS cluster will be deployed.')
param location string

@description('Tags to be applied to the AKS cluster for resource organization.')
param tags object

@description('Azure Kubernetes Service (AKS) cluster for storage integration demo.')
resource aksCluster 'Microsoft.ContainerService/managedClusters@2025-07-01' = {
  name: 'aks-demo-${uniqueString(resourceGroup().id)}-cluster'
  location: location
  identity: {
    type: 'SystemAssigned'
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
    principalId: aksCluster.identity.principalId
  }
}
