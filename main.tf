# Provider configuration
provider "aws" {
  region = var.region
}

# Variables
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
  default     = "vpc-1234567890abcdef0" # Replace with your VPC ID
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
  default     = ["subnet-12345678", "subnet-87654321"] # Replace with your subnet IDs
}

variable "ami_id" {
  description = "AMI ID for EC2 instances"
  type        = string
  default     = "ami-0c55b159cbfafe1f0" # Replace with a valid AMI for your region
}

# Security Group for Proxy and Frontend Servers
resource "aws_security_group" "proxy_frontend_sg" {
  name        = "proxy-frontend-sg"
  description = "Security group for proxy and frontend servers"
  vpc_id      = var.vpc_id

  # SSH (port 22) from specific IP
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["192.168.1.78/32"]
  }

  # HTTP (port 80) from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS (port 443) from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group for RDS
resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Security group for RDS instance"
  vpc_id      = var.vpc_id

  # MySQL (port 3306) from proxy and frontend servers
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.proxy_frontend_sg.id]
  }
}

# Security Group for Redis
resource "aws_security_group" "redis_sg" {
  name        = "redis-sg"
  description = "Security group for Redis instance"
  vpc_id      = var.vpc_id

  # Redis (port 6379) from proxy and frontend servers
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.proxy_frontend_sg.id]
  }
}

# Proxy EC2 Instance
resource "aws_instance" "proxy" {
  ami           = var.ami_id
  instance_type = "t2.micro"
  subnet_id     = var.subnet_ids[0]
  security_groups = [aws_security_group.proxy_frontend_sg.name]

  tags = {
    Name = "proxy-server"
  }
}

# Frontend EC2 Instances
resource "aws_instance" "frontend" {
  count         = 2
  ami           = var.ami_id
  instance_type = "t2.micro"
  subnet_id     = var.subnet_ids[count.index % length(var.subnet_ids)]
  security_groups = [aws_security_group.proxy_frontend_sg.name]

  tags = {
    Name = "frontend-server-${count.index + 1}"
  }
}

# RDS Instance (MySQL)
resource "aws_db_instance" "rds" {
  identifier           = "my-rds-instance"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  storage_type        = "gp2"
  username             = "admin"
  password             = "securepassword123" # Use a secret manager in production
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name
  skip_final_snapshot  = true
}

# RDS Subnet Group
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = var.subnet_ids
}

# ElastiCache Redis Instance
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "my-redis-cluster"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis6.x"
  subnet_group_name    = aws_elasticache_subnet_group.redis_subnet_group.name
  security_group_ids   = [aws_security_group.redis_sg.id]
}

# Redis Subnet Group
resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "redis-subnet-group"
  subnet_ids = var.subnet_ids
}

# Outputs
output "proxy_public_ip" {
  description = "Public IP of the proxy server"
  value       = aws_instance.proxy.public_ip
}

output "frontend_public_ips" {
  description = "Public IPs of the frontend servers"
  value       = aws_instance.frontend[*].public_ip
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.rds.endpoint
}

output "redis_endpoint" {
  description = "Redis instance endpoint"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}
