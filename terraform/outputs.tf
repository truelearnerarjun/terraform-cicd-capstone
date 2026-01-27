output "alb_dns_name" {
  value = aws_lb.alb.dns_name
}
 
output "web1_instance_id" {
  value = aws_instance.web1.id
}
 
output "web2_instance_id" {
  value = aws_instance.web2.id
}