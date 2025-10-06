@description('The Azure region where the storage account will be deployed.')
param location string

@description('Tags to be applied to the storage account for resource organization.')
param tags object

@description('Azure Storage Account used for AKS file share integration.')
resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: 'contoso${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
  }
}

@description('The name of the provisioned Azure Storage Account.')
output AZURE_STORAGE_ACCOUNT_NAME string = storageAccount.name

@description('File service resource for the storage account, enabling file shares and retention policy.')
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2025-01-01' = {
  name: 'default'
  parent: storageAccount
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

@description('Azure File Share used by AKS workloads for persistent storage.')
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2025-01-01' = {
  name: 'aksfileshare'
  parent: fileService
}
