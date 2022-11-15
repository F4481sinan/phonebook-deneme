terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.10.0"
    }
    github = {
      source  = "integrations/github"
      version = "4.23.0"
    }
  }
  
}

provider "aws" {
  region  = "us-east-1"
}

provider "github" {
  token = var.token
}
variable "token" {
  default = "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"
}

data "aws_vpc" "default_vpc" {
  default = true
}

data "aws_subnets" "subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default_vpc.id]
  }
}


resource "aws_security_group" "tf-project-alb" {
  name        = "tf-project-alb"
  description = "for ALB"
  vpc_id      = data.aws_vpc.default_vpc.id

  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "tf-project-ec2" {
  name        = "tf-project-ec2"
  description = "for ec2"
  vpc_id      = data.aws_vpc.default_vpc.id

  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    security_groups   = [aws_security_group.tf-project-alb.id]
  }

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]

  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "tf-project-db" {
  name        = "tf-project-db"
  description = "for db"
  vpc_id      = data.aws_vpc.default_vpc.id


  ingress {
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    security_groups   = [aws_security_group.tf-project-ec2.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

}

resource "aws_launch_template" "lt-ec2" {
  name = "lt-ec2"



  image_id = "ami-09d3b3274b6c5d4aa"

  instance_type = "t2.micro"

  key_name = "firstkey"


  vpc_security_group_ids = [aws_security_group.tf-project-ec2.id]

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "lt-ec2"
    }
  }

  user_data = filebase64("userdata.sh")   #calismayabilir problem oldugunda buraya bakilacak
}

resource "aws_lb_target_group" "tg-project" {
  name     = "tg-project"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default_vpc.id
  target_type = "instance"
  
  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 3

  }
}


resource "aws_lb" "tf-alb" {
  name               = "tf-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.tf-project-alb.id]
  subnets            = data.aws_subnets.subnets.ids

  enable_deletion_protection = false

  tags = {
    Environment = "production"
  }
}
resource "aws_lb_listener" "tf-listener" {
  load_balancer_arn = aws_lb.tf-alb.arn    #dikkat
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg-project.arn  #dikkat
  }
}

resource "aws_autoscaling_group" "tf-asg" {
  name                      = "tf-asg"
  max_size                  = 3
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 2
  force_delete              = true
  target_group_arns = [aws_lb_target_group.tg-project.arn]
  vpc_zone_identifier       = aws_lb.tf-alb.subnets

  launch_template {
    id      = aws_launch_template.lt-ec2.id
    version = aws_launch_template.lt-ec2.latest_version
  }
}

resource "aws_db_instance" "db-server" {
  allocated_storage    = 10
  db_name              = "phonebook"
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = "db.t2.micro"
  username             = "admin"
  password             = "Oliver_1"
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
  vpc_security_group_ids = [aws_security_group.tf-project-db.id]
  
}

resource "github_repository_file" "dbendpoint" {
  content             = aws_db_instance.db-server.address
  file                = "dbserver.endpoint"
  repository          = "phonebook"
  overwrite_on_create = true
  branch              = "main"

}