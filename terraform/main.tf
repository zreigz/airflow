terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}

# ── Random secrets ────────────────────────────────────────────────────────────

resource "random_password" "fernet_key" {
  length  = 32
  special = false
  # Fernet keys must be 32 url-safe base64-encoded bytes; we base64-encode
  # the 32-character random string in the secret below.
}

resource "random_password" "webserver_secret_key" {
  length  = 32
  special = false
}

resource "random_password" "postgres_password" {
  length  = 16
  special = false
}

# ── Namespace ─────────────────────────────────────────────────────────────────
# The namespace is created by Plural's ServiceDeployment (createNamespace: true).
# Terraform only needs to ensure it exists before writing secrets into it.

resource "kubernetes_namespace" "airflow" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/name"       = "airflow"
    }
  }

  lifecycle {
    # Plural also manages this namespace; prevent Terraform from destroying it
    # when the stack is torn down (Plural will handle deletion).
    prevent_destroy = false
    ignore_changes  = [metadata[0].labels, metadata[0].annotations]
  }
}

# ── Airflow secrets ───────────────────────────────────────────────────────────
# These are mounted into the Airflow pods via extraEnvFrom / extraEnv in the
# Helm values file (helm/airflow.yaml).

resource "kubernetes_secret" "airflow" {
  metadata {
    name      = "airflow-secrets"
    namespace = kubernetes_namespace.airflow.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/name"       = "airflow"
    }
  }

  data = {
    # Fernet key: 32 bytes → base64 → URL-safe base64 (Fernet expects this)
    fernet-key        = base64encode(random_password.fernet_key.result)
    webserver-secret  = random_password.webserver_secret_key.result
    postgres-password = random_password.postgres_password.result
    # Full connection string consumed by Airflow via AIRFLOW__DATABASE__SQL_ALCHEMY_CONN
    connection-string = "postgresql+psycopg2://airflow:${random_password.postgres_password.result}@airflow-postgresql:5432/airflow"
  }
}

# ── PostgreSQL admin secret (used by the embedded PostgreSQL sub-chart) ───────
# The postgresql sub-chart reads 'postgres-password' key from this secret.

resource "kubernetes_secret" "postgresql" {
  metadata {
    name      = "airflow-postgresql"
    namespace = kubernetes_namespace.airflow.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/name"       = "airflow-postgresql"
    }
  }

  data = {
    postgres-password = random_password.postgres_password.result
    password          = random_password.postgres_password.result
  }
}

