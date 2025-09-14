Terraform AWS Infrastructure Setup
This repository contains a Terraform configuration to deploy an AWS infrastructure with a proxy server, frontend servers, RDS (MySQL) with read replicas, and an ElastiCache Redis instance. The setup includes security groups and data preservation mechanisms to ensure no data loss during Terraform operations like tainting.
Overview
The infrastructure includes:

1 Proxy Server: An EC2 instance with a persistent Elastic IP, acting as a gateway (e.g., Nginx).
2 Frontend Servers: EC2 instances for hosting the application.
1 RDS MySQL Instance: A primary database with automated backups and read replicas for scalability.
1 Redis Cluster: An ElastiCache Redis instance with snapshotting for data persistence.
Security Groups:
Proxy and frontend servers allow SSH (22) from 192.168.1.78/32, HTTP (80), and HTTPS (443) from anywhere.
RDS (port 3306) and Redis (port 6379) allow access only from the proxy and frontend servers.



Data Preservation

RDS: Protected with prevent_destroy = true, automated backups (7-day retention), and final snapshots to prevent data loss during terraform taint or accidental deletion.
Redis: Protected with prevent_destroy = true and snapshotting (5 snapshots retained) to S3 for data persistence.
Proxy Elastic IP: Persists across instance recreation (e.g., after tainting) using aws_eip_association.

Prerequisites

Terraform: Version 1.5 or later.
AWS Account: With permissions to create EC2, RDS, ElastiCache, and VPC resources.
AWS CLI: Configured with credentials (aws configure).
VPC and Subnets: An existing VPC with at least two subnets in different availability zones.
AMI: A valid EC2 AMI ID for your region (e.g., Amazon Linux 2).

Setup Instructions

Clone the Repository:
git clone <repository-url>
cd <repository-directory>


Update Variables:Edit main.tf or create a terraform.tfvars file to set the following variables:

region: AWS region (e.g., us-east-1).
vpc_id: Your VPC ID (e.g., vpc-1234567890abcdef0).
subnet_ids: List of at least two subnet IDs (e.g., ["subnet-12345678", "subnet-87654321"]).
ami_id: A valid AMI ID for your region (e.g., ami-0c55b159cbfafe1f0).
Optional: Adjust rds_read_replica_count (default: 2), rds_backup_retention_period (default: 7 days), or redis_snapshot_retention_limit (default: 5 snapshots).

Example terraform.tfvars:
region        = "us-east-1"
vpc_id        = "vpc-1234567890abcdef0"
subnet_ids    = ["subnet-12345678", "subnet-87654321"]
ami_id        = "ami-0c55b159cbfafe1f0"


Initialize Terraform:
terraform init


Validate Configuration:
terraform validate


Plan Deployment:
terraform plan -out=tfplan


Apply Changes:
terraform apply tfplan



Outputs
After deployment, Terraform provides the following outputs:

proxy_eip: Elastic IP of the proxy server.
frontend_public_ips: Public IPs of the frontend servers.
rds_endpoint: Endpoint of the primary RDS instance.
rds_replica_endpoints: Endpoints of the RDS read replicas.
redis_endpoint: Endpoint of the Redis cluster.
rds_final_snapshot: Final snapshot identifier for the RDS instance.
redis_snapshot_name: Snapshot name for the Redis cluster.

Use these outputs to configure your application to connect to the proxy, RDS, and Redis.
Data Preservation Mechanisms

RDS:
Prevent Destroy: The prevent_destroy = true lifecycle rule blocks accidental deletion during terraform taint or apply.
Backups: Automated backups are enabled with a 7-day retention period (configurable via rds_backup_retention_period).
Final Snapshot: A snapshot is created before deletion (if allowed) to allow data restoration.


Redis:
Prevent Destroy: The prevent_destroy = true lifecycle rule prevents accidental deletion.
Snapshots: Snapshots are stored in S3 with a retention limit of 5 (configurable via redis_snapshot_retention_limit). Use the snapshot (my-redis-snapshot) to restore data if the cluster is recreated.


Proxy Elastic IP: The aws_eip resource is protected with prevent_destroy = true, and aws_eip_association ensures the IP persists after instance recreation.

Testing Taint Behavior
To test tainting without data loss:

Proxy: Run terraform taint aws_instance.proxy, then terraform plan. The instance is recreated, but the Elastic IP remains unchanged.
RDS/Redis: Run terraform taint aws_db_instance.rds or terraform taint aws_elasticache_cluster.redis. Terraform will error due to prevent_destroy = true. To recreate:
Comment out prevent_destroy temporarily.
Ensure snapshots are created (rds_final_snapshot, redis_snapshot_name).
Restore snapshots via the AWS console or update the Terraform configuration.



Security Considerations

SSH Access: Restricted to 192.168.1.78/32 for proxy and frontend servers.
Secrets: The RDS password is hardcoded for simplicity. Use AWS Secrets Manager or HashiCorp Vault in production.
Encryption: Consider enabling encryption for RDS (storage_encrypted = true) and Redis (at_rest_encryption_enabled = true) in production.
Monitoring: Add CloudWatch for monitoring and alerting in production.

Additional Notes

Load Balancer: The proxy server handles traffic routing. Add an AWS Application Load Balancer (ALB) for frontend load balancing if needed.
State Management: Use a remote backend (e.g., S3 with versioning) for state storage to enable collaboration and rollback.
Read Replicas: Configure your application to route read queries to rds_replica_endpoints for scalability.
Scaling: Adjust instance types (t2.micro, db.t3.micro, cache.t3.micro) for production workloads.

Troubleshooting

Invalid VPC/Subnets: Ensure vpc_id and subnet_ids are valid and span multiple availability zones.
AMI Issues: Verify the ami_id is valid for your region.
Taint Errors: If prevent_destroy blocks tainting, review the need to recreate resources and ensure snapshots/backups are available.
Rate Limits: If AWS API rate limits occur, reduce -parallelism (e.g., terraform apply -parallelism=5).

Contributing
Contributions are welcome! Submit a pull request or open an issue for suggestions or bug reports.
License
This project is licensed under the MIT License.
