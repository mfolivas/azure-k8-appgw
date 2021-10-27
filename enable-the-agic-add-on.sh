resourceGroup=demoAksClusterResourceGroup
aksCluster=demoAksCluster
totalNodes=2
location=eastus
appgwName=demok8sappgw
appgwPublicIpName=demoAppgwIP
k8sVnet=appgwsvnet
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
  --enable-managed-identity 
  --generate-ssh-keys

az aks show --name $aksCluster --resource-group $resourceGroup

# connecto to the cluster
az aks get-credentials --resource-group $resourceGroup --name $aksCluster --overwrite-existing


az network public-ip create \
  --name $appgwPublicIpName \
  -g $resourceGroup \
  --allocation-method Static \
  --sku Standard

az network vnet create \
  --name myVnet \
  -g $resourceGroup \
  --address-prefix 11.0.0.0/8 \
  --subnet-name mySubnet \
  --subnet-prefix 11.1.0.0/16 

az network application-gateway create \
  --name myApplicationGateway \
  -l $location \
  -g $resourceGroup \
  --sku WAF_v2 \
  --public-ip-address $appgwPublicIpName \
  --vnet-name myVnet \
  --subnet mySubnet \
  --http-settings-cookie-based-affinity Disabled \
  --frontend-port 80 \
  --http-settings-port 80 \
  --http-settings-protocol Http 


appgwId=$(az network application-gateway show --name myApplicationGateway -g $resourceGroup -o tsv --query "id")
az aks enable-addons \
  --name myCluster \
  -g $resourceGroup \
  -a ingress-appgw \
  --appgw-id $appgwId


nodeResourceGroup=$(az aks show --name myCluster -g $resourceGroup -o tsv --query "nodeResourceGroup")
aksVnetName=$(az network vnet list -g $nodeResourceGroup -o tsv --query "[0].name")

aksVnetId=$(az network vnet show --name $aksVnetName -g $nodeResourceGroup -o tsv --query "id")
az network vnet peering create --name AppGWtoAKSVnetPeering -g $resourceGroup --vnet-name myVnet --remote-vnet $aksVnetId --allow-vnet-access

appGWVnetId=$(az network vnet show --name myVnet -g $resourceGroup -o tsv --query "id")
az network vnet peering create --name AKStoAppGWVnetPeering -g $nodeResourceGroup --vnet-name $aksVnetName --remote-vnet $appGWVnetId --allow-vnet-access

az aks get-credentials --name myCluster -g myResourceGroup
