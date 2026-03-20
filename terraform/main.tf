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

# ── Namespace ─────────────────────────────────────────────────────────────────
# The namespace is created by Plural's ServiceDeployment (createNamespace: true).
# Terraform only reads it to ensure secrets are placed in the correct namespace.

data "kubernetes_namespace" "airflow" {
  metadata {
    name = var.namespace
  }
}

# ── Airflow secrets ───────────────────────────────────────────────────────────
# kubernetes_manifest uses server-side apply (upsert) so re-runs never fail
# with "already exists", even when Terraform state is reset.
# PostgreSQL password is fixed ("airflow") and matches postgresql.auth.password
# in helm/airflow.yaml so there is no race condition between Terraform and
# Bitnami's first-boot initialisation.

resource "kubernetes_manifest" "airflow" {
  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    type       = "Opaque"
    metadata = {
      name      = "airflow-secrets"
      namespace = var.namespace
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/name"       = "airflow"
      }
    }
    # data values must be base64-encoded (kubernetes_manifest sends the manifest verbatim)
    data = {
      fernet-key        = base64encode(base64encode(random_password.fernet_key.result))
      webserver-secret  = base64encode(random_password.webserver_secret_key.result)
      connection-string = base64encode("postgresql+psycopg2://airflow:airflow@airflow-postgresql:5432/airflow")
    }
  }

  field_manager {
    force_conflicts = true
  }
}
