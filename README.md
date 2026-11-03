# Deploying WordPress on AWS with Terraform

n this project I used Terraform to deploy WordPress on AWS. Everything is built as code. The network, the servers, the database and the load balancer are all in Terraform.

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

## Steps

These are the steps I took to build this.

### 1. Set up your Terraform environment

First you need to pick which provider you are using. In this case I am using the `AWS` provider. You can get this from the Terraform Registry.

This is the AWS provider from HashiCorp:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.70.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
```

#### 1a. Store your Terraform state file remotely

I store the state file remotely so it stays safe and isn't sitting on one laptop. It also means other people on a team can access it and work on the same infrastructure.

I chose AWS S3 because it is secure and keeps backups of the file.

```hcl
  backend "s3" {
    bucket = "<state-bucket-name>"
    key    = "wordpress/terraform.tfstate"
    region = "us-east-1"
  }
```

Add this inside the `terraform` block from step 1.

#### 1b. Run `terraform init`

Run `terraform init` to set up the backend, install the provider and get your environment ready.

### 2. Create a custom VPC

I wanted to build my own VPC so that I have full control of the network: the IP ranges, the routing and how the subnets are laid out. I used a `resource` block to do this:

```hcl
resource "aws_vpc" "my-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "wordpress-vpc"
  }
}
```

- You first need to give your VPC a CIDR block. This is the range your IPs will be given out from.
- For private networks you use a private range like `10.0.0.0`. AWS VPC CIDR blocks can go from /16 to /28. A /16 leaves plenty of room for subnets.

### 3. Create an Internet Gateway

For resources inside the VPC to reach the internet, you need an IGW (Internet Gateway) attached to your VPC.

I used a `resource` block to do this:

```hcl
resource "aws_internet_gateway" "IGW" {
  vpc_id = aws_vpc.my-vpc.id

  tags = {
    Name = "main-igw"
  }
}
```

- `vpc_id = aws_vpc.my-vpc.id` grabs the ID of your VPC and attaches the IGW to it.

### 4. Create the subnets

Subnets are segments of your network. You use them to group your resources, which makes the network clear to understand.

I split my VPC into:

- **Public subnets** for the ALB, the bastion and the NAT Gateway
- **Private subnets** for WordPress and RDS

They are spread across 2 Availability Zones because the ALB and the RDS subnet group both need subnets in at least 2 AZs.

I used a `resource` block for each subnet:

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

- Subnet CIDRs must not overlap. If they do, AWS gives you an error and won't create the subnet.

### 5. Create a NAT Gateway

My WordPress instance needs internet access to install packages and download WordPress, but I don't want anyone on the internet to reach it. A NAT Gateway in a public subnet sorts this out. It allows outbound connections from the private subnets and blocks inbound traffic coming in.

#### 5a. Create an Elastic IP

A public NAT Gateway needs an Elastic IP, so it has one fixed public IP.

```hcl
resource "aws_eip" "NAT_eip" {
  domain = "vpc"
}
```

#### 5b. Create the NAT Gateway

I used a `resource` block to create the NAT Gateway:

```hcl
resource "aws_nat_gateway" "NAT" {
  allocation_id = aws_eip.NAT_eip.id    # attaches the Elastic IP to this NAT Gateway
  subnet_id     = aws_subnet.PublicA.id # puts it in the public subnet

  tags = {
    Name = "nat-gw"
  }

  # makes sure the IGW is created first
  depends_on = [aws_internet_gateway.IGW]
}
```

## Creating and Deploying the WordPress Application

Now that the network is set up, it is time to create and deploy WordPress.

### 6. Create the security groups

Each layer only accepts traffic from the layer in front of it.

| Security group | Direction | Port       | Source / destination | Notes |
|----------------|-----------|------------|----------------------|-------|
| **alb-sg**     | inbound   | 80 (TCP)   | `0.0.0.0/0`          | Public HTTP traffic |
| **alb-sg**     | outbound  | 80 (TCP)   | `ec2-sg`             | Forwards to the WordPress instance |
| **bastion-sg** | inbound   | 22 (TCP)   | `<your-ip>/32`       | SSH from my IP only |
| **bastion-sg** | outbound  | 22 (TCP)   | `ec2-sg`             | SSH into the private instance |
| **ec2-sg**     | inbound   | 80 (TCP)   | `alb-sg`             | Traffic from the ALB only |
| **ec2-sg**     | inbound   | 22 (TCP)   | `bastion-sg`         | SSH from the bastion only |
| **ec2-sg**     | outbound  | all        | `0.0.0.0/0`          | Updates through the NAT, RDS access |
| **rds-sg**     | inbound   | 3306 (TCP) | `ec2-sg`             | MySQL from the WordPress instance only |
| **rds-sg**     | outbound  | none       | n/a                  | Security groups are stateful, so replies are allowed automatically |

#### 6a. Create the security group

First create a `resource` block for the security group:

```hcl
resource "aws_security_group" "rds" {
  name        = "rds-sg"
  description = "Allow MySQL from the WordPress instance"
  vpc_id      = aws_vpc.my-vpc.id
}
```

#### 6b. Add the ingress (inbound) and egress (outbound) rules

Each rule is its own resource that you attach to the security group.

```hcl
resource "aws_vpc_security_group_ingress_rule" "rds_from_ec2" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.ec2-sg.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
}
```

- `referenced_security_group_id` lets you point to another security group instead of an IP range. This ties the rule to the actual resources, not to IP addresses.

### 7. Create the RDS database

RDS (Relational Database Service) is AWS's managed database service. AWS handles the setup, patching and backups, and you focus on the database.

#### 7a. Create a subnet group

The subnet group decides which subnets the database lives in. I put it in my two private subnets.

```hcl
resource "aws_db_subnet_group" "wordpress_subnet" {
  name       = "wordpress-subnet"
  subnet_ids = [aws_subnet.PrivateA.id, aws_subnet.PrivateB.id]

  tags = {
    Name = "Private Subnets"
  }
}
```

#### 7b. Create a parameter group

A parameter group is used to configure the database engine itself. I used it to turn on the general query log and write it to a file so it can be sent to CloudWatch.

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

#### 7c. Create the database instance

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

### 8. Create the WordPress EC2 instance

The instance runs in a private subnet. I used `templatefile()` to pass the database details into the user data script when it deploys.

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

### 9. Set up the user data script

User data is a bootstrap script that runs when the instance first boots up. Mine installs Apache and PHP, downloads WordPress and puts the database settings into `wp-config.php`.

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

### 10. Set up the ALB

The ALB is the only way into WordPress from the internet. It sends traffic to my instance, runs health checks on it, and means users never connect to the instance directly.

#### 10a. Create a target group

A target group is the set of places the ALB can send traffic to, like EC2 instances or containers.

I built this using the [Terraform docs for `aws_lb_target_group`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group).

```hcl
resource "aws_lb_target_group" "my_tg_b" {
  name     = "target-groupB"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my-vpc.id
}
```

#### 10b. Attach the instance to the target group

```hcl
resource "aws_lb_target_group_attachment" "WordpressA" {
  target_group_arn = aws_lb_target_group.my_tg_b.arn
  target_id        = aws_instance.WordpressA.id
  port             = 80
}
```

#### 10c. Create the ALB

This is an internet-facing ALB, which means it receives traffic from the internet. It sits across both public subnets.

```hcl
resource "aws_lb" "my_alb" {
  name               = "my-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb-sg.id]
  subnets            = [aws_subnet.PublicA.id, aws_subnet.PublicB.id]
}
```

#### 10d. Add a listener

A listener decides which port and protocol the ALB listens on (like HTTP or HTTPS) and what to do with the traffic, like forwarding it to a target group.

Mine forwards HTTP traffic on port 80 to the target group I made earlier.

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

### 11. Set up a bastion host

A bastion host is a controlled entry point into your private instance. It is an instance that sits in a public subnet, in front of the instance in the private subnet. It's the only way I can SSH into my WordPress instance, and its security group only accepts SSH from my IP.

#### 11a. Create the bastion instance in Public Subnet A

```hcl
resource "aws_instance" "bastion" {
  ami                    = local.ami
  instance_type          = var.instance_type[1]
  subnet_id              = aws_subnet.PublicA.id
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.bastion-sg.id]
}
```

#### 11b. Attach an Elastic IP

I also gave the bastion an Elastic IP so it keeps the same public IP, even if I stop and start the instance.

```hcl
resource "aws_eip" "bastion_eip" {
  domain   = "vpc"
  instance = aws_instance.bastion.id
}
```

## How to run it

```bash
terraform init      # set up the S3 backend and download the provider
terraform plan      # check what will be created
terraform apply     # build the infrastructure
terraform destroy   # tear it all down when you're done
```

Once `apply` finishes, open the ALB DNS name in your browser and you'll get the WordPress setup page.

## Final Result

<img width="1497" height="698" alt="WordPress running behind the ALB" src="https://github.com/user-attachments/assets/7ba5a7b6-8475-47ac-bd8d-dff1784e288d" />

## Errors I Encountered

### Error 1: Cycle between the Elastic IP and the NAT Gateway

<img width="402" height="126" alt="Terraform cycle error" src="https://github.com/user-attachments/assets/c7719bd1-704a-498a-9957-dfc674ec107e" />

#### Solution

There was a loop between `instance = aws_nat_gateway.NAT` in my `aws_eip` block and `allocation_id = aws_eip.NAT_eip.id` in my `aws_nat_gateway` block. The Elastic IP was pointing to the NAT Gateway, and the NAT Gateway was pointing back to the Elastic IP, so Terraform didn't know which one to create first.

I fixed it by removing `instance = aws_nat_gateway.NAT` from the Elastic IP. The NAT Gateway already attaches the Elastic IP through `allocation_id`, so that's all you need.

## What I'd Improve Next

This is a learning project, so some things you'd want in production aren't set up yet. These are the gaps I know about and plan to fix:

- **HTTPS:** the ALB only listens on HTTP. Next I'll add an ACM certificate, a 443 listener and a redirect from HTTP to HTTPS.
- **Secrets:** the database password goes through Terraform variables and user data, so it ends up in the state file and in the instance's user data. Moving it to AWS Secrets Manager would fix both.
- **State security:** turn on encryption and state locking for the S3 backend.
- **Database:** turn on storage encryption and automated backups, and remove `skip_final_snapshot`.
- **Instance access:** replace the bastion with AWS Systems Manager Session Manager so I can close port 22 completely, and enforce IMDSv2 on the instances.
