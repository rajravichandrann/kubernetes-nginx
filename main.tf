provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {}

# VPC
resource "aws_vpc" "eks_vpc" {
  cidr_block = var.vpc_cidr_block
}

# Public Subnets
resource "aws_subnet" "eks_public_subnet" {
  count                   = 3
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 8, count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
}

# Private Subnets
resource "aws_subnet" "eks_private_subnet" {
  count                   = 3
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 8, count.index + 3)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.eks_vpc.id
}

# Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.eks_vpc.id
}

# Route for Internet Access
resource "aws_route" "igw_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Associate Public Subnets with Route Table
resource "aws_route_table_association" "public_rt_assoc" {
  count          = 3
  subnet_id      = element(aws_subnet.eks_public_subnet.*.id, count.index)
  route_table_id = aws_route_table.public_rt.id
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {}

# NAT Gateway
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = element(aws_subnet.eks_public_subnet.*.id, 0)
}

# Private Route Table
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.eks_vpc.id
}

# Route for Internet Access through NAT
resource "aws_route" "nat_route" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id
}

# Associate Private Subnets with Route Table
resource "aws_route_table_association" "private_rt_assoc" {
  count          = 3
  subnet_id      = element(aws_subnet.eks_private_subnet.*.id, count.index)
  route_table_id = aws_route_table.private_rt.id
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_cluster_role" {
  name = "seal-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

# Attach EKS Policy to EKS Cluster Role
resource "aws_iam_role_policy_attachment" "eks_cluster_role_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cluster_role_AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# EKS Cluster
resource "aws_eks_cluster" "my_cluster" {
  name     = "seal-eks-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = concat(aws_subnet.eks_public_subnet[*].id, aws_subnet.eks_private_subnet[*].id)
  }
}

# EKS Node Group IAM Role
resource "aws_iam_role" "eks_worker_node_role" {
  name               = "eks_worker_node_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_role_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_worker_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_role_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_worker_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_role_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_worker_node_role.name
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# EKS Node Group
resource "aws_eks_node_group" "node_group" {
  cluster_name    = aws_eks_cluster.my_cluster.name
  node_group_name = "seal-node-group"
  node_role_arn   = aws_iam_role.eks_worker_node_role.arn
  subnet_ids      = aws_subnet.eks_private_subnet[*].id

  scaling_config {
    desired_size = 3
    max_size     = 4
    min_size     = 1
  }

  instance_types = ["t3.small"]

#   remote_access {
#     ec2_ssh_key = var.ec2_key_pair_name
#   }

  ami_type = "AL2_x86_64"

  tags = {
    Name = "seal-node-group"
  }
}


# Generate kubeconfig file
resource "local_file" "kubeconfig" {
  content  = templatefile("${path.module}/templates/kubeconfig.yaml.tpl", {
    cluster_name    = aws_eks_cluster.my_cluster.name,
    endpoint        = aws_eks_cluster.my_cluster.endpoint,
    cert_data       = aws_eks_cluster.my_cluster.certificate_authority.0.data,
    token           = data.aws_eks_cluster_auth.cluster_auth.token,
  })
  filename = "${path.module}/kubeconfig.yaml"
}

# Apply Kubernetes resources using kubectl
resource "null_resource" "apply_manifests" {
  depends_on = [aws_eks_cluster.my_cluster, local_file.kubeconfig]

  provisioner "local-exec" {
    command = <<EOT
    kubectl apply -f ${path.module}/nginx-deployment.yaml --kubeconfig=${path.module}/kubeconfig.yaml
    kubectl apply -f ${path.module}/nginx-service.yaml --kubeconfig=${path.module}/kubeconfig.yaml
    EOT
  }
}

# Output kubeconfig content
data "aws_eks_cluster_auth" "cluster_auth" {
  name = aws_eks_cluster.my_cluster.name
}

output "kubeconfig" {
  value = data.aws_eks_cluster_auth.cluster_auth.id
}

output "kubeconfig_token" {
  value = data.aws_eks_cluster_auth.cluster_auth.token
  sensitive = true
}

# Output cluster endpoint and certificate authority data
output "cluster_endpoint" {
  value = aws_eks_cluster.my_cluster.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.my_cluster.certificate_authority.0.data
}
