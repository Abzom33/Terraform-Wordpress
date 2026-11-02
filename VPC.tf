 resource "aws_vpc" "my-vpc" {
   cidr_block = "10.0.0.0/16"
     tags = {
    Name = "my-vpc"
  }
 }


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.my-vpc.id

  tags = {
    Name = "Main-gw"
  }
}

resource "aws_subnet" "PublicA" {
  vpc_id = aws_vpc.my-vpc.id
  cidr_block = "10.0.0.0/20"
  tags = {
    Name = "Public Subnet A"
    
    
  }
}


resource "aws_subnet" "PublicB" {
  vpc_id = aws_vpc.my-vpc.id
  cidr_block = "10.0.16.0/20"
  tags = {
    Name = "Public Subnet B"
  }
}


resource "aws_subnet" "PrivateA" {
  vpc_id = aws_vpc.my-vpc.id
  cidr_block = "10.0.32.0/20"
  tags = {
    Name = "Private Subnet A"
  }
}




resource "aws_subnet" "PrivateB" {
  vpc_id = aws_vpc.my-vpc.id
  cidr_block = "10.0.48.0/20"
  tags = {
    Name = "Private Subnet B"
  }
}


  resource "aws_eip" "NAT_eip" {
  
  domain   = "vpc"
}





resource "aws_nat_gateway" "NAT" {
  allocation_id = aws_eip.NAT_eip.id
  subnet_id     = aws_subnet.PublicA.id

  tags = {
    Name = "gw NAT"
  }

 
  depends_on = [aws_internet_gateway.gw]
}



resource "aws_route_table" "Public" {
  vpc_id = aws_vpc.my-vpc.id
  tags = {
    "Name" = "Public Route "
  }

}


resource "aws_route_table" "Public2" {
  vpc_id = aws_vpc.my-vpc.id
  tags = {
    "Name" = "Public Route B"
  }

}


resource "aws_route_table" "PrivateA" {
  vpc_id = aws_vpc.my-vpc.id
  tags = {
    "Name" = "Priavte Route A"
  }

}

resource "aws_route_table" "PrivateB" {
  vpc_id = aws_vpc.my-vpc.id
  tags = {
    "Name" = "Private Route B"
  }

}


resource "aws_route" "Priavte_RouteA" {
  route_table_id = aws_route_table.PrivateA.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_nat_gateway.NAT.id

  

}


resource "aws_route" "Priavte_RouteB" {
  route_table_id = aws_route_table.PrivateB.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_nat_gateway.NAT.id

  

}


resource "aws_route_table_association" "Priavte_RouteA" {
  subnet_id      = aws_subnet.PrivateA.id
  route_table_id = aws_route_table.PrivateA.id
}



resource "aws_route_table_association" "Priavte_RouteB" {
  subnet_id      = aws_subnet.PrivateB.id
  route_table_id = aws_route_table.PrivateB.id
}




resource "aws_route" "Public_Route" {
  route_table_id = aws_route_table.Public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.gw.id

  

}


resource "aws_route" "Public_Route1" {
  route_table_id = aws_route_table.Public2.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.gw.id

  

}


resource "aws_route_table_association" "RouteA_public" {
  subnet_id      = aws_subnet.PublicA.id
  route_table_id = aws_route_table.Public.id
}



resource "aws_route_table_association" "RouteB_public" {
  subnet_id      = aws_subnet.PublicB.id
  route_table_id = aws_route_table.Public2.id
}
