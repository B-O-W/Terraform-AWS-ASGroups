resource "aws_lb" "terramino" {
  name               = "learn-asg-terramino-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.terramino_lb.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_listener" "terramino" {
  load_balancer_arn = aws_lb.terramino.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.terramino.arn
  }
}

resource "aws_lb_target_group" "terramino" {
  name     = "learn-asg-terramino"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  #Health check path
    health_check {
    path                = "/"
    port                = 80
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200-499"
  }
}



# If you want enable listeners with HTTPS
# ------- ALB HTTP Listener --------
#
#resource "aws_lb_listener" "web_http" {
#  load_balancer_arn = local.alb_arn
#  port              = 80
#  protocol          = "HTTP"
#  default_action {
#    type = "redirect"
#
#    redirect {
#      port        = "443"
#      protocol    = "HTTPS"
#      status_code = "HTTP_301"
#    }
#  }
#}
#
## ------- ALB HTTPS Listener --------
#
#resource "aws_lb_listener" "web_https" {
#  load_balancer_arn = local.alb_arn
#  port              = 443
#  protocol          = "HTTPS"
#  certificate_arn = aws_acm_certificate_validation.my_domain.certificate_arn
#
#  default_action {
#    type             = "forward"
#    target_group_arn = aws_lb_target_group.web.arn
#  }
#}