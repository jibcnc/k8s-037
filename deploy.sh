#!/usr/bin/env bash
# รันบน k8s-control จากโฟลเดอร์ k8s-037
set -euo pipefail
cd "$(dirname "$0")"
NS="id-037"

echo "==> สร้างไฟล์ ConfigMap ของ app-about จากไฟล์ HTML และรูป"
kubectl create configmap app-about-files -n "${NS}" \
  --from-file=index.html=apps/app-about/index.html \
  --from-file=about-index.html=apps/app-about/about/index.html \
  --from-file=profile.png=apps/app-about/about/profile.png \
  --dry-run=client -o yaml > k8s/02-app-about-configmap.yaml

echo "==> apply manifests"
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-storage.yaml
kubectl apply -f k8s/02-app-about-configmap.yaml
kubectl apply -f k8s/02-app-about-deployment.yaml
kubectl apply -f k8s/03-app-research.yaml
kubectl apply -f k8s/04-app-api.yaml
kubectl apply -f k8s/05-ingress.yaml

echo "==> รอให้ Deployment พร้อม"
for d in app-about app-research app-api; do
  kubectl rollout status deployment/"${d}" -n "${NS}" --timeout=180s
done

kubectl get all,ingress,pvc -n "${NS}" -o wide
