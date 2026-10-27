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










## Errors I encounterd :


### Error 1 :  

<img width="402" height="126" alt="image" src="https://github.com/user-attachments/assets/c7719bd1-704a-498a-9957-dfc674ec107e" />


##### Solution :  

There was loop back between the command `instance = aws_nat_gateway.NAT` in my `aws_eip` block and `allocation_id = aws_eip.NAT_eip.id` in my `aws_nat_gateway` , Sice the Elastic IP used for NATGW , was pointng back to NATGW . 

Therefore I removed `instance = aws_nat_gateway.NAT`  


