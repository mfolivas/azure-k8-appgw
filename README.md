# azure-k8-appgw
Implementing the Application Gateway to an existing AKS

The Application Gateway Ingress Controller allows Azure Application Gateway to be used as the ingress for an Azure Kubernetes Service aka AKS cluster.

As shown in the figure below, the ingress controller runs as a pod within the AKS cluster. It consumes Kubernetes Ingress Resources and converts them to an Azure Application Gateway configuration which allows the gateway to load-balance traffic to Kubernetes pods.

Much like the most popular Kubernetes Ingress Controllers, the Application Gateway Ingress Controller provides several features, leveraging Azure’s native Application Gateway L7 load balancer. To name a few:

1. URL routing
2. Cookie based affinity
3. SSL termination
4. End-to-End SSL
5. Support for public, private and hybrid websites
6. Integrated WAF

![architecture](architecture.png)


The architecture of the Application Gateway Ingress Controller differs from that of a traditional in-cluster L7 load balancer. The architectural differences are shown in this diagram:

![agw](agw2.jpeg)
- An in-cluster load balancer performs all data path operations leveraging the Kubernetes cluster’s compute resources. It competes for resources with the business apps it is fronting. In-cluster ingress controllers create Kubernetes Service Resources and leverage kubenet for network traffic. In comparison to Ingress Controller, traffic flows through an extra hop.

- Application Gateway Ingress Controller leverages the AKS' advanced networking, which allocates an IP address for each pod from the subnet shared with Application Gateway. Application Gateway Ingress Controller has direct access to all Kubernetes pods. This eliminates the need for data to pass through kubenet.