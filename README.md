# K8s Ingress Assignment — ID-037

ให้บริการเว็บ 4 บริการบน Kubernetes ผ่าน NGINX Ingress Controller และ External Load Balancer

| URL | Service | App | หน้าที่ |
|---|---|---|---|
| `http://www.id-037.com/` | `svc-about` | app-about | หน้ารวมบริการ (Dashboard) |
| `http://www.id-037.com/about` | `svc-about` | app-about (nginx + ConfigMap) | แสดงรูป ชื่อ และรหัสนักศึกษา |
| `http://www.id-037.com/research` | `svc-research` | app-research (Flask + PVC) | สรุปงานวิจัย 300–500 คำ |
| `http://www.id-037.com/api/<ข้อความ>` | `svc-api` | app-api (Flask) | แสดง `<ข้อความ>` ตัวใหญ่กลางจอ |
| `http://admin.id-037.com/edit` | `svc-research` | app-research (path `/edit`) | แก้ไขและบันทึกสรุปงานวิจัยลง PVC |

## สถาปัตยกรรม

```
Client (hosts: www/admin.id-037.com -> 172.25.1.183)
        |
        v  :80
External-LB 172.25.1.183 (NGINX)
        |  round-robin
        v
k8s-worker1 172.25.1.181:31080   k8s-worker2 172.25.1.182:31080   (NodePort)
        |
        v
ingress-nginx controller  --(host + path)-->  svc-about / svc-research / svc-api
                                                   |            |            |
                                               app-about   app-research   app-api
                                               (x2 pods)   (x2, worker1)  (x2, worker1)
                                                              |
                                                       PVC research-pvc-037
                                                       PV  hostPath /var/lib/k8s-037/research (worker1)
k8s-control 172.25.1.180 (control plane)
```

## เวอร์ชันที่ใช้

| ส่วนประกอบ | เวอร์ชัน | เหตุผล |
|---|---|---|
| Ubuntu Server | 24.04 LTS หรือ 26.04 LTS | คำสั่งเหมือนกันทั้ง 2 เวอร์ชัน |
| Kubernetes (kubeadm/kubelet/kubectl) | **v1.35** | ingress-nginx v1.15.1 (เวอร์ชันสุดท้าย) รองรับ K8s 1.31–1.35 |
| Container runtime | containerd จาก repo ของ Ubuntu | ตั้งค่า `SystemdCgroup = true` |
| CNI (ระบบเครือข่ายของ Pod) | Flannel | ใช้วง Pod `10.244.0.0/16` |
| Ingress controller | ingress-nginx (Helm chart 4.15.1 / controller v1.15.1) | NodePort 31080 (HTTP) / 31502 (HTTPS) |

> หมายเหตุ: ingress-nginx ถูกปลดระวาง (retired) ตั้งแต่มีนาคม 2026 จึงไม่มีอัปเดตความปลอดภัยแล้ว แต่ chart และ image ยังดาวน์โหลดได้ จึงใช้กับ lab ได้ แต่ไม่ควรใช้ใน production

## โครงสร้างไฟล์

```
k8s-037/
├── README.md
├── deploy.sh                         # สร้าง ConfigMap + apply manifest ทั้งหมด
├── apps/
│   ├── app-about/                    # nginx เสิร์ฟไฟล์จาก ConfigMap
│   │   ├── index.html                # หน้ารวมบริการ
│   │   └── about/{index.html, profile.png}
│   ├── app-api/                      # Flask + gunicorn
│   │   ├── app.py, requirements.txt, Containerfile
│   │   └── templates/index.html
│   └── app-research/                 # Flask + gunicorn + PVC
│       ├── app.py, requirements.txt, Containerfile, default-research.txt
│       ├── static/research-architecture.png
│       └── templates/{research.html, edit.html}
├── k8s/
│   ├── 00-namespace.yaml
│   ├── 01-storage.yaml               # PV (hostPath บน worker1) + PVC
│   ├── 02-app-about-configmap.yaml   # deploy.sh สร้างให้อัตโนมัติ
│   ├── 02-app-about-deployment.yaml
│   ├── 03-app-research.yaml
│   ├── 04-app-api.yaml
│   └── 05-ingress.yaml
├── lb/k8s-lb.conf                    # config ของ NGINX บน External-LB
├── client/hosts-linux.txt, hosts-windows.txt
└── scripts/
    ├── 01-prepare-node.sh            # เตรียม OS + containerd + kubeadm (3 เครื่องใน cluster)
    ├── build-and-load-images.sh      # build image แล้วนำเข้าไปที่ worker1
    └── verify.sh                     # รวมคำสั่งตรวจสอบไว้ใช้แคปหน้าจอ
```

