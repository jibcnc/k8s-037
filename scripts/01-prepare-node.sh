#!/usr/bin/env bash
# รันบน k8s-control, k8s-worker1, k8s-worker2 (ทุกเครื่องในคลัสเตอร์)
# ใช้งาน: sudo bash scripts/01-prepare-node.sh
set -euo pipefail

K8S_MINOR="v1.35"   # ingress-nginx v1.15.1 (เวอร์ชันสุดท้าย) รองรับ Kubernetes ได้ถึง 1.35

if [[ $EUID -ne 0 ]]; then echo "กรุณารันด้วย sudo"; exit 1; fi

echo "==> [1/6] ปิด swap"
swapoff -a
sed -ri '/\sswap\s/ s/^([^#])/#\1/' /etc/fstab

echo "==> [2/6] โหลด kernel module overlay และ br_netfilter"
cat <<MODS > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
MODS
modprobe overlay
modprobe br_netfilter

echo "==> [3/6] ตั้งค่า sysctl"
cat <<SYSCTL > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
SYSCTL
sysctl --system >/dev/null

echo "==> [4/6] ติดตั้งและตั้งค่า containerd (SystemdCgroup = true)"
apt-get update
apt-get install -y containerd apt-transport-https ca-certificates curl gpg
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
if ! grep -q 'SystemdCgroup = true' /etc/containerd/config.toml; then
  echo "!! ไม่พบ SystemdCgroup = true ใน /etc/containerd/config.toml กรุณาตรวจสอบเอง"; exit 1
fi
systemctl restart containerd
systemctl enable containerd

echo "==> [5/6] ติดตั้ง kubeadm kubelet kubectl ${K8S_MINOR}"
install -d -m 0755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet

echo "==> [6/6] ตั้งค่า crictl ให้ใช้ containerd"
cat <<CRICTL > /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
CRICTL

echo "==> ตรวจสอบ"
swapon --show || true
lsmod | grep -E '^(overlay|br_netfilter)'
sysctl net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables
containerd --version
kubeadm version -o short
echo "==> เสร็จแล้ว"
