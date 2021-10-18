resourceGroup=demoAksClusterResourceGroup
aksCluster=demoAksCluster
totalNodes=2
location=eastus

az login

az group create --name $resourceGroup --location $location

# Create AKS cluster with worker nodes
az aks create --resource-group $resourceGroup --name $aksCluster --node-count $totalNodes --enable-addons monitoring --generate-ssh-keys

az aks show --name $aksCluster --resource-group $resourceGroup

# Connect to the cluster
az aks get-credentials --resource-group $resourceGroup --name $aksCluster --overwrite-existing

# To verify the connection to your cluster, use the kubectl get command to return a list of the cluster nodes.

kubectl get nodes

# Deploying nginx app
kubectl create -f https://raw.githubusercontent.com/kubernetes/website/master/content/en/examples/controllers/nginx-deployment.yaml

# Once the deployment is created, use kubectl to check on the deployments by running this command: 

kubectl get deployments

# delete cluster
# To avoid Azure charges, you should clean up unneeded resources.
# When the cluster is no longer needed, use the az group delete command to
# remove the resource group, container service, and all related resources. 
az group delete --name $resourceGroup --yes --no-wait


