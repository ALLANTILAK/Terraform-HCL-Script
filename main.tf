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

variable "rds_read_replica_count" {
  description = "Number of RDS read replicas"
  type        = number
  default     = 2
}

variable "rds_backup_retention_period" {
  description = "RDS backup retention period in days"
  type        = number
  default     = 7
}

variable "redis_snapshot_retention_limit" {
  description = "Number of Redis snapshots to retain"
  type        = number
  default     = 5
}

# Security Group for Proxy and Frontend Servers
resource "aws_security_group" "proxy_frontend_sg" {
  name        = "proxy-frontend-sg"
  description = "Security group for proxy and frontend servers"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["192.168.1.78/32"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.proxy_frontend_sg.id]
  }
}

# Elastic IP for Proxy Server
resource "aws_eip" "proxy_eip" {
  vpc = true
  tags = {
    Name = "proxy-eip"
  }

  lifecycle {
    prevent_destroy = true # Prevents accidental deletion of the EIP
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

# Associate Elastic IP with Proxy Instance
resource "aws_eip_association" "proxy_eip_assoc" {
  instance_id   = aws_instance.proxy.id
  allocation_id = aws_eip.proxy_eip.id
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

# RDS Subnet Group
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = var.subnet_ids
}

# RDS Primary Instance (MySQL)
resource "aws_db_instance" "rds" {
  identifier                = "my-rds-instance"
  engine                    = "mysql"
  engine_version            = "8.0"
  instance_class            = "db.t3.micro"
  allocated_storage         = 20
  storage_type              = "gp2"
  username                  = "admin"
  password                  = "securepassword123" # Use a secret manager in production
  vpc_security_group_ids    = [aws_security_group.rds_sg.id]
  db_subnet_group_name      = aws_db_subnet_group.rds_subnet_group.name
  backup_retention_period   = var.rds_backup_retention_period
  final_snapshot_identifier = "my-rds-final-snapshot-${timestamp()}"
  skip_final_snapshot       = false

  lifecycle {
    prevent_destroy = true # Prevents accidental deletion of the RDS instance
  }
}

# RDS Read Replicas
resource "aws_db_instance" "rds_read_replica" {
  count               = var.rds_read_replica_count
  identifier          = "my-rds-replica-${count.index + 1}"
  instance_class      = "db.t3.micro"
  replicate_source_db = aws_db_instance.rds.identifier
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot = false
  final_snapshot_identifier = "my-rds-replica-${count.index + 1}-final-snapshot-${timestamp()}"

  lifecycle {
    prevent_destroy = true # Prevents accidental deletion of read replicas
  }
}

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "redis-subnet-group"
  subnet_ids = var.subnet_ids
}

# ElastiCache Redis Instance
resource "aws_elasticache_cluster" "redis" {
  cluster_id               = "my-redis-cluster"
  engine                   = "redis"
  node_type                = "cache.t3.micro"
  num_cache_nodes          = 1
  parameter_group_name     = "default.redis6.x"
  subnet_group_name        = aws_elasticache_subnet_group.redis_subnet_group.name
  security_group_ids       = [aws_security_group.redis_sg.id]
  snapshot_retention_limit = var.redis_snapshot_retention_limit
  snapshot_name            = "my-redis-snapshot"

  lifecycle {
    prevent_destroy = true # Prevents accidental deletion of the Redis cluster
  }
}

# Outputs
output "proxy_eip" {
  description = "Elastic IP of the proxy server"
  value       = aws_eip.proxy_eip.public_ip
}

output "frontend_public_ips" {
  description = "Public IPs of the frontend servers"
  value       = aws_instance.frontend[*].public_ip
}

output "rds_endpoint" {
  description = "RDS primary instance endpoint"
  value       = aws_db_instance.rds.endpoint
}

output "rds_replica_endpoints" {
  description = "RDS read replica endpoints"
  value       = aws_db_instance.rds_read_replica[*].endpoint
}

output "redis_endpoint" {
  description = "Redis instance endpoint"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "rds_final_snapshot" {
  description = "RDS final snapshot identifier"
  value       = aws_db_instance.rds.final_snapshot_identifier
}

output "redis_snapshot_name" {
  description = "Redis snapshot name"
  value       = aws_elasticache_cluster.redis.snapshot_name
}
