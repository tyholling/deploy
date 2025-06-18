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

resource "kubernetes_namespace" "grafana" {
  metadata {
    name = "grafana"
  }
}

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = kubernetes_namespace.grafana.metadata[0].name
  values     = [file("${path.module}/grafana-values.yaml")]

  depends_on = [
    helm_release.ingress-nginx,
    helm_release.localpv-provisioner,
    kubernetes_namespace.grafana,
  ]
}
