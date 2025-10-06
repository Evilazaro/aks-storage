@secure()
param sshPublicKey string
param adminUsername string = 'azureuser'
param location string
param tags object

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

output AKS_CLUSTER_NAME string = aksCluster.name
output AKS_OIDC_ISSUER string = aksCluster.properties.oidcIssuerProfile.issuerURL

module storageAccount 'storage-account.bicep' = {
  params: {
    location: location
    tags: tags
  }
  dependsOn: [
    aksCluster
  ]
}

output AZURE_STORAGE_ACCOUNT_NAME string = storageAccount.outputs.AZURE_STORAGE_ACCOUNT_NAME

module roleAssignment '../identity/role-assignment.bicep' = {
  name: 'aksroleAssignmentDeployment'
  scope: resourceGroup()
  params: {
    principalId: aksCluster.identity.principalId
  }
  dependsOn: [
    aksCluster
  ]
}
