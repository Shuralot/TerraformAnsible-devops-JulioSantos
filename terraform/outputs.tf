output "environment" {
  value       = terraform.workspace
  description = "The deployment environment"
}

output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC"
}

output "subnet_id" {
  value       = aws_subnet.public.id
  description = "The ID of the public subnet"
}

output "instance_id" {
  value       = aws_instance.web.id
  description = "The ID of the EC2 instance"
}

output "public_ip" {
  value       = aws_instance.web.public_ip
  description = "The public IP address of the EC2 instance"
}

output "app_url" {
  value       = "http://${aws_instance.web.public_ip}:3000"
  description = "The URL of the deployed web application"
}

output "ssh_command" {
  value       = "ssh -i terraform/id_rsa.pem ubuntu@${aws_instance.web.public_ip}"
  description = "Command to SSH into the instance"
}