---

# ขั้นตอนทั้งหมด

| Phase | งาน | เครื่อง |
|---|---|---|
| 0 | ติดตั้ง Ubuntu, ตั้ง IP, hostname, `/etc/hosts` | ทั้ง 4 เครื่อง |
| 1 | เตรียม OS + containerd + kubeadm | control, worker1, worker2 |
| 2 | `kubeadm init` + Flannel | control |
| 3 | `kubeadm join` | worker1, worker2 |
| 4 | ติดตั้ง ingress-nginx (NodePort) | control |
| 5 | ตั้งค่า NGINX Load Balancer | External-LB |
| 6 | แก้เนื้อหาเว็บ + build image + นำเข้า worker1 | control → worker1 |
| 7 | Deploy | control |
| 8 | ตรวจสอบด้วย kubectl | control |
| 9 | ทดสอบผ่านเบราว์เซอร์ + push GitHub | Client |

## Phase 0 — ติดตั้ง Ubuntu (ทั้ง 4 เครื่อง)

| เครื่อง | IP | CPU / RAM / Disk ขั้นต่ำ |
|---|---|---|
| k8s-control | 172.25.1.180 | 2 vCPU / 4 GB / 30 GB |
| k8s-worker1 | 172.25.1.181 | 2 vCPU / 4 GB / 30 GB |
| k8s-worker2 | 172.25.1.182 | 2 vCPU / 2 GB / 30 GB |
| External-LB | 172.25.1.183 | 1 vCPU / 1 GB / 20 GB |

ตอนติดตั้ง Ubuntu Server ให้ติ๊ก **Install OpenSSH server**, สร้าง user `user01` ให้เหมือนกันทุกเครื่อง และไม่ต้องเลือก snap เสริม (เช่น docker หรือ microk8s) ในหน้าติดตั้ง

> ⚠️ ถ้า clone VM มา ต้องให้ MAC address และ `product_uuid` ไม่ซ้ำกัน (ตรวจด้วย `ip link` และ `sudo cat /sys/class/dmi/id/product_uuid`)

### 0.1 ตั้ง IP แบบคงที่ (static IP)

```bash
ip -br a                 # ดูชื่อการ์ดเครือข่าย เช่น ens33, ens160
ls /etc/netplan/         # ดูชื่อไฟล์ netplan เช่น 50-cloud-init.yaml
```

ปิดไม่ให้ cloud-init เขียนทับค่า network ตอนรีบูต:
```bash
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
```

แก้ไฟล์ netplan (ตัวอย่างของ k8s-control; เครื่องอื่นเปลี่ยนแค่ IP):
```bash
sudo nano /etc/netplan/50-cloud-init.yaml
```
```yaml
network:
  version: 2
  ethernets:
    ens33:                        # ให้ตรงกับชื่อการ์ดจาก ip -br a
      dhcp4: false
      addresses:
        - 172.25.1.180/24
      routes:
        - to: default
          via: 172.25.1.1         # ⚠️ เปลี่ยนเป็น gateway จริงของวง 172.25.1.0/24
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
```
```bash
sudo chmod 600 /etc/netplan/*.yaml
sudo netplan apply
ip -br a && ping -c 2 8.8.8.8
```

### 0.2 ตั้ง hostname และ `/etc/hosts`

