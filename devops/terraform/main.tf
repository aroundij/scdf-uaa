provider "aws" {
  region = "us-east-1"
}

resource "aws_ecs_cluster" "dev_cluster" {
  name = "DevCluster"
}

data "aws_ssm_parameter" "bdd_url" {
  name = "scdf.bdd_url"
}

data "aws_ssm_parameter" "bdd_user" {
  name = "scdf.bdd_user"
}

data "aws_ssm_parameter" "bdd_password" {
  name = "scdf.bdd_password"
}

resource "aws_ecs_task_definition" "my_task" {
  family                   = "my-task-family"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions    = jsonencode([
    {
      name           = "scdf-server"
      image          = "springcloud/spring-cloud-dataflow-server:2.11.3-jdk17"
      cpu            = 256
      memory         = 512
      essential      = true
      mountPoints    = [
        {
          sourceVolume  = "scdf-config"
          containerPath = "/home/cnb/scdf"
          readOnly      = false
        }
      ]
      portMappings = [
        {
          containerPort = 9393
          hostPort      = 9393
        }
      ]
      environment = [
        { name = "BDD_URL", value = data.aws_ssm_parameter.bdd_url.value },
        { name = "BDD_USER", value = data.aws_ssm_parameter.bdd_user.value },
        { name = "BDD_PASSWORD", value = data.aws_ssm_parameter.bdd_password.value },
        { name = "SPRING_CONFIG_ADDITIONAL_LOCATION", value = "/home/cnb/scdf/scdf-config.yml" }
      ]
    }
  ])
  volume {
    name      = "scdf-config"
    host_path = "/home/cnb/scdf"
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs_task_execution_role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Effect    = "Allow"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Security group for ALB"
  vpc_id      = "<Your-VPC-ID>"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "my_alb" {
  name               = "my-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = ["<Your-Subnet-ID-1>", "<Your-Subnet-ID-2>"]
}

resource "aws_lb_target_group" "my_tg" {
  name     = "my-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "<Your-VPC-ID>"
}

resource "aws_lb_listener" "my_listener" {
  load_balancer_arn = aws_lb.my_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_tg.arn
  }
}

resource "aws_ecs_service" "my_service" {
  name            = "my-service"
  cluster         = aws_ecs_cluster.dev_cluster.id
  task_definition = aws_ecs_task_definition.my_task.arn
  desired_count   = 1
  launch_type     = "EC2"
  load_balancer {
    target_group_arn = aws_lb_target_group.my_tg.arn
    container_name   = "scdf-server"
    container_port   = 9393
  }

  network_configuration {
    subnets         = ["<Your-Subnet-ID-1>", "<Your-Subnet-ID-2>"]
    security_groups = [aws_security_group.alb_sg.id]
    assign_public_ip = true
  }

  depends_on = [aws_lb_listener.my_listener]
}