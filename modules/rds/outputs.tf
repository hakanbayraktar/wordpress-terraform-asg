output "db_endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.wordpress.endpoint
}

output "db_address" {
  description = "RDS address"
  value       = aws_db_instance.wordpress.address
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.wordpress.db_name
}

output "db_port" {
  description = "Database port"
  value       = aws_db_instance.wordpress.port
}