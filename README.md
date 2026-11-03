# Deploying WordPress on AWS with Terraform

Terraform Module 1. This project provisions a WordPress site on AWS using Terraform. The network, compute, database and load balancer are all defined as code, and nothing is created by hand in the console.

## What gets built

- A custom VPC with two public and two private subnets
- An Internet Gateway for the public subnets and a NAT Gateway for outbound traffic from the private subnets
- An Application Load Balancer (ALB) that serves WordPress on port 80
- A WordPress EC2 instance in a private subnet, bootstrapped with a user data script
- An RDS MySQL 8.0 database in the private subnets, not publicly accessible
- A bastion host in a public subnet for SSH access to the private instance
- Security groups that only allow traffic between the layers that need it
- Remote Terraform state stored in S3

## Architecture

```
                         Internet
                            |
                     Internet Gateway
                            |
+--------------------------- VPC ----------------------------+
|                                                            |
|  Public subnets (A, B)                                     |
|    ALB :80          Bastion host (EIP)    NAT Gateway (EIP)|
|      |                   |                     ^           |
|      v                   v :22                 |           |
|  Private subnets (A, B)                        |           |
|    WordPress EC2 (Apache + PHP) ---------------+ outbound  |
|      |                                                     |
|      v :3306                                               |
|    RDS MySQL 8.0                                           |
+------------------------------------------------------------+
```

Request flow: user -> ALB (public subnet) -> WordPress EC2 (private subnet) -> RDS (private subnet).

## Prerequisites

- Terraform installed
- AWS CLI configured with credentials for your account
- An existing S3 bucket for the remote state
- An SSH key pair for the bastion and WordPress instances

## Build steps

### 1. Provider and remote state

