output "namespace" {
  description = "Airflow namespace"
  value       = var.namespace
}

output "airflow_secret_name" {
  description = "Name of the Kubernetes secret containing Airflow credentials"
  value       = kubernetes_secret.airflow.metadata[0].name
}

output "postgresql_secret_name" {
  description = "Name of the Kubernetes secret containing PostgreSQL credentials"
  value       = kubernetes_secret.postgresql.metadata[0].name
}

output "postgres_password" {
  description = "PostgreSQL password (sensitive)"
  value       = random_password.postgres_password.result
  sensitive   = true
}

output "fernet_key" {
  description = "Airflow Fernet key (sensitive)"
  value       = base64encode(random_password.fernet_key.result)
  sensitive   = true
}