```bash
# ใช้ชื่อตามแต่ละเครื่อง: k8s-control / k8s-worker1 / k8s-worker2 / External-LB
sudo hostnamectl set-hostname k8s-control

sudo tee -a /etc/hosts <<'EOF'
172.25.1.180 k8s-control
172.25.1.181 k8s-worker1
172.25.1.182 k8s-worker2
172.25.1.183 External-LB
EOF

sudo timedatectl set-timezone Asia/Bangkok
sudo apt update && sudo apt -y full-upgrade
sudo reboot
```

> ชื่อ `k8s-worker1` ต้องเป็นตัวพิมพ์เล็กตามนี้เป๊ะ เพราะ PV และ Deployment ใช้ label `kubernetes.io/hostname: k8s-worker1`

### 0.3 คัดลอกโปรเจกต์ไปไว้ที่ k8s-control

จากเครื่องที่ดาวน์โหลดไฟล์ zip มา:
```bash
scp k8s-037.zip user01@172.25.1.180:~
ssh user01@172.25.1.180
sudo apt install -y unzip && unzip k8s-037.zip && cd ~/k8s-037
```
แล้วคัดลอก `scripts/01-prepare-node.sh` ไปที่ worker ทั้ง 2 เครื่อง:
```bash
scp scripts/01-prepare-node.sh user01@172.25.1.181:~
scp scripts/01-prepare-node.sh user01@172.25.1.182:~
```

## Phase 1 — เตรียม OS + containerd + kubeadm (control, worker1, worker2)

รันสคริปต์ที่รวมทุกขั้นตอนไว้:
```bash
sudo bash ~/k8s-037/scripts/01-prepare-node.sh     # บน control
sudo bash ~/01-prepare-node.sh                     # บน worker1, worker2
```

สคริปต์นี้ทำงานตามลำดับเดียวกับคำสั่งด้านล่าง (ถ้าอยากพิมพ์เองทีละคำสั่งเพื่อแคปลงรายงาน):

```bash
# 1) ปิด swap (kubelet จะไม่ทำงานถ้า swap เปิดอยู่)
sudo swapoff -a
sudo sed -ri '/\sswap\s/ s/^([^#])/#\1/' /etc/fstab

# 2) โหลด kernel module
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# 3) ตั้งค่า sysctl ให้ส่งต่อแพ็กเก็ต (IP forwarding)
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# 4) containerd
sudo apt-get update
sudo apt-get install -y containerd apt-transport-https ca-certificates curl gpg
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
grep -n 'SystemdCgroup' /etc/containerd/config.toml        # ต้องเป็น = true
sudo systemctl restart containerd
sudo systemctl enable containerd

# 5) kubeadm / kubelet / kubectl v1.35
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet

# 6) ให้ crictl ใช้ containerd
printf 'runtime-endpoint: unix:///run/containerd/containerd.sock\nimage-endpoint: unix:///run/containerd/containerd.sock\n' | sudo tee /etc/crictl.yaml
```

ตรวจสอบ:
```bash
swapon --show                      # ต้องไม่มีผลลัพธ์
sysctl net.ipv4.ip_forward         # = 1
kubeadm version -o short           # v1.35.x
systemctl is-active containerd     # active
```

> ณ จุดนี้ `kubelet` จะ restart วนอยู่ ซึ่งเป็นปกติ เพราะยังไม่ได้รัน `kubeadm init`/`join`
> 💡 ควร snapshot VM ทั้ง 3 เครื่องไว้ตรงนี้

## Phase 2 — สร้าง Cluster (k8s-control เท่านั้น)

```bash
sudo kubeadm init \
  --apiserver-advertise-address=172.25.1.180 \
  --pod-network-cidr=10.244.0.0/16

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Flannel (ค่าเริ่มต้นใช้วง 10.244.0.0/16 ตรงกับ --pod-network-cidr)
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

kubectl get pods -n kube-flannel
kubectl get pods -n kube-system      # รอจน coredns เป็น Running
kubectl get nodes                    # k8s-control ต้องเป็น Ready
```

