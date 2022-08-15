output "lb_endpoint" {
  value = "http://${aws_lb.terramino.dns_name}"
}

output "application_endpoint" {
  value = "http://${aws_lb.terramino.dns_name}/index.php"
}

output "asg_name" {
  value = aws_autoscaling_group.terramino.name
}

output "vpc_id" {
  description = "vpc-id"
  value = module.vpc.vpc_id 
}
