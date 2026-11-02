output "aws_instance" {
type = list(string)
value = [aws_instance.WordpressA.id, aws_instance.WordpressB.id]

}
