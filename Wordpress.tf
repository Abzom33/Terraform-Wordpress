## RDS DB instance 

## Resource to db_subnet group which lists out the private subnets in my VPC

resource "aws_db_subnet_group" "wordpress_subnet" {
  name       = "wordpress_subnet"
  subnet_ids = [ aws_subnet.PrivateA.id , aws_subnet.PrivateB.id ]

  tags = {
    Name = "Private Subnets"
  }
}
 

## Creating DB Instance used for Wordpress 

resource "aws_db_instance" "wordpress" {
  db_name                =  "wpress"
  identifier             = "wordpress"
  instance_class         = var.instance_class
  allocated_storage      =  20
  engine                 = "mysql"
  engine_version         = "8.0"
  username               = var.username
  password               = var.password
  db_subnet_group_name   = aws_db_subnet_group.wordpress_subnet.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.wordpress_parameters.name
  publicly_accessible    = false
  skip_final_snapshot    = true
  enabled_cloudwatch_logs_exports = ["general"]
  

}


## Parameter for RDS which is used for connection logging and contains database-level settingg for RDS

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







## EC2 Wordpress
resource "aws_instance" "WordpressA" {
    instance_type = var.instance_type[0]
    ami = local.ami
    user_data = templatefile("${path.module}/userdata.sh", {
    db_name     = aws_db_instance.wordpress.db_name
    db_user     = var.db_user
    db_password = var.db_password
    db_host     = aws_db_instance.wordpress.address
  })
    subnet_id = aws_subnet.PrivateB.id
    key_name = aws_key_pair.deployer.key_name
    vpc_security_group_ids = [aws_security_group.ec2-sg.id]
}
    


  



resource "aws_instance" "WordpressB" {
    instance_type =  var.instance_type[0]
    ami = local.ami
    user_data = templatefile("${path.module}/userdata.sh", {
    db_name     = aws_db_instance.wordpress.db_name
    db_user     = var.db_user
    db_password = var.db_password
    db_host     = aws_db_instance.wordpress.address
  })
    subnet_id = aws_subnet.PrivateA.id
    key_name = aws_key_pair.deployer.key_name
    vpc_security_group_ids = [aws_security_group.ec2-sg.id]
}
    



