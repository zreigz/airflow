output "namespace" {
  description = "Airflow namespace"
  value       = var.namespace
}

output "airflow_secret_name" {
  description = "Name of the Kubernetes secret containing Airflow credentials"
  value       = kubernetes_manifest.airflow.manifest.metadata.name
}

output "fernet_key" {
  description = "Airflow Fernet key (sensitive)"
  value       = base64encode(random_password.fernet_key.result)
  sensitive   = true
}
