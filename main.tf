terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.37"
    }
    mysql = {
      source  = "petoju/mysql"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

provider "kubectl" {
  config_path = "~/.kube/config"
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "mysql" {
  endpoint = "192.168.64.101:3306"
  username = "root"
  password = random_string.mariadb-root-password.result
}

provider "random" {}

resource "kubernetes_namespace" "flannel" {
  metadata {
    name = "flannel"
  }
}

resource "helm_release" "flannel" {
  name       = "flannel"
  repository = "https://flannel-io.github.io/flannel"
  chart      = "flannel"
  namespace  = kubernetes_namespace.flannel.metadata[0].name
  values     = [file("${path.module}/flannel-values.yaml")]

  depends_on = [kubernetes_namespace.flannel]
}

resource "kubernetes_namespace" "certmgr" {
  metadata {
    name = "certmgr"
  }
}

resource "helm_release" "cert-manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = kubernetes_namespace.certmgr.metadata[0].name
  values     = [file("${path.module}/cert-manager-values.yaml")]

  depends_on = [
    helm_release.flannel,
    kubernetes_namespace.certmgr,
  ]
}

resource "kubectl_manifest" "cert-manager-self-signed-issuer" {
  yaml_body = file("cert-manager-self-signed-issuer.yaml")

  depends_on = [helm_release.cert-manager]
}

resource "kubectl_manifest" "cert-manager-ca-cert" {
  yaml_body = file("cert-manager-ca-cert.yaml")

  depends_on = [
    helm_release.cert-manager,
    kubectl_manifest.cert-manager-self-signed-issuer,
  ]
}

resource "kubectl_manifest" "cert-manager-cluster-issuer" {
  yaml_body = file("cert-manager-cluster-issuer.yaml")

  depends_on = [
    helm_release.cert-manager,
    kubectl_manifest.cert-manager-ca-cert,
  ]
}

resource "kubernetes_namespace" "localpv" {
  metadata {
    name = "localpv"
  }
}

resource "helm_release" "localpv-provisioner" {
  name       = "localpv-provisioner"
  repository = "https://openebs.github.io/dynamic-localpv-provisioner"
  chart      = "localpv-provisioner"
  namespace  = kubernetes_namespace.localpv.metadata[0].name
  values     = [file("${path.module}/localpv-provisioner-values.yaml")]

  depends_on = [
    helm_release.flannel,
    kubernetes_namespace.localpv,
  ]
}

resource "kubernetes_namespace" "metallb" {
  metadata {
    name = "metallb"
  }
}

resource "helm_release" "metallb" {
  name       = "metallb"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  namespace  = kubernetes_namespace.metallb.metadata[0].name
  values     = [file("${path.module}/metallb-values.yaml")]

  depends_on = [
    helm_release.flannel,
    kubernetes_namespace.metallb,
  ]
}

resource "kubectl_manifest" "metallb-ip-address-pool" {
  yaml_body = file("metallb-ip-address-pool.yaml")

  depends_on = [helm_release.metallb]
}

resource "kubectl_manifest" "metallb-l2-advertisement" {
  yaml_body = file("metallb-l2-advertisement.yaml")

  depends_on = [helm_release.metallb]
}

resource "kubernetes_namespace" "metrics" {
  metadata {
    name = "metrics"
  }
}

resource "helm_release" "metrics-server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  namespace  = kubernetes_namespace.metrics.metadata[0].name
  values     = [file("${path.module}/metrics-server-values.yaml")]

  depends_on = [
    helm_release.flannel,
    kubernetes_namespace.metrics,
  ]
}

resource "kubernetes_namespace" "ingress" {
  metadata {
    name = "ingress"
  }
}
resource "helm_release" "ingress-nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = kubernetes_namespace.ingress.metadata[0].name
  values     = [file("${path.module}/ingress-nginx-values.yaml")]

  depends_on = [
    helm_release.cert-manager,
    helm_release.metallb,
    kubernetes_namespace.ingress,
  ]
}

