# Terraform Manage AWS Auto Scaling Groups

![Untitled](Terraform%20Manage%20AWS%20Auto%20Scaling%20Groups%202ff5e7a405fe43278f6ad3f71497a811/Untitled.png)

## Prerequisites

This tutorial assumes that you are familiar with the standard Terraform workflow. If you are new to Terraform, complete the [Get Started tutorials](https://learn.hashicorp.com/collections/terraform/aws-get-started) first.

For this tutorial, you will need:

- [Terraform v1.1+ installed locally](https://learn.hashicorp.com/tutorials/terraform/install-cli)
- An [AWS account](https://portal.aws.amazon.com/billing/signup) with [credentials configured for Terraform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication)
- The [AWS CLI](https://aws.amazon.com/cli/)

### EC2 Launch Configuration

A **launch configuration** specifies the EC2 instance configuration that an ASG will use to launch each new instance.

main.tf

```terraform
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
  key_name        = "elbrus-2"
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
```

Launch configurations support many arguments and customization options for your instances.

This configuration specifies:

- a name prefix to use for all versions of this launch configuration. Terraform will append a unique identifier to the prefix for each launch configuration created.
- an Amazon Linux AMI specified by a data source.
- an instance type.
- a user data script, which configures the instances to run the `user-data.sh` file in this repository at launch time. The user data script installs dependencies and initializes Terramino, a Terraform-skinned Tetris application.
- a security group to associate with the instances. The security group (defined later in this file) allows ingress traffic on port 80 and egress traffic to all endpoints.

I’m use `precondition`blocks to specify assumptions and guarantees about how the data source operates. The following examples creates a postcondition that checks whether the AMI has the correct tags.

### Auto Scaling group

An ASG is a logical grouping of EC2 instances running the same configuration. ASGs allow for dynamic scaling and make it easier to manage a group of instances that host the same services.

main.tf

```javascript
resource "aws_autoscaling_group" "terramino" {
  name                 = "terramino"
  min_size             = 1
  max_size             = 5
  desired_capacity     = 1
  health_check_type    = "ELB" ##I'm add this parametr for check autoscaling group with network
  launch_configuration = aws_launch_configuration.terramino.name
  vpc_zone_identifier  = module.vpc.public_subnets

  tag {
    key                 = "Name"
    value               = "HashiCorp Learn ASG - Terramino"
    propagate_at_launch = true
  }
}
```

This ASG configuration sets:

- the minimum and maximum number of instances allowed in the group.
- the desired count to launch (`desired_capacity`).
- a launch configuration to use for each instance in the group.
- a list of subnets where the ASGs will launch new instances. This configuration references the public subnets created by the `vpc` module.

You can use health_check_type `ELB`and `EC2` blocks to specify!
FYI **`[health_check_type](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group#health_check_type)`** - (Optional) "EC2" or "ELB". Controls how health checking is done.

### Load balancer resources

Since you will launch multiple instances running your Terramino application, you must provision a load balancer to distribute traffic across the instances.

The `aws_lb` resource creates an application load balancer, which routes traffic at the application layer.

[alb-target-group.tf](http://alb-target-group.tf/)

```json
resource "aws_lb" "terramino" {
  name               = "learn-asg-terramino-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.terramino_lb.id]
  subnets            = module.vpc.public_subnets
}
```

The `[aws_lb_listener` resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) specifies how to handle any HTTP requests to port `80`. In this case, it forwards all requests to the load balancer to a target group. You can define multiple listeners with distinct listener rules for more complex traffic routing.

alb-target-group.tf

```json
resource "aws_lb_listener" "terramino" {
  load_balancer_arn = aws_lb.terramino.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.terramino.arn
  }
}
```

A target group defines the collection of instances your load balancer sends traffic to. It does not manage the configuration of the targets in that group directly, but instead specifies a list of destinations the load balancer can forward requests to.

alb-target-group.tf

```json
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
```

While you can use an `[aws_lb_target_group_attachment` resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment) to directly associate an EC2 instance or other target type with the target group, the dynamic nature of instances in an ASG makes that hard to maintain in configuration. Instead, this configuration links your Auto Scaling group with the target group using the `aws_autoscaling_attachment` resource. This allows AWS to automatically add and remove instances from the target group over their lifecycle.

## Security groups

This configuration also defines two security groups: one to associate with your ASG EC2 instances, and another for the load balancer.

security-group.tf

```json
resource "aws_security_group" "terramino_instance" { #For EC2 with Dynamic SG
  name = "learn-asg-terramino-instance"

  dynamic "ingress" { ###Open port for check localy 
  for_each = ["80", "443", "22"]
  content {
    from_port   = ingress.value
    to_port     = ingress.value
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.terramino_lb.id]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.terramino_lb.id]
  }

   egress { ## for install a lot of dependency for userdata
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = module.vpc.vpc_id
}

resource "aws_security_group" "terramino_lb" { #For LoadBalancer
  name = "learn-asg-terramino-lb"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress { ### Add this line for after you enable https aws_lb_listeners to 443 
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = module.vpc.vpc_id
}
```

Both of these security groups allow ingress HTTP traffic on port 80 and all outbound traffic. However, the `aws_security_group.terramino_instance`
 group restricts inbound traffic to requests coming from any source associated with the `aws_security_group.terramino_lb`
 security group, ensuring that only requests forwarded from your load balancer will reach your instances.

***What did i change:***

I used a dynamic security group

Open egress for install a lot of dependency for user-data.sh

# Output.tf

## I change some problem in this script because after my terraform installed you see output from terraform

For example:

```json
Outputs:
application_endpoint = "[https://learn-asg-terramino-lb-1572171601.us-east-2.elb.amazonaws.com/index.php](https://learn-asg-terramino-lb-1572171601.us-east-2.elb.amazonaws.com/index.php)"
asg_name = "terramino"
lb_endpoint = "[https://learn-asg-terramino-lb-1572171601.us-east-2.elb.amazonaws.com](https://learn-asg-terramino-lb-1572171601.us-east-2.elb.amazonaws.com/)"
```

***Because your load balancer work on the HTTP, not HTTPS if you send curl you don't see any output***

I changed [output.tf](http://output.tf) to this configuration 

```json
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
```

# And I changed User-data.sh

```bash
#!/bin/bash
yum update -y
yum install -y httpd.x86_64
systemctl start httpd.service
systemctl enable httpd.service
echo “Hello World from $(hostname -f)” > /var/www/html/index.html
```

# Deploying Terraform

```bash
terraform init

Initializing the backend...

Initializing provider plugins...
- Reusing previous version of hashicorp/aws from the dependency lock file
- Installing hashicorp/aws v3.50.0...
- Installed hashicorp/aws v3.50.0 (signed by HashiCorp)

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
```

# Terraform Plan|Apply

```bash
terraform apply
Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:
##...
Plan: 18 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + lb_endpoint = (known after apply)
Do you want to perform these actions in workspace "rita-asg"?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

 Enter a value: yes
##...

Apply complete! Resources: 36 added, 0 changed, 0 destroyed.

Outputs:

application_endpoint = "http://learn-asg-terramino-lb-1312245032.eu-west-1.elb.amazonaws.com/index.php"
asg_name = "terramino"
lb_endpoint = "http://learn-asg-terramino-lb-1312245032.eu-west-1.elb.amazonaws.com"
vpc_id = "vpc-0087206e7c6cb93b0"
```

Next, use `cURL`to send a request to the `lb_endpoint`output, which reports the instance ID of the EC2 instance responding to your request.

```bash
curl $(terraform output -raw lb_endpoint)
```

![Untitled](Terraform%20Manage%20AWS%20Auto%20Scaling%20Groups%202ff5e7a405fe43278f6ad3f71497a811/Untitled%201.png)

![Untitled](Terraform%20Manage%20AWS%20Auto%20Scaling%20Groups%202ff5e7a405fe43278f6ad3f71497a811/Untitled%202.png)

# ****Useful Documentation:****

[Data Sources - Configuration Language | Terraform by HashiCorp](https://www.terraform.io/language/data-sources)

[Manage AWS Auto Scaling Groups | Terraform - HashiCorp Learn](https://learn.hashicorp.com/tutorials/terraform/aws-asg)

[Terraform Dynamic Blocks with Examples](https://www.cloudbolt.io/terraform-best-practices/terraform-dynamic-blocks/)
