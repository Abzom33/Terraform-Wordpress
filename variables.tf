variable "instance_type" {
  type = list(string)
  default = ["t3.micro", "t2.micro"]
}

# SENSITVE
variable "cidr_ipv4"{
  type = string
  sensitive = true
  
}

locals {
 ami = "ami-0c230065b91270bc6"
  
}

variable "instance_class" {
  type = string
  default = "db.t3.micro"
  
}
# SENSITVE
variable "username" {
  type = string
  sensitive = true
  
}
# SENSITVE
variable "password"{
  type = string
   sensitive = true
}
# SENSITVE
variable "db_user" {
    type = string
   sensitive = true
}

# SENSITVE
variable "db_password" {
    type = string
  sensitive = true
  
}
