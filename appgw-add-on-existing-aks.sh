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
  --network-plugin azure \
  --enable-managed-identity 

az aks show --name $aksCluster --resource-group $resourceGroup

# connecto to the cluster
az aks get-credentials \
  --resource-group $resourceGroup \
  --name $aksCluster \
  --overwrite-existing

# add a NGINX ingress controller leveraging Helm 3 - helm version
# use the helm repo command to add the ingress-nginx repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

helm search repo ingress-nginx

# Create an ACR instance 
containerRegistryName=appgwContainerRegistry$(date '+%Y%m%d')
az acr create --resource-group $resourceGroup \
  --name $containerRegistryName --sku Basic

# Import the images used by the Helm chart into your ACR

CONTROLLER_REGISTRY=k8s.gcr.io
CONTROLLER_IMAGE=ingress-nginx/controller
CONTROLLER_TAG=v0.48.1
PATCH_REGISTRY=docker.io
PATCH_IMAGE=jettech/kube-webhook-certgen
PATCH_TAG=v1.5.1
DEFAULTBACKEND_REGISTRY=k8s.gcr.io
DEFAULTBACKEND_IMAGE=defaultbackend-amd64
DEFAULTBACKEND_TAG=1.5

az acr import --name $containerRegistryName --source $CONTROLLER_REGISTRY/$CONTROLLER_IMAGE:$CONTROLLER_TAG --image $CONTROLLER_IMAGE:$CONTROLLER_TAG
az acr import --name $containerRegistryName --source $PATCH_REGISTRY/$PATCH_IMAGE:$PATCH_TAG --image $PATCH_IMAGE:$PATCH_TAG
az acr import --name $containerRegistryName --source $DEFAULTBACKEND_REGISTRY/$DEFAULTBACKEND_IMAGE:$DEFAULTBACKEND_TAG --image $DEFAULTBACKEND_IMAGE:$DEFAULTBACKEND_TAG

acrloginServer=$(az acr show --name $containerRegistryName -o tsv --query loginServer)

# run helm charts
# Create a namespace for your ingress resources
k8namespace=appgw-sample
kubectl create namespace $k8namespace

kubectl --namespace $k8namespace get services -o wide

# helm uninstall $helmIngressRelease --namespace $k8namespace

# deploy an NGINX ingress controller

# Error: INSTALLATION FAILED: failed pre-install: timed out waiting for the condition
# helm install nginx-ingress ingress-nginx/ingress-nginx \
#     --namespace $k8namespace \
#     --set controller.replicaCount=2 \
#     --set controller.nodeSelector."kubernetes\.io/os"=linux \
#     --set controller.image.registry=$acrloginServer \
#     --set controller.image.image=$CONTROLLER_IMAGE \
#     --set controller.image.tag=$CONTROLLER_TAG \
#     --set controller.image.digest="" \
#     --set controller.admissionWebhooks.patch.nodeSelector."kubernetes\.io/os"=linux \
#     --set controller.admissionWebhooks.patch.image.registry=$acrloginServer \
#     --set controller.admissionWebhooks.patch.image.image=$PATCH_IMAGE \
#     --set controller.admissionWebhooks.patch.image.tag=$PATCH_TAG \
#     --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux \
#     --set defaultBackend.image.registry=$acrloginServer \
#     --set defaultBackend.image.image=$DEFAULTBACKEND_IMAGE \
#     --set defaultBackend.image.tag=$DEFAULTBACKEND_TAG

helm install nginx-ingress ingress-nginx/ingress-nginx \
    --namespace $k8namespace \
    --set controller.replicaCount=2 \
    --set controller.nodeSelector."kubernetes\.io/os"=linux \
    --set controller.image.digest="" \
    --set controller.admissionWebhooks.patch.nodeSelector."kubernetes\.io/os"=linux \
    --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux 

# check that the public ip of the ELB was created
# It takes a few minutes for the IP address to be assigned to the service
kubectl --namespace $k8namespace get services -o wide -w nginx-ingress-ingress-nginx-controller

# the result should be something like this:
# NAME                                     TYPE           CLUSTER-IP    EXTERNAL-IP     PORT(S)                      AGE   SELECTOR
# nginx-ingress-ingress-nginx-controller   LoadBalancer   10.0.108.231   20.85.201.27   80:32766/TCP,443:30609/TCP   27s   app.kubernetes.io/component=controller,app.kubernetes.io/instance=nginx-ingress,app.kubernetes.io/name=ingress-nginx

# run some demo application
kubectl apply -f aks-helloworld.yaml --namespace $k8namespace
kubectl apply -f ingress-demo.yaml --namespace $k8namespace

# Create an ingress route
kubectl apply -f hello-world-ingress.yaml
# Traffic to the address http://<EXTERNAL_IP>/ is routed to the service named aks-helloworld.
# Traffic to the address http://<EXTERNAL_IP>/hello-world-two is routed to the ingress-demo service

# Now we will create a application gateway
# To route traffic to each application, create a Kubernetes ingress resource.
# The ingress resource configures the rules that route traffic to one of the two applications.


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
  --name $appgwName --location $location \
  --resource-group $resourceGroup \
  --sku WAF_v2 \
  --public-ip-address $appgwPublicIpName \
  --vnet-name $vnetName \
  --subnet $subnetName


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
kubectl apply -f aspnetapp.yaml 

# verify that your application is reachable
# Get the IP address of the Ingress.

kubectl get ingress --namespace $k8namespace
# NAME                  CLASS    HOSTS   ADDRESS         PORTS   AGE
# aspnetapp             <none>   *       52.152.173.37   80      58s
# hello-world-ingress   <none>   *       20.85.201.27    80      21m


# create front door
# need to have the front door extension installed before
az extension add --name front-door

frondoorname=appgwdemofrontdoor
az network front-door check-name-availability --name $frondoorname --resource-type Microsoft.Network/frontDoors

az network front-door create \
  --resource-group $nodeResourceGroup \
  --name $frondoorname \
  --backend-address 52.152.173.37

# create a WAF policy
wafpolicyname=IPAllowPolicyExampleCLI
az network front-door waf-policy create \
  --name $wafpolicyname \
  --resource-group $nodeResourceGroup 

# create an IP allow rule for the policy created from the previous step.
# --defer is required because a rule must have a match condition to be added in the next step
az network front-door waf-policy rule create \
  --action Block \
  --name IPAllowListRule \
  --policy-name $wafpolicyname \
  --priority 1 \
  --resource-group $nodeResourceGroup  \
  --rule-type MatchRule \
  --defer

# Next, add match condition to the rule:
az network front-door waf-policy rule match-condition add \
  --name IPAllowListRule \
  --operator IPMatch \
  --policy-name $wafpolicyname \
  --resource-group $nodeResourceGroup \
  --values "196.16.223.27" "103.228.197.79" \
  --match-variable RemoteAddr \
  --negate true

# find the ids of the WAF policies
az network front-door  waf-policy show --resource-group $nodeResourceGroup --name $wafpolicyname

# clean resources
helm uninstall $helmIngressRelease --namespace $k8namespace
az group delete --name $resourceGroup --yes --no-wait
