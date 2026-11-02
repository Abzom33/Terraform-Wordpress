## Creating SG for RDS , EC2(Wordpress) , ALB  and  Bastion Host



## RDS SG 

## Rules 
## Ingress : port 3306   source : ec2-sg
## Egress : Anywhere (Not needed) 


resource "aws_security_group" "rds" {
  name        = "rds"
  description = "Allow port 3306 inbound traffic from MYSQL and all outbound traffic"
  vpc_id      = aws_vpc.my-vpc.id

  tags = {
    Name = "rds"
  }
}


resource "aws_vpc_security_group_ingress_rule" "allow_mysql" {
  security_group_id = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.ec2-sg.id
  from_port         = 3306
  ip_protocol       = "tcp"
  to_port           = 3306
}





## SG EC2(Wordpres)

## Ingress : Allow HTTP (Port 80) from alb-sg & Allow SSH (Port22) from bastion-sg
## Egress : All traffic destination 0.0.0.0/0



resource "aws_security_group" "ec2-sg" {
  name        = "ec2-sg"
  description = "Allow HTTP (Port 80) from alb-sg"
  vpc_id      = aws_vpc.my-vpc.id

  tags = {
    Name = "ec2-sg"
  }
}



resource "aws_vpc_security_group_ingress_rule" "allow_http_from_alb" {
  security_group_id = aws_security_group.ec2-sg.id
  referenced_security_group_id = aws_security_group.alb-sg.id
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}


resource "aws_vpc_security_group_ingress_rule" "allow_SSH_from_bastion" {
  security_group_id = aws_security_group.ec2-sg.id
  referenced_security_group_id = aws_security_group.bastion-sg.id
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.ec2-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" 
}


## ALB SG
## Ingress :  Allow HTTP (Port 80) from  anywhere
## Egress :  Allow HTTP (Port 80) to EC2-SG

resource "aws_security_group" "alb-sg" {
  name        = "alb"
  description = "Allow HTTP (Port 80) from  anywhere"
  vpc_id      = aws_vpc.my-vpc.id

  tags = {
    Name = "alb"
  }
}


resource "aws_vpc_security_group_ingress_rule" "allow_http" {
  security_group_id = aws_security_group.alb-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "send_to_ec2-sg" {
  security_group_id = aws_security_group.alb-sg.id
  referenced_security_group_id = aws_security_group.ec2-sg.id
  ip_protocol       = "tcp"
  from_port = 80
  to_port = 80

}


## Bastion SG
## Ingress : allow ssh traffic from my ip
## Egress : Point to my wordpress A

resource "aws_security_group" "bastion-sg" {
  name        = "bastion"
  description = "Allow SSH traffic into bastion $ Egress traffic directs to Wordpress"
  vpc_id      = aws_vpc.my-vpc.id

  tags = {
    Name = "bastion"
  }
}
resource "aws_vpc_security_group_ingress_rule" "bastion"  {
ip_protocol = "tcp"
security_group_id = aws_security_group.bastion-sg.id
from_port = 22
to_port = 22
cidr_ipv4 = var.cidr_ipv4

}



resource "aws_vpc_security_group_egress_rule" "send_to_ec2" {
  security_group_id = aws_security_group.bastion-sg.id
  referenced_security_group_id = aws_security_group.ec2-sg.id
  ip_protocol       = "tcp"
  from_port = 22
  to_port = 22

}