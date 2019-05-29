#!/usr/bin/env bash


kubectl apply -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.6/deploy/manifests/00-crds.yaml
helm install stable/cert-manager \
  --name cert-manager \
  --namespace kube-system
kubectl apply -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.6/deploy/manifests/cert-manager.yaml
kubectl -n kube-system rollout status deploy/cert-manager
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update

helm install rancher-stable/rancher \
  --name rancher \
  --namespace cattle-system \
  --set hostname=rancher.ericom.com

kubectl -n cattle-system rollout status deploy/rancher


helm upgrade --install cert-manager stable/cert-manager --reuse-values --set webhook.enabled=true



