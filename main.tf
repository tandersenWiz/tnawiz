resource "aws_vpc" "my_vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "my_vpc"
  }
}

resource "aws_subnet" "my_subnet_1" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "my_subnet_1"
  }
}

resource "aws_subnet" "my_subnet_2" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "my_subnet_2"
  }
}

resource "aws_internet_gateway" "my_igw" {      
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "my_igw"
  }
}

resource "aws_route_table" "my_rt" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = "my_public_rt"
  }
}

resource "aws_route_table_association" "my_subnet_1_association" {
  subnet_id      = aws_subnet.my_subnet_1.id
  route_table_id = aws_route_table.my_rt.id
}

resource "aws_route_table_association" "tech_task_subnet_2_association" {
  subnet_id      = aws_subnet.my_subnet_2.id
  route_table_id = aws_route_table.my_rt.id
}

resource "aws_eks_cluster" "my_eks_cluster" {
  name     = "my_eks_cluster"
  role_arn = aws_iam_role.my_eks_cluster_role.arn
  access_config {
  authentication_mode = "API_AND_CONFIG_MAP"
  bootstrap_cluster_creator_admin_permissions = true

  }
  vpc_config {
    subnet_ids = [aws_subnet.my_subnet_1.id, aws_subnet.my_subnet_2.id]
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Cluster handling.
  # Otherwise, EKS will not be able to properly delete EKS managed EC2 infrastructure such as Security Groups.
  
  depends_on = [
    aws_iam_policy_attachment.my_eks_role_attachment
  ]
}

resource "aws_eks_node_group" "my_node_group" {
  cluster_name    = aws_eks_cluster.my_eks_cluster.name
  node_group_name = "my_node_group"
  node_role_arn   = aws_iam_role.my_nodegroup_role.arn
  subnet_ids      = [aws_subnet.my_subnet_1.id, aws_subnet.my_subnet_2.id]

  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  ami_type        = "AL2_x86_64"
  instance_types   = ["t3.small"]

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_policy_attachment.my_nodegroup_role_attachment                                           #verify that it doesn't need to be this: aws_iam_role_policy_attachment.my_nodegroup_role_attachment
  ]
  #tags so that I can retrieve with a data source
    tags = {          
    "Name"      = "MyNodeGroup"
    "Cluster"   = aws_eks_cluster.my_eks_cluster.name
    "NodeGroup" = "my_node_group"
  }
}

resource "aws_iam_role" "my_nodegroup_role" {            #this role allows the eks.amazonaws.com to assume a role with a full access policies to call on other services in aws on behalf of ec2/eks
  name = "tech_task_nodegroup_role"

    assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "my_node_group_policy" {
  name        = "node_group_policy"
  description = "Full access policy for node group"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"                           #think about restricting these permissions to a more granular set: https://us-east-1.console.aws.amazon.com/eks/home?region=us-east-1#/clusters/VanOsTestCluster?selectedTab=cluster-access-tab
        Action = "*"
        Resource = "*"
      }
    ]
  })
}


resource "aws_iam_policy_attachment" "my_nodegroup_role_attachment" {
  name       = "my_nodegroup_role_attachment"
  roles      = [aws_iam_role.my_nodegroup_role.name]
  policy_arn = aws_iam_policy.my_node_group_policy.arn
}

resource "aws_iam_role" "my_eks_cluster_role" {            #this role allows the eks.amazonaws.com to assume a role with a full access policies to call on other services in aws on behalf of ec2/eks
  name = "my_eks_cluster_role"

    assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "eks_full_access" {
  name        = "eks_full_access"
  description = "access policy for EKS cluster"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"                           #think about restricting these permissions to a more granular set: https://us-east-1.console.aws.amazon.com/eks/home?region=us-east-1#/clusters/VanOsTestCluster?selectedTab=cluster-access-tab
        Action = "*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "my_eks_role_attachment" {
  name       = "my_eks_role_attachment"
  roles      = [aws_iam_role.my_eks_cluster_role.name]
  policy_arn = aws_iam_policy.eks_full_access.arn
}