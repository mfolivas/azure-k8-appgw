# Create a resource group.
# Create a new AKS cluster with the AGIC add-on enabled.
# Deploy a sample application by using AGIC for ingress on the AKS cluster.
# Check that the application is reachable through Application Gateway.
 

resourceGroup=demoAksClusterResourceGroup
aksCluster=demoAksCluster
totalNodes=2
location=eastus
appgwName=demok8sappgw

az login

# In Azure, you allocate related resources to a resource group
az group create --name $resourceGroup --location $location

# Deploy an AKS cluster with the add-on enabled
# You'll now deploy a new AKS cluster with the AGIC add-on enabled. 
# If you don't provide an existing Application Gateway instance to use in 
# this process, we'll automatically create and set up a new Application Gateway
# instance to serve traffic to the AKS cluster.
# with the AGIC add-on enabled will create a Standard_v2 SKU Application Gateway instance

az aks create --name $aksCluster \
  --resource-group $resourceGroup \
  --network-plugin azure \
  --enable-managed-identity \
  --enable-addons ingress-appgw,monitoring \
  --appgw-name $appgwName \
  --appgw-subnet-cidr 10.2.0.0/16 \
  --generate-ssh-keys

# get credentials to the AKS cluster
az aks get-credentials --name $aksCluster --resource-group $resourceGroup

# set up a sample application that uses AGIC for ingress to the cluster.

kubectl apply \
  -f https://raw.githubusercontent.com/Azure/application-gateway-kubernetes-ingress/master/docs/examples/aspnetapp.yaml 

# Check that the sample application that you created is running by either:
# Visiting the IP address of the Application Gateway instance that you got from running the preceding command.
# Using curl.

kubectl get ingress


# when you no longer need them, remove the resource group
az group delete --name $resourceGroup --yes --no-wait
