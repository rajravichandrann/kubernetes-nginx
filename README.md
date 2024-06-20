
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

this will generate a kubeconfig.yaml to access the kuberentes cluster to deploy the resources
