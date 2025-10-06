param location string
param tags object

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: 'contoso${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  sku: {
    name: 'Premium_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
  }
}

output AZURE_STORAGE_ACCOUNT_NAME string = storageAccount.name

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

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2025-01-01' = {
  name: 'aksfileshare'
  parent: fileService
}
