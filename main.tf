# Proveedor de AWS
provider "aws" {
  region     = "us-east-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

# Variables para las claves de acceso
variable "aws_access_key" {
  type = string
  default = ""
}

variable "aws_secret_key" {
  type = string
  default = ""
}

# Módulo VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.14.0"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.3.0/24", "10.0.4.0/24"]

  enable_nat_gateway = true
}

# Salida de depuración para verificar el ID de la VPC
output "vpc_id_output" {
  value = module.vpc.vpc_id
  description = "ID de la VPC creada por el módulo VPC"
}

# Crear el grupo de seguridad
resource "aws_security_group" "web_sg" {
  vpc_id      = module.vpc.vpc_id
  name        = "web_sg"
  description = "Allow HTTP and SSH access"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

# Crear dos instancias EC2 dentro de la VPC
resource "aws_instance" "web" {
  count         = 2
  ami           = "ami-06b21ccaeff8cd686"
  instance_type = "t2.micro"

  subnet_id              = module.vpc.public_subnets[count.index]
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  tags = {
    Name = "WebInstance-${count.index + 1}"
  }
}

# Crear el Application Load Balancer (ALB)
resource "aws_lb" "web_load_balancer" {
  name               = "web-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false

  tags = {
    Name = "WebLoadBalancer"
  }
}

# Crear el Target Group para el ALB
resource "aws_lb_target_group" "web_tg" {
  name     = "web-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Registrar las instancias EC2 en el Target Group
resource "aws_lb_target_group_attachment" "web_targets" {
  count            = 2
  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

# Crear el Listener para el ALB
resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_load_balancer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

