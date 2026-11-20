#!/usr/bin/env bash
# รันบน k8s-control จากโฟลเดอร์ k8s-037
# build image ด้วย podman แล้วส่งไปนำเข้า containerd บน k8s-worker1
set -euo pipefail

WORKER1="${WORKER1:-user01@172.25.1.181}"
TAG="037"
APPS=(app-research app-api)

cd "$(dirname "$0")/.."

for app in "${APPS[@]}"; do
  echo "==> build localhost/${app}:${TAG}"
  podman build -t "localhost/${app}:${TAG}" -f "apps/${app}/Containerfile" "apps/${app}"
  podman save --format docker-archive -o "/tmp/${app}.tar" "localhost/${app}:${TAG}"
done

echo "==> คัดลอกไฟล์ image ไปที่ ${WORKER1}"
scp /tmp/app-research.tar /tmp/app-api.tar "${WORKER1}:/tmp/"

echo "==> นำเข้า image เข้า containerd (namespace k8s.io) บน worker1 (จะถามรหัส sudo)"
ssh -t "${WORKER1}" '
  sudo ctr -n k8s.io images import /tmp/app-research.tar &&
  sudo ctr -n k8s.io images import /tmp/app-api.tar &&
  sudo crictl images | grep -E "localhost/app-(research|api)"
'
