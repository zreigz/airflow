variable "kube_context" {
  description = "kubeconfig context to use when connecting to the cluster"
  type        = string
  default     = "kind-kind"
}

variable "namespace" {
  description = "Kubernetes namespace where Airflow will be deployed"
  type        = string
  default     = "airflow"
}

