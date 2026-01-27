resource "aws_instance" "web1" {
  ami                    = "ami-0532be01f26a3de55"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  user_data              = file("${path.module}/user_data.sh")
}

resource "aws_instance" "web2" {
  ami                    = "ami-0532be01f26a3de55"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_2.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  user_data              = file("${path.module}/user_data.sh")
}
 