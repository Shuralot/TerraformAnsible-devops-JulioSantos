data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

resource "aws_vpc" "main" {
  cidr_block           = lookup(var.vpc_cidr, terraform.workspace, var.vpc_cidr["default"])
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "vpc-${terraform.workspace}"
    Environment = terraform.workspace
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = lookup(var.subnet_cidr, terraform.workspace, var.subnet_cidr["default"])
  map_public_ip_on_launch = true

  tags = {
    Name        = "subnet-public-${terraform.workspace}"
    Environment = terraform.workspace
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "igw-${terraform.workspace}"
    Environment = terraform.workspace
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name        = "rt-public-${terraform.workspace}"
    Environment = terraform.workspace
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
  name        = "web-sg-${terraform.workspace}"
  description = "Allow SSH and HTTP access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Web App Port"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name        = "web-sg-${terraform.workspace}"
    Environment = terraform.workspace
  }
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ssh" {
  key_name   = "key-${terraform.workspace}"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_file" "ssh_private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/id_rsa.pem"
  file_permission = "0600"
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = aws_key_pair.ssh.key_name

  tags = {
    Name        = "web-server-${terraform.workspace}"
    Environment = terraform.workspace
  }
}

resource "local_file" "ansible_inventory" {
  content = <<EOT
[webservers]
${aws_instance.web.public_ip} ansible_user=ubuntu
EOT
  filename = "${path.module}/../ansible/hosts.ini"
}

resource "null_resource" "ansible_trigger" {
  depends_on = [
    aws_instance.web,
    local_file.ssh_private_key,
    local_file.ansible_inventory
  ]

  triggers = {
    instance_id = aws_instance.web.id
    public_ip   = aws_instance.web.public_ip
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command     = <<EOT
      $ip = "${aws_instance.web.public_ip}"
      $port = 22
      $connected = $false
      Write-Host "Waiting for SSH to become ready on $ip..."
      while (-not $connected) {
          try {
              $tcp = New-Object System.Net.Sockets.TcpClient
              $connect = $tcp.BeginConnect($ip, $port, $null, $null)
              $wait = $connect.AsyncWaitHandle.WaitOne(1000, $false)
              if ($wait -and $tcp.Connected) {
                  $tcp.EndConnect($connect)
                  $connected = $true
              }
              $tcp.Close()
          } catch {
              # Ignore and retry
          }
          if (-not $connected) {
              Start-Sleep -Seconds 5
          }
      }
      Write-Host "SSH is ready. Invoking Ansible inside WSL..."
      
      # Copy key and vault password to WSL and set correct permissions (avoiding Windows mount exec bit issues)
      wsl mkdir -p /home/Shura/.ssh
      wsl cp /mnt/c/Projetos/DevOpsProva2JulioSantos/terraform/id_rsa.pem /home/Shura/.ssh/id_rsa_${terraform.workspace}
      wsl chmod 600 /home/Shura/.ssh/id_rsa_${terraform.workspace}
      wsl cp /mnt/c/Projetos/DevOpsProva2JulioSantos/ansible/vault_pass.txt /tmp/vault_pass.txt
      wsl chmod 600 /tmp/vault_pass.txt
      
      # Run Ansible Playbook
      wsl bash -c "ANSIBLE_HOST_KEY_CHECKING=False /home/Shura/.local/bin/ansible-playbook -i /mnt/c/Projetos/DevOpsProva2JulioSantos/ansible/hosts.ini /mnt/c/Projetos/DevOpsProva2JulioSantos/ansible/playbook.yml --private-key /home/Shura/.ssh/id_rsa_${terraform.workspace} --vault-password-file /tmp/vault_pass.txt"
    EOT
  }
}
