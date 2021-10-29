# https://docs.microsoft.com/en-us/azure/application-gateway/tutorial-ingress-controller-add-on-existing
# Create a resource group
# Create a new AKS cluster
# Create a new Application Gateway
# Enable the AGIC add-on in the existing AKS cluster through Azure CLI
# Enable the AGIC add-on in the existing AKS cluster through Portal
# Peer the Application Gateway virtual network with the AKS cluster virtual network
# Deploy a sample application using AGIC for Ingress on the AKS cluster
# Check that the application is reachable through Application Gateway


resourceGroup=demoAksClusterResourceGroup
aksCluster=demoAksCluster
totalNodes=2
location=eastus
appgwName=demok8sappgw
appgwPublicIpName=demoAppgwIP
vnetName=appgwsvnet
subnetName=appgwsubnet

az login

# allocate related resources to a resource group
az group create --name $resourceGroup --location $location

# deploy a new AKS cluster
az aks create --name $aksCluster \
  --resource-group $resourceGroup \
  --node-count $totalNodes \
  --enable-addons monitoring \
  --network-plugin azure \
  --enable-managed-identity \
  --generate-ssh-keys

az aks show --name $aksCluster --resource-group $resourceGroup

# connecto to the cluster
az aks get-credentials --resource-group $resourceGroup --name $aksCluster --overwrite-existing

# When using an AKS cluster and Application Gateway in separate virtual networks,
# the address spaces of the two virtual networks must not overlap. 
# The default address space that an AKS cluster deploys in is 10.0.0.0/8, 
# so we set the Application Gateway virtual network address prefix to 11.0.0.0/8.

az network public-ip create \
  --name $appgwPublicIpName \
  --resource-group $resourceGroup \
  --allocation-method Static \
  --sku Standard

az network vnet create \
  --name $vnetName \
  --resource-group $resourceGroup \
  --address-prefix 11.0.0.0/8 \
  --subnet-name $subnetName \
  --subnet-prefix 11.1.0.0/16 

az network application-gateway create \
  --name $appgwName \
  --location $location \
  --resource-group $resourceGroup \
  --sku WAF_v2 \
  --public-ip-address $appgwPublicIpName \
  --vnet-name $vnetName \
  --subnet $subnetName \
  --http-settings-cookie-based-affinity Disabled \
  --frontend-port 80 \
  --http-settings-port 80 \
  --http-settings-protocol Http 


# Enable the AGIC add-on in existing AKS cluster
appgwId=$(az network application-gateway show --name $appgwName --resource-group $resourceGroup -o tsv --query "id")
az aks enable-addons \
  --name $aksCluster \
  --resource-group $resourceGroup \
  -a ingress-appgw \
  --appgw-id $appgwId

# Peer the two virtual networks together
# Peering the two virtual networks requires running the Azure CLI command two separate times
# to ensure that the connection is bi-directional. 
# The first command will create a peering connection from the Application Gateway 
# virtual network to the AKS virtual network
# the second command will create a peering connection in the other direction.
nodeResourceGroup=$(az aks show --name $aksCluster --resource-group $resourceGroup -o tsv --query "nodeResourceGroup")
aksVnetName=$(az network vnet list --resource-group $nodeResourceGroup -o tsv --query "[0].name")

aksVnetId=$(az network vnet show --name $aksVnetName --resource-group $nodeResourceGroup -o tsv --query "id")
az network vnet peering create \
  --name AppGWtoAKSVnetPeering \
  --resource-group $resourceGroup \
  --vnet-name $vnetName \
  --remote-vnet $aksVnetId \
  --allow-vnet-access

appGWVnetId=$(az network vnet show --name $vnetName --resource-group $resourceGroup -o tsv --query "id")
az network vnet peering create \
  --name AKStoAppGWVnetPeering \
  --resource-group $nodeResourceGroup \
  --vnet-name $aksVnetName \
  --remote-vnet $appGWVnetId \
  --allow-vnet-access

# Deploy a sample application using AGIC
az aks get-credentials --name $aksCluster --resource-group $resourceGroup

# set up a sample application that uses AGIC for Ingress to the cluster. 
# AGIC will update the Application Gateway you set up earlier with 
# corresponding routing rules to the new sample application you deployed.
kubectl apply -f https://raw.githubusercontent.com/Azure/application-gateway-kubernetes-ingress/master/docs/examples/aspnetapp.yaml 

# verify that your application is reachable
# Get the IP address of the Ingress.

kubectl get ingress

# clean resources
az group delete --name $resourceGroup --yes --no-wait