📝 คัดลอกคำสั่ง `kubeadm join ...` ที่แสดงตอนท้ายของ `kubeadm init` เก็บไว้ ถ้าทำหายให้สร้างใหม่ด้วย:
```bash
kubeadm token create --print-join-command
```

## Phase 3 — Join Worker (worker1 และ worker2)

```bash
sudo kubeadm join 172.25.1.180:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

ตรวจสอบบน control:
```bash
kubectl get nodes -o wide
```
ต้องได้ 3 node ที่เป็น `Ready` และ INTERNAL-IP เป็น 172.25.1.180/181/182

## Phase 4 — ติดตั้ง ingress-nginx แบบ NodePort (k8s-control)

```bash
sudo snap install helm --classic

helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --version 4.15.1 \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=31080 \
  --set controller.service.nodePorts.https=31502

kubectl get pods,svc -n ingress-nginx -o wide
kubectl get ingressclass
```
ผลที่ต้องได้: `ingress-nginx-controller` เป็น `Running`, Service แสดง `80:31080/TCP,443:31502/TCP` และมี IngressClass ชื่อ `nginx`

## Phase 5 — External-LB (172.25.1.183)

```bash
sudo apt install -y nginx
sudo rm -f /etc/nginx/sites-enabled/default
sudo nano /etc/nginx/conf.d/k8s-lb.conf      # วางเนื้อหาจาก lb/k8s-lb.conf
sudo nginx -t
sudo systemctl reload nginx
```

`lb/k8s-lb.conf`:
```nginx
upstream k8s_backend {
    server 172.25.1.181:31080 max_fails=3 fail_timeout=10s;
    server 172.25.1.182:31080 max_fails=3 fail_timeout=10s;
}

