
## Creating Traget Groups to Attach ALB

## Target : EC2 instances 




resource "aws_lb_target_group" "my_tg_b" {
  name = "target-groupB"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my-vpc.id
}



## Create Target Group attachment 

resource "aws_lb_target_group_attachment" "WordpresA" {
  target_group_arn = aws_lb_target_group.my_tg_b.arn
  target_id        = aws_instance.WordpressA.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "WordpresB" {
  target_group_arn = aws_lb_target_group.my_tg_b.arn
  target_id        = aws_instance.WordpressB.id
  port             = 80
}


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




resource "aws_lb_listener" "B" {
  load_balancer_arn = aws_lb.my_alb.arn
  port              = "80"
  protocol          = "HTTP"
  

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_tg_b.arn
  }
}


