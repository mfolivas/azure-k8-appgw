#!/bin/bash

### Setup AppGateway V2 w/ multi namespace support

resourceGroup=demoAksClusterResourceGroup
k8sVnet=demok8sVnet
appgwName=demok8sappgw
appgwPublicIpName=demoAppgwIP
location=eastus

# create dedicated appgateway vnet subnet
# az network vnet subnet create \
#   --name appgwsubnet \
#   --location $location \
#   --resource-group $resourceGroup \
#   --vnet-name $k8sVnet \
#   --address-prefix 10.242.0.0/16

az network vnet create \
    --resource-group $resourceGroup \
    --location $location \
    --name appgwsubnet \
    --address-prefix 10.242.0.0/16 \
    --subnet-name $k8sVnet

# create public ip for app gateway
az network public-ip create \
  --resource-group $resourceGroup \
  --name $appgwPublicIpName \
  --allocation-method Static \
  --sku Standard

# Create the application gateway
az network application-gateway create \
  --name $appgwName \
  --location $location \
  --resource-group $resourceGroup \
  --vnet-name $k8sVnet \
  --subnet appgwsubnet \
  --capacity 2 \
  --sku WAF_v2 \
  --http-settings-cookie-based-affinity Disabled \
  --frontend-port 80 \
  --http-settings-port 80 \
  --http-settings-protocol Http \
  --public-ip-address $appgwPublicIpName

# enable firewall mode detection
# need to update to network application-gateway waf-policy in future
# az network application-gateway waf-config set \
#     -g $resourceGroup \
#     --gateway-name $appgwName \
#     --enabled true \
#     --firewall-mode Detection \
#     --rule-set-version 3.0

# manage application gateway web application firewall policies
az network application-gateway waf-policy create \
    --name demoWafPolicy \
    --resource-group $resourceGroup \
    --location $location


# Create http probe
az network application-gateway probe create \
    -g $resourceGroup \
    --gateway-name $appgwName \
    -n defaultprobe-Http \
    --protocol http \
    --host 127.0.0.1 \
    --timeout 30 \
    --path /

# Create https probe
az network application-gateway probe create \
    -g $resourceGroup \
    --gateway-name $appgwName \
    -n defaultprobe-Https \
    --protocol https \
    --host 127.0.0.1 \
    --timeout 30 \
    --path /

# Link http probe to application gateway
az network application-gateway http-settings update \
    -g $resourceGroup \
    --gateway-name $appgwName \
    -n appGatewayBackendHttpSettings \
    --probe defaultprobe-Http

# Install AAD Pod Identity to your cluster; installs Kubernetes CRDs: AzureIdentity, AzureAssignedIdentity, AzureIdentityBinding
## Be sure to switch to K8s cluster
kubectl create -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment-rbac.yaml

### setup aad pod identity w/ managed identity
az identity create \
    -g $resourceGroup \
    -n aadappGW
    
# capture clientId in variable
clientId=$(az identity show \
    -g $resourceGroup \
    -n aadappGW \
    --query 'clientId' \
    -o tsv)

# capture appgwId in variable
appgwId=$(az network application-gateway list --resource-group $resourceGroup --query '[].id' -o tsv)

# capture appgw resource group id in variable
appgwrgId=$(az group show -g $resourceGroup --query 'id' -o tsv)

# Give identity Contributor access to your Application Gateway
az role assignment create \
    --role Contributor \
    --assignee $clientId \
    --scope $appgwId

# Give identity Reader access to the Application Gateway resource group
az role assignment create \
    --role Reader \
    --assignee $clientId \
    --scope $appgwrgId

# capture necessary variables for helm config
applicationGatewayName=$(az network application-gateway list --resource-group $resourceGroup --query '[].name' -o tsv)
subscriptionId=$(az account show --query 'id' -o tsv)
identityClientId=$(az identity show -g $resourceGroup -n aadappGW --query 'clientId' -o tsv)
identityResourceId=$(az identity show -g $resourceGroup -n aadappGW --query 'id' -o tsv)

# download helm-config
wget https://raw.githubusercontent.com/Azure/application-gateway-kubernetes-ingress/master/docs/examples/sample-helm-config.yaml -O helm-config.yaml

# use said to replace <> field values with captured data
sed -i "" "s|<subscriptionId>|${subscriptionId}|g" helm-config.yaml
sed -i "" "s|<resourceGroupName>|${resourceGroup}|g" helm-config.yaml
sed -i "" "s|<applicationGatewayName>|${applicationGatewayName}|g" helm-config.yaml
sed -i "" "s|<identityResourceId>|${identityResourceId}|g" helm-config.yaml
sed -i "" "s|<identityClientId>|${identityClientId}|g" helm-config.yaml

### Optional tip - open helm-config.yaml and edit line 47 if using an RBAC enabled cluster

# add app gateway ingress helm chart repo and update repo
helm repo add application-gateway-kubernetes-ingress https://appgwingress.blob.core.windows.net/ingress-azure-helm-package/
helm repo update

# install appgw ingress using helm chart and helm-config.yaml
helm upgrade --install appgw-ingress-azure -f helm-config.yaml application-gateway-kubernetes-ingress/ingress-azure

# test deployment

wget https://raw.githubusercontent.com/jldeen/helm3-demo/master/jenkins-values-demo.yaml -O jenkins-values.yaml

# deploy to 2 different namespaces with 2 different hostnames
# hostname appgateway.ap.az.jessicadeen.com
helm upgrade jenkins --install --namespace default2 -f ./jenkins-values.yaml stable/jenkins

# hostname default.ap.az.jessicadeen.com
helm upgrade jenkins --install --namespace default -f ./jenkins-values.yaml stable/jenkins
