
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "intern-task-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "intern-task-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "intern-task-public-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "intern-task-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "app" {
  name        = "intern-task-app-sg"
  description = "Allow restricted SSH and public app access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from the configured CIDR only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    description = "Application HTTP port"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound traffic for package installation"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "intern-task-app-sg"
  }
}

locals {
  app_source = file("${path.module}/../../intern-task-app/app/app.py")
  dockerfile = file("${path.module}/../../intern-task-app/Dockerfile")

  raw_user_data = <<USERDATA
#!/bin/bash
set -euxo pipefail

exec > >(tee -a /var/log/intern-task-bootstrap.log) 2>&1


useradd --create-home --shell /bin/bash internadmin
usermod -aG sudo internadmin
echo 'internadmin ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/internadmin
chmod 0440 /etc/sudoers.d/internadmin


apt-get update
apt-get install -y docker.io ufw
systemctl enable --now docker


mkdir -p /opt/intern-task-app/app
cat > /opt/intern-task-app/app.py <<'APP_SOURCE'
${local.app_source}
APP_SOURCE

cat > /opt/intern-task-app/Dockerfile <<'DOCKERFILE'
${local.dockerfile}
DOCKERFILE


mkdir -p /opt/intern-task-app/app
cp /opt/intern-task-app/app.py /opt/intern-task-app/app/app.py

docker build -t intern-task-app:latest /opt/intern-task-app


cat > /etc/systemd/system/intern-task-app.service <<'SERVICE'
[Unit]
Description=Intern task application container
Requires=docker.service
After=docker.service

[Service]
Restart=always
ExecStartPre=-/usr/bin/docker rm -f intern-task-app
ExecStart=/usr/bin/docker run --name intern-task-app --rm -p ${var.app_port}:${var.app_port} -e PORT=${var.app_port} intern-task-app:latest
ExecStop=/usr/bin/docker stop -t 10 intern-task-app

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload




ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw --force enable


cat > /usr/local/sbin/intern-task-docker-firewall.sh <<'FIREWALL'
#!/bin/sh
set -eu

iptables -N INTERN_TASK_DOCKER 2>/dev/null || true
iptables -F INTERN_TASK_DOCKER

iptables -A INTERN_TASK_DOCKER -p tcp --dport ${var.app_port} -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
iptables -A INTERN_TASK_DOCKER -j DROP

iptables -C DOCKER-USER -j INTERN_TASK_DOCKER 2>/dev/null || \
  iptables -I DOCKER-USER 1 -j INTERN_TASK_DOCKER
FIREWALL

chmod 0755 /usr/local/sbin/intern-task-docker-firewall.sh

cat > /etc/systemd/system/intern-task-docker-firewall.service <<'SERVICE'
[Unit]
Description=Firewall rules for the intern task Docker application
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/intern-task-docker-firewall.sh

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now intern-task-docker-firewall.service
systemctl enable --now intern-task-app.service
USERDATA
  user_data     = replace(local.raw_user_data, "\r\n", "\n")
}

resource "aws_instance" "app" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true

  user_data                   = local.user_data
  user_data_replace_on_change = false

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "intern-task-app"
  }
}

output "instance_public_ip" {
  description = "Public IPv4 address of the EC2 instance."
  value       = aws_instance.app.public_ip
}

output "app_port" {
  description = "TCP port exposed by the application."
  value       = var.app_port
}
