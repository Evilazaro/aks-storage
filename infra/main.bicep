targetScope = 'subscription'

param sshPublicKey string
param adminUsername string 
param location string 

resource rg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: 'rg-aks'
  location: location
}

module aksClusterModule '../src/aks-cluster.bicep' = {
  name: 'deployAksCluster'
  scope: rg
  params: {
    sshPublicKey: sshPublicKey
    adminUsername: adminUsername
    location: location
  }
}
