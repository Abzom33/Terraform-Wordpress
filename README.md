## Terraform Module 1 : Deploy WordPress Using Terraform

We are going to use Terraform to Deploy WordPress on AWS .

## Objective
Use Terraform to deploy a full WordPress stack on AWS.

The setup should include:

- EC2 instance running WordPress
- Security groups
- User data or cloud-init to install dependencies
- A working public endpoint
- All resources provisioned via Terraform


## Architecture




## Steps:

These are the steps I have taken to achieve this objective.





1. Set up your Terraform Environment 

You need to first which Provider Block you are using . In this case I am using `AWS` Provider Block.
You can get this from Terraform Registry.

This is the AWS Porvider from Terraform Registry HashiCorp

```
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.70.0"
    }
  }
}

provider "aws" {
  # Configuration options
}


```

1a. Store your Terraform State file remotely

This is a security measure to ensure that the Terraform State File remains safe , allows others to acces and collaborate with in
your team .

I chose AWS S3 as it is secure and provides automatic backups .

```
  backend "s3" {
    bucket = "Name of bucket"
    key = "/path/to/file"
    region = "us-east-1"
    
    
  }

```

Add this to your `AWS` Provider Code


1b . Run the command `terraform init` to initailize the backend , install provider and set up environment


2. Create a Custom VPC 

I wanted to provision my own VPC , so that I could have full control of the network . I used a `resource`block to achieve this :

```
 resource "aws_vpc" "Name" {
   cidr_block = "X.X.X.X/X"
     tags = {
    Name = "Name"
  }
 }

```

- You need to first declare a CIDR Block to your VPC . This is going to be where your IP will be allocated
- For private networks AWS recommends using 10.0.0.0  
- AWS CIDR Ranges goes /16 - /28


3. Ceated IGW 

In order for my resources inside my VPC to access the Internet . You need an IGW (Internet Gateway) and attach it to your VPC.

I used a `resource` block to do this :

```
resource "aws_internet_gateway" "IGW" {
  vpc_id = aws_vpc.Name.id

  tags = {
    Name = "Main-gw"
  }
}

```

- `  vpc_id = aws_vpc.Name.id` = Grabs the id of your VPC 


4. Creating Subnets

 Subnets are a segements of your networks. You can use it to group your resource for each segment for a network , this makes it clear to understand.

 - I used a `resource` block to create a subnet.

 
 ```
 resource "aws_subnet" "PublicA" {
  vpc_id = aws_vpc.my-vpc.id
  cidr_block = "x.x.x.x/x"
  tags = {
    Name = "Public Subnet A"
  }
}
```

- `CIDR` must not overlap when making a subnet or else the route tables won't know where to send traffic to since the IPs are
the same. AWS will give an error message

5. Creating a NAT Gateway

You create to allow your resource in a private subnet internet access . NAT Gateway allows outbound connects but blocks all inbound traffic to the resource in the private subnet.


5a. Create an Elastic IP

This is to ensure that only one public IP can be used for this NATGW.

```
  resource "aws_eip" "NAT_eip" {
  instance = aws_nat_gateway.NAT
  domain   = "vpc"
}

```


- I used a `resource` block to create a NATGW.

```
resource "aws_nat_gateway" "NAT" {
  allocation_id = aws_eip.NAT_eip.id   < -- This associates Elastic IP to this NATGW.
  subnet_id     = aws_subnet.PublicA.id  <---  Your placing this in the Public Subnet

  tags = {
    Name = "gw NAT"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.gw]
}


```


## Creating and Deploying WordPress Application 

Now that we have set up our environment , it is time to create and Deploy Wordpress


1. Set up and Create Security Groups for our resources . 


#### Table


## Security Groups

| security group | direction | port       | source / destination | notes |
|----------------|-----------|------------|----------------------|-------|
| **alb-sg**     | inbound   | 80 (TCP)   | `0.0.0.0/0`          | public HTTP traffic |
| **alb-sg**     | outbound  | 80 (TCP)   | `ec2-sg`             | forwards to app instances |
| **bastion-sg** | inbound   | 22 (TCP)   | `MYIP`               | your IP only |
| **bastion-sg** | outbound  | 22 (TCP)   | `ec2-sg`             | SSH into private instances |
| **ec2-sg**     | inbound   | 80 (TCP)   | `alb-sg`             | traffic from ALB only |
| **ec2-sg**     | inbound   | 22 (TCP)   | `bastion-sg`         | SSH from bastion only |
| **ec2-sg**     | outbound  | all        | `0.0.0.0/0`          | updates via NAT, RDS, etc. |
| **rds-sg**     | inbound   | 3306 (TCP) | `ec2-sg`             | MySQL from app instances only |
| **rds-sg**     | outbound  | none       | n/a                  | SGs are stateful, so replies are allowed automatically |



1a . Code Structure 

- First Create a resource block in which we are going to define our SG.

````

resource "aws_security_group"  "Name" {

   name        = "Name"
  description = "This is a description of what the Security Group should contain"
  vpc_id      =  The ID of your VPC

  tags = {
    Name = ""   
  }
}

````

1b . Create Ingress(Incoming) & Egress(Outbound) traffic for security group rules and attach it security group.

