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
subnetName=appgwsubnet

az login

# allocate related resources to a resource group
az group create --name $resourceGroup --location $location

# deploy a new AKS cluster
az aks create --name $aksCluster \
  --resource-group $resourceGroup \
  --node-count $totalNodes \
  --enable-addons monitoring \
  --generate-ssh-keys

az aks show --name $aksCluster --resource-group $resourceGroup

# Connect to the cluster
az aks get-credentials --resource-group $resourceGroup --name $aksCluster --overwrite-existing

# deploy a new Application Gateway
# create public ip for app gateway
az network public-ip create \
  --resource-group $resourceGroup \
  --name $appgwPublicIpName \
  --allocation-method Static \
  --sku Standard

# create a new virtual network
az network vnet create \
  --resource-group $resourceGroup \
  --location $location \
  --name $subnetName \
  --address-prefix 10.242.0.0/16 \
  --subnet-name $k8sVnet

# create the application gateway
az network application-gateway create \
  --name $appgwName \
  --location $location \
  --resource-group $resourceGroup \
  --vnet-name $k8sVnet \
  --subnet $subnetName \
  --capacity 2 \
  --sku WAF_v2 \
  --http-settings-cookie-based-affinity Disabled \
  --frontend-port 80 \
  --http-settings-port 80 \
  --http-settings-protocol Http \
  --public-ip-address $appgwPublicIpName

# enable the AGIC
# enable the AGIC add-on in the AKS cluster and specify the AGIC add-on to use
# the existing applicagion gateway you created
appgwId=$(az network application-gateway show --name $appgwName -g $resourceGroup -o tsv --query "id") 
az aks enable-addons -n $aksCluster -g $resourceGroup -a ingress-appgw --appgw-id $appgwId

# peer the two virtual networks together
# since we deployed the AKS cluster in its own virtual network and the
# Application Gateway in another virtual network, we'll need to peer the two
# virtual networks together in order for traffic to flow from the 
# Application Gateway to the pods in the cluster
nodeResourceGroup=$(az aks show -n $aksCluster -g $resourceGroup -o tsv --query "nodeResourceGroup")
aksVnetName=$(az network vnet list -g $nodeResourceGroup -o tsv --query "[0].name")

aksVnetId=$(az network vnet show -n $aksVnetName -g $nodeResourceGroup -o tsv --query "id")
# create a peering connection from the Application Gateway virtual network to the AKS virtual network
az network vnet peering create --name appGWtoAKSVnetPeering \
  -g $nodeResourceGroup \
  --vnet-name $aksVnetName \
  --remote-vnet $aksVnetId \
  --allow-vnet-access

appGWVnetId=$(az network vnet show -n myVnet -g myResourceGroup -o tsv --query "id")
# create a peering connection in the other direction
az network vnet peering create --name AKStoAppGWVnetPeering -g $nodeResourceGroup --vnet-name $aksVnetName --remote-vnet $appGWVnetId --allow-vnet-access

az group delete --name $resourceGroup --yes --no-wait