resource "kubernetes_namespace" "mariadb" {
  metadata {
    name = "mariadb"
  }
}

resource "random_string" "mariadb-root-password" {
  length  = 32
  special = false
  upper   = true
  lower   = true
  numeric = true
}

resource "kubernetes_secret" "mariadb-credentials-mariadb" {
  metadata {
    name      = "mariadb-credentials"
    namespace = kubernetes_namespace.mariadb.metadata[0].name
  }
  type = "Opaque"
  data = {
    "mariadb-root-password" = random_string.mariadb-root-password.result
  }
}

resource "kubernetes_secret" "mariadb-credentials-grafana" {
  metadata {
    name      = "mariadb-credentials"
    namespace = kubernetes_namespace.grafana.metadata[0].name
  }
  type = "Opaque"
  data = {
    "mariadb-grafana-password" = random_string.mariadb-grafana-password.result
  }
}

resource "helm_release" "mariadb" {
  name       = "mariadb"
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart      = "mariadb"
  namespace  = kubernetes_namespace.mariadb.metadata[0].name
  values     = [file("${path.module}/mariadb-values.yaml")]
  set {
    name  = "auth.existingSecret"
    value = kubernetes_secret.mariadb-credentials-mariadb.metadata[0].name
  }

  depends_on = [
    helm_release.flannel,
    helm_release.localpv-provisioner,
    helm_release.metallb,
    kubernetes_namespace.mariadb,
  ]
}

resource "mysql_database" "grafana" {
  name = "grafana"

  depends_on = [helm_release.mariadb, ]
}

resource "random_string" "mariadb-grafana-password" {
  length  = 32
  special = false
  upper   = true
  lower   = true
  numeric = true
}

resource "mysql_user" "grafana" {
  user               = "grafana"
  host               = "%"
  plaintext_password = random_string.mariadb-grafana-password.result

  depends_on = [helm_release.mariadb]
}

resource "mysql_grant" "grafana" {
  user       = mysql_user.grafana.user
  host       = "%"
  database   = mysql_database.grafana.name
  privileges = ["ALL"]

  depends_on = [
    helm_release.mariadb,
    mysql_database.grafana,
    mysql_user.grafana,
  ]
}

resource "kubernetes_namespace" "grafana" {
  metadata {
    name = "grafana"
  }
}

resource "random_string" "grafana-password" {
  length  = 32
  special = false
  upper   = true
  lower   = true
  numeric = true
}

output "grafana-password" {
  value = random_string.grafana-password.result
}

resource "kubernetes_secret" "grafana-credentials" {
  metadata {
    name      = "grafana-credentials"
    namespace = kubernetes_namespace.grafana.metadata[0].name
  }
  type = "Opaque"
  data = {
    "admin-user"     = "admin"
    "admin-password" = random_string.grafana-password.result
  }
}

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = kubernetes_namespace.grafana.metadata[0].name
  values     = [file("${path.module}/grafana-values.yaml")]
  set {
    name  = "admin.existingSecret"
    value = kubernetes_secret.grafana-credentials.metadata[0].name
  }

  depends_on = [
    helm_release.ingress-nginx,
    helm_release.mariadb,
    mysql_grant.grafana,
    kubernetes_namespace.grafana,
  ]
}

resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  namespace  = kubernetes_namespace.grafana.metadata[0].name
  values     = [file("${path.module}/loki-values.yaml")]

  depends_on = [
    helm_release.flannel,
    helm_release.localpv-provisioner,
    kubernetes_namespace.grafana,
  ]
}

resource "kubernetes_namespace" "fluent-bit" {
  metadata {
    name = "fluent-bit"
  }
}

resource "helm_release" "fluent-bit" {
  name       = "fluent-bit"
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  namespace  = kubernetes_namespace.fluent-bit.metadata[0].name
  values     = [file("${path.module}/fluent-bit-values.yaml")]

  depends_on = [
    helm_release.flannel,
    kubernetes_namespace.fluent-bit,
  ]
}