The project uses the HashiCorp AWS provider from the Terraform Registry. State is stored in S3 so it isn't kept on a single laptop and can be shared with a team.

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.70.0"
    }
  }

  backend "s3" {
    bucket = "<state-bucket-name>"
    key    = "wordpress/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}
```

The `backend` block goes inside the `terraform` block, not the `provider` block. Run `terraform init` to configure the backend and download the provider.

### 2. VPC

A custom VPC gives full control over IP ranges, routing and subnet layout instead of relying on the default VPC.

```hcl
resource "aws_vpc" "my-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "wordpress-vpc"
  }
}
```

VPC CIDR blocks can range from /16 to /28. Using a private RFC 1918 range such as `10.0.0.0/16` leaves plenty of room for subnets.

### 3. Internet Gateway

The Internet Gateway lets resources in the public subnets reach the internet and receive inbound traffic.

```hcl
resource "aws_internet_gateway" "IGW" {
  vpc_id = aws_vpc.my-vpc.id

  tags = {
    Name = "main-igw"
  }
}
```

### 4. Subnets

The VPC is split into public subnets (ALB, bastion, NAT Gateway) and private subnets (WordPress and RDS), spread across two Availability Zones. The ALB and the RDS subnet group both require subnets in at least two AZs.

```hcl
resource "aws_subnet" "PublicA" {
  vpc_id            = aws_vpc.my-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Public Subnet A"
  }
}
```

Subnet CIDRs must not overlap. AWS rejects the subnet if they do.

### 5. NAT Gateway

The WordPress instance needs outbound internet access to install packages and download WordPress, but it should not be reachable from the internet. A NAT Gateway in a public subnet handles this: it allows outbound connections from the private subnets and blocks unsolicited inbound traffic.

A public NAT Gateway needs an Elastic IP:

```hcl
resource "aws_eip" "NAT_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "NAT" {
  allocation_id = aws_eip.NAT_eip.id
  subnet_id     = aws_subnet.PublicA.id

  tags = {
    Name = "nat-gw"
  }

  depends_on = [aws_internet_gateway.IGW]
}
```

## Deploying WordPress

### 6. Security groups

Each layer only accepts traffic from the layer in front of it.

| Security group | Direction | Port       | Source / destination | Notes |
|----------------|-----------|------------|----------------------|-------|
| **alb-sg**     | inbound   | 80 (TCP)   | `0.0.0.0/0`          | Public HTTP traffic |
| **alb-sg**     | outbound  | 80 (TCP)   | `ec2-sg`             | Forwards to the WordPress instance |
| **bastion-sg** | inbound   | 22 (TCP)   | `<your-ip>/32`       | SSH from my IP only |
| **bastion-sg** | outbound  | 22 (TCP)   | `ec2-sg`             | SSH into private instances |
| **ec2-sg**     | inbound   | 80 (TCP)   | `alb-sg`             | Traffic from the ALB only |
| **ec2-sg**     | inbound   | 22 (TCP)   | `bastion-sg`         | SSH from the bastion only |
| **ec2-sg**     | outbound  | all        | `0.0.0.0/0`          | Package updates via NAT, RDS access |
| **rds-sg**     | inbound   | 3306 (TCP) | `ec2-sg`             | MySQL from the WordPress instance only |
| **rds-sg**     | outbound  | none       | n/a                  | Security groups are stateful, so replies are allowed automatically |

Security groups are created with `aws_security_group`, and each rule is a separate resource. Referencing another security group instead of a CIDR range keeps rules tied to specific resources rather than IP addresses.

```hcl
resource "aws_security_group" "rds" {
  name        = "rds-sg"
  description = "Allow MySQL from the WordPress instance"
  vpc_id      = aws_vpc.my-vpc.id
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_ec2" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.ec2-sg.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
}
```

### 7. RDS database

RDS is AWS's managed relational database service. AWS handles provisioning, patching and backups, so the focus stays on the database itself.

The subnet group places the database in the two private subnets:

```hcl
resource "aws_db_subnet_group" "wordpress_subnet" {
  name       = "wordpress-subnet"
  subnet_ids = [aws_subnet.PrivateA.id, aws_subnet.PrivateB.id]

  tags = {
    Name = "Private Subnets"
  }
}
```

A parameter group configures the MySQL engine. Here it enables the general query log and writes it to file so it can be exported to CloudWatch:

```hcl
resource "aws_db_parameter_group" "wordpress_parameters" {
  name   = "wordpress"
  family = "mysql8.0"

  parameter {
    name  = "general_log"
    value = "1"
  }

  parameter {
    name  = "log_output"
    value = "FILE"
  }
}
```

The database instance:

```hcl
resource "aws_db_instance" "wordpress" {
  identifier                      = "wordpress"
  db_name                         = "wpress"
  engine                          = "mysql"
  engine_version                  = "8.0"
  instance_class                  = var.instance_class
  allocated_storage               = 20
  username                        = var.db_user
  password                        = var.db_password
  db_subnet_group_name            = aws_db_subnet_group.wordpress_subnet.name
  vpc_security_group_ids          = [aws_security_group.rds.id]
  parameter_group_name            = aws_db_parameter_group.wordpress_parameters.name
  publicly_accessible             = false
  skip_final_snapshot             = true
  enabled_cloudwatch_logs_exports = ["general"]
}
```

### 8. WordPress EC2 instance

The instance runs in a private subnet. `templatefile()` injects the database connection details into the user data script at deploy time.

```hcl
resource "aws_instance" "WordpressA" {
  ami                    = local.ami
  instance_type          = var.instance_type[0]
  subnet_id              = aws_subnet.PrivateB.id
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.ec2-sg.id]

  user_data = templatefile("${path.module}/userdata.sh", {
    db_name     = aws_db_instance.wordpress.db_name
    db_user     = var.db_user
    db_password = var.db_password
    db_host     = aws_db_instance.wordpress.address
  })
}
```

### 9. User data script

The user data script runs on first boot. It installs Apache and PHP, downloads WordPress, and writes the database settings into `wp-config.php`.

```bash
#!/bin/bash
dnf update -y
dnf install -y httpd wget php php-mysqlnd php-fpm php-json php-gd php-mbstring php-xml
systemctl enable --now httpd php-fpm

