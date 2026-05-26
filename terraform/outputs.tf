output "worker_name" {
  description = "Multipass instance name of the worker VM."
  value       = multipass_instance.worker.name
}

output "db_name" {
  description = "Multipass instance name of the database VM."
  value       = multipass_instance.db.name
}

output "worker_ip" {
  description = "Primary IPv4 address of the worker VM."
  value       = multipass_instance.worker.ipv4
}

output "db_ip" {
  description = "Primary IPv4 address of the database VM."
  value       = multipass_instance.db.ipv4
}
