
# Terraform Setup for AWS and Kubernetes
This repository contains Terraform configurations to provision AWS infrastructure including VPC, subnets, NAT gateway, EKS cluster, and node group. It also includes deploying Kubernetes resources using kubectl via Terraform's local-exec provisioner.

Initialize Terraform
```sh
terraform init
```

Apply Terraform Configuration

```sh 
terraform apply 
```

this will generate a kubeconfig.yaml to access the kuberentes cluster to deploy the resources.


nginx-deployment.yaml ---> this manifest will create the Deployment (nginx-deployment) with 3 replicas, each running an NGINX container. The initContainer will execute once per Pod, setting up the index.html file in the workdir volume with pod metadata.

nginx-service.yaml  ---> this manifest exposes the your deployment  to the internet or a cloud provider's load balancer.

``` sh 
kubectl get deployments --kubeconfig=./kubeconfig.yaml
kubectl get service --kubeconfig=./kubeconfig.yaml
```

use the above command to verify the deployments are good

use this ```http://a866dfe8d5f494caa8fe6e538f2225ed-743414502.us-west-2.elb.amazonaws.com/``` to access the service.



# Improvements
I would have looked into CICD options 

Created a DNS so I could have made a ACM to host this service on port 443.

I could have made the terraform better.