cd /tmp
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* /var/www/html/

cd /var/www/html
cp wp-config-sample.php wp-config.php
sed -i "s|database_name_here|${db_name}|" wp-config.php
sed -i "s|username_here|${db_user}|" wp-config.php
sed -i "s|password_here|${db_password}|" wp-config.php
sed -i "s|localhost|${db_host}|" wp-config.php

chown -R apache:apache /var/www/html
systemctl restart httpd
```

### 10. Application Load Balancer

The ALB is the only public entry point to WordPress. It runs health checks against the instance and means users never connect to the instance directly.

Target group, which defines where the ALB sends traffic:

```hcl
resource "aws_lb_target_group" "my_tg_b" {
  name     = "target-groupB"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my-vpc.id
}

resource "aws_lb_target_group_attachment" "WordpressA" {
  target_group_arn = aws_lb_target_group.my_tg_b.arn
  target_id        = aws_instance.WordpressA.id
  port             = 80
}
```

Internet-facing ALB across both public subnets:

```hcl
resource "aws_lb" "my_alb" {
  name               = "my-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb-sg.id]
  subnets            = [aws_subnet.PublicA.id, aws_subnet.PublicB.id]
}
```

Listener, which forwards HTTP traffic on port 80 to the target group:

```hcl
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.my_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_tg_b.arn
  }
}
```

### 11. Bastion host

The bastion sits in a public subnet and is the only way to SSH into the private WordPress instance. Its security group only accepts SSH from my IP.

```hcl
resource "aws_instance" "bastion" {
  ami                    = local.ami
  instance_type          = var.instance_type[1]
  subnet_id              = aws_subnet.PublicA.id
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.bastion-sg.id]
}

resource "aws_eip" "bastion_eip" {
  domain   = "vpc"
  instance = aws_instance.bastion.id
}
```

The Elastic IP gives the bastion a fixed public address that doesn't change if the instance is stopped and started.

## Usage

```bash
terraform init      # configure the S3 backend and download providers
terraform plan      # review the changes
terraform apply     # create the infrastructure
terraform destroy   # tear everything down when finished
```

Once `apply` completes, open the ALB DNS name in a browser to reach the WordPress setup page.

## Result

<img width="1497" height="698" alt="WordPress running behind the ALB" src="https://github.com/user-attachments/assets/7ba5a7b6-8475-47ac-bd8d-dff1784e288d" />

## Troubleshooting

### Dependency cycle between the Elastic IP and NAT Gateway

<img width="402" height="126" alt="Terraform cycle error" src="https://github.com/user-attachments/assets/c7719bd1-704a-498a-9957-dfc674ec107e" />

**Cause:** the `aws_eip` block had `instance = aws_nat_gateway.NAT`, and the `aws_nat_gateway` block had `allocation_id = aws_eip.NAT_eip.id`. Each resource depended on the other, so Terraform couldn't work out which to create first.

**Fix:** I removed the `instance` argument from the Elastic IP. The NAT Gateway already attaches the EIP through `allocation_id`, so the EIP doesn't need to reference the gateway.

## Security considerations and next steps

This is a learning project and some production practices aren't in place yet. Known gaps I plan to address:

- **HTTPS:** the ALB only listens on HTTP. Next step is an ACM certificate, a 443 listener and an HTTP to HTTPS redirect.
- **Secrets:** the database password is passed through Terraform variables and user data, so it ends up in the state file and the instance's user data. Moving it to AWS Secrets Manager would fix both.
- **State security:** enable encryption and state locking on the S3 backend.
- **Database:** enable storage encryption and automated backups, and remove `skip_final_snapshot`.
- **Instance access:** replace the bastion with AWS Systems Manager Session Manager so port 22 can be closed entirely, and enforce IMDSv2 on the instances.
- **Availability:** a single WordPress instance and a single NAT Gateway mean one AZ failure takes the site down. An Auto Scaling group across both private subnets would remove that.