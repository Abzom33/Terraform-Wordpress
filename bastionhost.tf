

resource "aws_instance" "bastion" {
  ami = local.ami
  instance_type = var.instance_type[1]
  subnet_id = aws_subnet.PublicA.id
  key_name = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.bastion-sg.id]
  
}


  resource "aws_eip" "bastion_eip" {
    domain = "vpc"
    instance = aws_instance.bastion.id
  }