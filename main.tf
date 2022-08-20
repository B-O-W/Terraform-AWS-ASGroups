data "aws_ami" "amazon-2" {
  most_recent = true

  filter { ##Change it for search and set Amazon-2-Image
    name = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
  }
  owners = ["amazon"]
}


resource "aws_launch_configuration" "terramino" {
  name_prefix     = "learn-terraform-aws-asg-"
  image_id        =  data.aws_ami.amazon-2.id
  instance_type   = "t2.micro"
  user_data       = file("user-data.sh")
  security_groups = [aws_security_group.terramino_instance.id]

  lifecycle {
    # The AMI ID must refer to an AMI that contains an operating system
    # for the `x86_64` architecture.
    precondition {
      condition     = data.aws_ami.amazon-2.architecture == "x86_64"
      error_message = "The selected AMI must be for the x86_64 architecture."
    }
  }
}

resource "aws_autoscaling_group" "terramino" {
  name                 = "terramino"
  min_size             = 1
  max_size             = 5
  desired_capacity     = 1
  health_check_type    = "ELB" ##add this parametr for check autoscaling group with network
  launch_configuration = aws_launch_configuration.terramino.name
  vpc_zone_identifier  = module.vpc.public_subnets

  tag {
    key                 = "Name"
    value               = "HashiCorp Learn ASG - Terramino"
    propagate_at_launch = true
  }
}


resource "aws_autoscaling_attachment" "terramino" {
  autoscaling_group_name = aws_autoscaling_group.terramino.id
  alb_target_group_arn   = aws_lb_target_group.terramino.arn
}