````
resource "aws_vpc_security_group_ingress_rule" "Name" {
  security_group_id = ID of your SG
  referenced_security_group_id = Use this to reference to Other SGs
  from_port         = 3306
  ip_protocol       = "tcp"
  to_port           = 3306
}

````


2. Creating RDS 

RDS (Relational Database Service) which is an AWS managed database service , where AWS manages deployment , updates , software pacthes and mnay more , you focus on the Database.


Steps :

1. Create a resource called `aws_subnet_group` which is used to define which subnets the RDS will be held in .

```

resource "aws_db_subnet_group" "Wordpress" {
  name       = "Wordpress_subnet"
  subnet_ids = [ aws_subnet.PrivateA.id , aws_subnet.PrivateB ]

  tags = {
    Name = "Private Subnets"
  }
}



```
2. Create a `db_instance` resource block which is used a create a isolated database with in the VPC.

```
resource "aws_db_instance" "Wordpres" {
  identifier             = "Wordpress"
  instance_class         = "db.t3.micro"
  allocated_storage      = 5
  engine                 = "mysql"
  engine_version         = "18"
  username               = "var.username"
  password               = "var.password"
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.Wordpres.name
  publicly_accessible    = false
  skip_final_snapshot    = true

}



```

3. Create a paramter group for your `db_instance`

- This use to configure your database engine itself

```

resource "aws_db_parameter_group" "Wordpres" {
  name   = "Wordpress"
  family = "mysql18.0"

  parameter {
    name  = "log_connections"
    value = "all"
  }
}



```

4. Create your Wordpress EC2 Instance 

You can do this using the `resource` block on Terraform .


Ex:

```
resource "aws_instance" "WordpressA" {
    instance_type = "t3.micro"
    ami = "ami-0c230065b91270bc6"
    user_data = templatefile("${path.module}/userdata.sh", {
    db_name     = aws_db_instance.wordpress.db_name
    db_user     = "ABZ_OM"
    db_password = "coderco9990876"
    db_host     = aws_db_instance.wordpress.address
  })
    subnet_id = aws_subnet.PrivateB.id
    key_name = aws_key_pair.deployer.key_name
    vpc_security_group_ids = [aws_security_group.ec2-sg.id]
}

```


5. Set up user-data 
You can set up your userdata to set and Install wordpress for your EC2 instances . User-data is a bootstrap script that you write to install dependencies onto to your instance when it boots up.


`````

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



`````



7.  Set up ALB

- An ALB is set up to route to distrubute your traffic to your instance , perform heath checks and as additional security measure to avoid user to have direct access to your instance.

7a. Create a Target Group

- A target group is a set of destinations that ALB can route to such as EC2 , Conatiners.

I created this by using this : https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group

```
resource "aws_lb_target_group" "my_tg_b" {
  name = "target-groupB"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my-vpc.id
}
```


7b .  Attach Instances to your Target Group 

```
resource "aws_lb_target_group_attachment" "WordpresA" {
  target_group_arn = aws_lb_target_group.my_tg_b.arn
  target_id        = aws_instance.WordpressA.id
  port             = 80
}


```
7c. Create the ALB 

- This is an Internet facing ALB , which means it can access and recieve traffic from the Internet
```
resource "aws_lb" "my_alb" {
  name               = "my-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb-sg.id]
   subnets           = [aws_subnet.PublicA.id , aws_subnet.PublicB.id]



  tags = {
    Environment = "production"
  }
}

```

7d. Attach a listener 

- This is decides how your traffic gets hits via HHTP , HTTPS , SSH and what decides what to do with the Traffic such as Route forward to Target Group.

This routes forward to my target group I specified earlier on Port 80 HTTP.

```

resource "aws_lb_listener" "B" {
  load_balancer_arn = aws_lb.my_alb.arn
  port              = "80"
  protocol          = "HTTP"
  

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_tg_b.arn
  }
}

```



8. Set up a bastion host

- A bastion host acts a controlled entry point into your private instance . It is an instance that sits in a public subnet in frint of your private instance inside a private subnet.

8a. Create a bastion instance in the `Public Subnet A` 

```

resource "aws_instance" "bastion" {
  ami = "ami-0c230065b91270bc6"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.PublicA.id
  key_name = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.bastion-sg.id]
  
}


```

- I also created an Elastic IP to attach to my instance so that it would 1 public Ip address to use.


```

  resource "aws_eip" "bastion_eip" {
    domain = "vpc"
    instance = aws_instance.bastion.id
  }

```



9 Final Result .

<img width="1497" height="698" alt="image" src="https://github.com/user-attachments/assets/7ba5a7b6-8475-47ac-bd8d-dff1784e288d" />



## Errors I encounterd :


### Error 1 :  

<img width="402" height="126" alt="image" src="https://github.com/user-attachments/assets/c7719bd1-704a-498a-9957-dfc674ec107e" />


##### Solution :  

There was loop back between the command `instance = aws_nat_gateway.NAT` in my `aws_eip` block and `allocation_id = aws_eip.NAT_eip.id` in my `aws_nat_gateway` , Sice the Elastic IP used for NATGW , was pointng back to NATGW . 

Therefore I removed `instance = aws_nat_gateway.NAT`  


