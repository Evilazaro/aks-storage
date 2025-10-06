#!/bin/bash

location='eastus2'
storageAccountName='contosoaksstorage'
nodeResourceGroupName='contoso-aks-uat-eastus2-RG'
clusterName='aks-demo-khfkx467bemki-cluster'

create_azure_storage_secret() {
  local resource_group="$1"
  local cluster_name="$2"
  local storage_account="$3"
  local secret_name="$4"
  local namespace="$5"
  
  echo "Getting node resource group for cluster: $cluster_name"
  local node_rg=$(az aks show --resource-group "$resource_group" --name "$cluster_name" --query nodeResourceGroup -o tsv)
  echo "Node Resource Group Name is: $node_rg"
  
  echo "Getting storage account key for: $storage_account"
  local storage_key=$(az storage account keys list --resource-group "$node_rg" --account-name "$storage_account" --query "[0].value" -o tsv)
  echo "Storage key retrieved successfully"
  
  echo "Creating Kubernetes secret: $secret_name"
  kubectl create secret generic "$secret_name" \
    --from-literal=azurestorageaccountname="$storage_account" \
    --from-literal=azurestorageaccountkey="$storage_key" \
    --namespace="$namespace"
  
  echo "Displaying secret YAML:"
  kubectl get secret "$secret_name" -n "$namespace" -o yaml
  
  echo "Decoding secret values:"
  kubectl get secret "$secret_name" -n "$namespace" -o json \
    | jq -r '.data | to_entries[] | "\(.key)=\(.value)"' \
    | while IFS='=' read -r key b64; do
      echo "== $key =="
      echo "$b64" | base64 --decode
      echo
    done
}

# Call the function with default values
create_azure_storage_secret $nodeResourceGroupName $clusterName $storageAccountName azure-secret default
