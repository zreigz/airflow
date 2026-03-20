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
  # Explicit in-cluster configuration: reads the service-account token and CA
  # cert that Kubernetes mounts into every pod automatically.
  host                   = "https://kubernetes.default.svc"
  cluster_ca_certificate = file("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")
  token                  = file("/var/run/secrets/kubernetes.io/serviceaccount/token")
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
# Terraform only reads it to ensure secrets are placed in the correct namespace.

data "kubernetes_namespace" "airflow" {
  metadata {
    name = var.namespace
  }
}


# ── Airflow secrets ───────────────────────────────────────────────────────────
# These are mounted into the Airflow pods via extraEnvFrom / extraEnv in the
# Helm values file (helm/airflow.yaml).

# ── Airflow secrets ───────────────────────────────────────────────────────────
# kubernetes_manifest uses server-side apply (upsert) so re-runs never fail
# with "already exists", even when Terraform state is reset.

resource "kubernetes_manifest" "airflow" {
  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "airflow-secrets"
      namespace = var.namespace
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/name"       = "airflow"
      }
    }
    stringData = {
      fernet-key        = base64encode(random_password.fernet_key.result)
      webserver-secret  = random_password.webserver_secret_key.result
      postgres-password = random_password.postgres_password.result
      connection-string = "postgresql+psycopg2://airflow:${random_password.postgres_password.result}@airflow-postgresql:5432/airflow"
    }
  }

  field_manager {
    force_conflicts = true
  }
}

# ── PostgreSQL secret (used by the embedded Bitnami PostgreSQL sub-chart) ─────

resource "kubernetes_manifest" "postgresql" {
  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "airflow-postgresql"
      namespace = var.namespace
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/name"       = "airflow-postgresql"
      }
    }
    stringData = {
      postgres-password   = random_password.postgres_password.result
      password            = random_password.postgres_password.result
      # Key used by the Bitnami sub-chart in airflow-helm 8.9.0 to initialise
      # the postgres superuser AND the custom airflow user at first boot.
      postgresql-password = random_password.postgres_password.result
    }
  }

  field_manager {
    force_conflicts = true
  }
}


