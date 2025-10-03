@secure()
param sshPublicKey string
param adminUsername string = 'azureuser'
param location string 

resource aksCluster 'Microsoft.ContainerService/managedClusters@2025-07-01' = {
  name: 'aks${uniqueString(resourceGroup().id)}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  kind: 'ManagedCluster'
  sku: {
    name: 'Automatic'
    tier: 'Premium'
  }
  properties: {
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
        count: 1
        vmSize: 'Standard_DS2_v2'
        osDiskSizeGB: 30
        osType: 'Linux'
        mode: 'System'
        type: 'VirtualMachineScaleSets'
      }
      {
        name: 'workloadpool'
        count: 1
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
