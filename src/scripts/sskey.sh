# !/bin/bash

AZURE_ENV_NAME=$1
AZURE_LOCATION=$2

az group create --name "aks-sskey-rg" --location "$AZURE_LOCATION"

# Create an SSH key pair using Azure CLI
az sshkey create --name "mySSHKey" --resource-group "aks-sskey-rg" --location "$AZURE_LOCATION"

# Create an SSH key pair using ssh-keygen
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""

# Export the SSH public key to an environment variable
export SSH_PUBLIC_KEY=$(az sshkey show --name "mySSHKey" --resource-group "aks-sskey-rg" --query publicKey -o tsv)

# Echo the SSH key
echo "SSH Public Key: $SSH_PUBLIC_KEY"

# export to .env file
echo "SSH_PUBLIC_KEY=\"$SSH_PUBLIC_KEY\"" >> ./.azure/$AZURE_ENV_NAME/.env