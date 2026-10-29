variable "aws_region" {
  description = "AWS region for the infrastructure."
  type        = string
  default     = "us-east-1"
}

variable "ssh_allowed_cidr" {
  description = "Single CIDR range allowed to access SSH, for example your public IP followed by /32."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.ssh_allowed_cidr))
    error_message = "ssh_allowed_cidr must be a valid IPv4 CIDR range."
  }
}

variable "ami_id" {
  description = "Ubuntu AMI ID available in the selected AWS region."
  type        = string
  default     = "ami-0e86e20dae9224db8"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "Port on which the application listens inside the container."
  type        = number
  default     = 5000
}