server {
    listen 80;
    server_name www.id-037.com admin.id-037.com;

    access_log /var/log/nginx/k8s-lb-access.log;
    error_log  /var/log/nginx/k8s-lb-error.log;

    location / {
        proxy_pass http://k8s_backend;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 3s;
        proxy_read_timeout    30s;
    }
}
```
> `proxy_set_header Host $host` จำเป็นมาก เพราะ Ingress ใช้ชื่อ Host ในการเลือกว่าจะส่งไป www หรือ admin

## Phase 6 — แก้เนื้อหาเว็บ + Build Image

### 6.1 แก้เนื้อหาให้เป็นของตัวเอง (k8s-control)

| ไฟล์ | สิ่งที่ต้องแก้ |
|---|---|
| `apps/app-about/about/index.html` | ชื่อ-นามสกุล และรหัสนักศึกษา |
| `apps/app-about/about/profile.png` | แทนด้วยรูปตัวเอง ชื่อไฟล์เดิม ขนาดไม่เกิน ~500 KB (ConfigMap จำกัด 1 MiB) |
| `apps/app-research/default-research.txt` | สรุปงานวิจัย 300–500 คำ (หรือแก้ภายหลังผ่าน `admin.id-037.com/edit`) |
| `apps/app-research/static/research-architecture.png` | รูปสถาปัตยกรรมงานวิจัย |

### 6.2 สร้างโฟลเดอร์สำหรับ PV (k8s-worker1)

```bash
sudo mkdir -p /var/lib/k8s-037/research
sudo chmod 777 /var/lib/k8s-037/research
```
> PV ใช้ `hostPath type: Directory` ซึ่งจะไม่สร้างโฟลเดอร์ให้เอง ถ้าไม่มีโฟลเดอร์นี้ Pod จะค้างที่ `ContainerCreating`

### 6.3 Build image และนำเข้าไปที่ worker1 (k8s-control)

```bash
sudo apt install -y podman
cd ~/k8s-037
./scripts/build-and-load-images.sh
```
สคริปต์จะ:
1. `podman build` → `localhost/app-research:037` และ `localhost/app-api:037`
2. `podman save --format docker-archive` → `/tmp/*.tar`
3. `scp` ไปที่ `user01@172.25.1.181:/tmp/`
4. `ssh` ไปรัน `sudo ctr -n k8s.io images import ...` บน worker1 (จะถามรหัส sudo ของ worker1)

ตรวจสอบบน worker1:
```bash
sudo crictl images | grep localhost
```
ต้องเห็น `localhost/app-research  037` และ `localhost/app-api  037`

> Deployment ตั้ง `imagePullPolicy: Never` และ `nodeSelector: k8s-worker1` ไว้ เพราะ image มีอยู่แค่บน worker1 และไม่มี registry ให้ดึง

## Phase 7 — Deploy (k8s-control)

```bash
cd ~/k8s-037
./deploy.sh
```
`deploy.sh` ทำงานตามลำดับนี้:
```bash
kubectl create configmap app-about-files -n id-037 \
  --from-file=index.html=apps/app-about/index.html \
  --from-file=about-index.html=apps/app-about/about/index.html \
  --from-file=profile.png=apps/app-about/about/profile.png \
  --dry-run=client -o yaml > k8s/02-app-about-configmap.yaml

kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-storage.yaml
kubectl apply -f k8s/02-app-about-configmap.yaml
kubectl apply -f k8s/02-app-about-deployment.yaml
kubectl apply -f k8s/03-app-research.yaml
kubectl apply -f k8s/04-app-api.yaml
kubectl apply -f k8s/05-ingress.yaml
kubectl rollout status deployment/app-about    -n id-037
kubectl rollout status deployment/app-research -n id-037
kubectl rollout status deployment/app-api      -n id-037
```

> ถ้าแก้เนื้อหา HTML หรือรูปแล้ว ให้รัน `./deploy.sh` ใหม่ แล้วตามด้วย `kubectl rollout restart deployment/app-about -n id-037`
> ถ้าแก้โค้ด Flask ให้รัน `./scripts/build-and-load-images.sh` ใหม่ แล้วตามด้วย `kubectl rollout restart deployment/app-research deployment/app-api -n id-037`

## Phase 8 — ตรวจสอบด้วย kubectl (แคปหน้าจอใส่รายงาน)

```bash
./scripts/verify.sh
```
หรือรันทีละคำสั่ง:
```bash
kubectl get nodes -o wide
kubectl get pods,svc -n ingress-nginx -o wide
kubectl get all -n id-037 -o wide
kubectl get ingress -n id-037
kubectl describe ingress app-ingress -n id-037       # ดูกฎ Host/Path -> Service
kubectl get pv research-pv-037
kubectl get pvc -n id-037                             # STATUS ต้องเป็น Bound
kubectl describe pvc research-pvc-037 -n id-037       # Used By: ต้องเห็น Pod ของ app-research
kubectl describe pod -l app=app-research -n id-037    # Mounts: /data from research-data
kubectl get endpointslices -n id-037                  # ทุก Service ต้องมี IP ของ Pod

# ทดสอบตรงที่ NodePort (ไม่ผ่าน LB)
curl -H "Host: www.id-037.com"   http://172.25.1.181:31080/api/test
curl -H "Host: admin.id-037.com" http://172.25.1.182:31080/edit
# ทดสอบผ่าน LB
curl -H "Host: www.id-037.com"   http://172.25.1.183/about/
```

## Phase 9 — ทดสอบผ่านเบราว์เซอร์ + ส่งงาน

### 9.1 ไฟล์ hosts ของเครื่อง Client

Linux (`/etc/hosts`):
```bash
echo '172.25.1.183  www.id-037.com admin.id-037.com' | sudo tee -a /etc/hosts
```
Windows: เปิด Notepad ด้วย **Run as administrator** แล้วแก้ `C:\Windows\System32\drivers\etc\hosts` โดยเพิ่มบรรทัดนี้
```
172.25.1.183  www.id-037.com admin.id-037.com
```
ตรวจสอบด้วย PowerShell:
```powershell
Select-String -Path C:\Windows\System32\drivers\etc\hosts -Pattern "id-037"
ipconfig /flushdns
```

### 9.2 รายการแคปหน้าจอสำหรับไฟล์ทดสอบ

| # | URL | สิ่งที่ต้องเห็น |
|---|---|---|
| 1 | `http://www.id-037.com/` | หน้ารวมบริการ 4 บริการ |
| 2 | `http://www.id-037.com/about/` | รูป ชื่อ และรหัสนักศึกษา |
| 3 | `http://www.id-037.com/research` | สรุปงานวิจัยและรูปสถาปัตยกรรม |
| 4 | `http://www.id-037.com/api/Hello-Kubernetes-037` | ข้อความตัวใหญ่กลางจอ |
| 5 | `http://admin.id-037.com/edit` | หน้าแก้ไขข้อมูล |
| 6 | แก้ข้อความ → กด Save | ข้อความ "บันทึกเรียบร้อย" |
| 7 | เปิด `/research` อีกครั้ง | เห็นข้อความใหม่ |
| 8 | `kubectl delete pod -l app=app-research -n id-037` แล้วเปิด `/research` | ข้อความยังอยู่ (พิสูจน์ว่าข้อมูลเก็บใน PV จริง) |

### 9.3 Push ขึ้น GitHub (repo แบบ public)

สร้าง repo ชื่อ `k8s-037` บน GitHub แบบ **Public** โดยไม่ต้องสร้าง README ไว้ก่อน แล้วรัน:
```bash
cd ~/k8s-037
git init
git add .
git commit -m "K8s Ingress assignment ID-037"
git branch -M main
git remote add origin https://github.com/<github-username>/k8s-037.git
git push -u origin main
```
> ตอน push ระบบจะถามรหัสผ่าน ให้ใช้ Personal Access Token (GitHub → Settings → Developer settings) แทนรหัสผ่านบัญชี

---

## ปัญหาที่พบบ่อย

| อาการ | สาเหตุ / วิธีแก้ |
|---|---|
| `kubeadm init` แจ้ง swap | ยังไม่ได้ปิด swap → `sudo swapoff -a` และตรวจ `/etc/fstab` |
| Node เป็น `NotReady` | Flannel ยังไม่ Running → `kubectl get pods -n kube-flannel` และตรวจว่าโหลด `br_netfilter` แล้ว |
| Pod ของ Flannel/CoreDNS `CrashLoopBackOff` ใน VM ที่มี 2 การ์ดเครือข่าย | Flannel หรือ kubelet เลือกการ์ดผิดใบ → ใส่ `KUBELET_EXTRA_ARGS=--node-ip=<IP ของเครื่อง>` ใน `/etc/default/kubelet` แล้ว `sudo systemctl restart kubelet` |
| Pod restart วนตลอดหลังติดตั้ง | containerd ยังไม่ได้ตั้ง `SystemdCgroup = true` |
| `ErrImageNeverPull` | ยังไม่ได้นำ image เข้า worker1 หรือชื่อไม่ตรงกับ `crictl images` |
| app-research ค้างที่ `ContainerCreating` | ยังไม่มีโฟลเดอร์ `/var/lib/k8s-037/research` บน worker1 → `kubectl describe pod` จะเห็น `hostPath type check failed` |
| PVC ค้างที่ `Pending` | ยังไม่ได้ apply `01-storage.yaml` หรือชื่อ/StorageClass ไม่ตรงกัน |
| เปิดเว็บได้ `404 Not Found` จาก nginx | ชื่อ Host ไม่ตรงกับ Ingress หรือ LB ไม่ได้ส่ง `Host $host` ไปด้วย |
| เปิดเว็บได้ `502 Bad Gateway` จาก LB | NodePort 31080 ยังไม่ตอบ → `kubectl get svc -n ingress-nginx` |
| กด Save แล้วได้ `500` | โฟลเดอร์ PV เขียนไม่ได้ → `sudo chmod 777 /var/lib/k8s-037/research` บน worker1 |

## รื้อระบบเพื่อเริ่มใหม่

```bash
kubectl delete namespace id-037
kubectl delete pv research-pv-037
helm uninstall ingress-nginx -n ingress-nginx
# รื้อทั้ง cluster (ทุก node):
sudo kubeadm reset -f && sudo rm -rf /etc/cni/net.d $HOME/.kube
```
