#!/usr/bin/env bash
# รันบน k8s-control เพื่อแสดงผลการตรวจสอบ (ใช้แคปหน้าจอใส่รายงาน)
set -uo pipefail
NS="id-037"
run() { echo; echo "\$ $*"; "$@"; }

run kubectl get nodes -o wide
run kubectl get pods,svc -n ingress-nginx -o wide
run kubectl get all -n "${NS}" -o wide
run kubectl get ingress -n "${NS}"
run kubectl describe ingress app-ingress -n "${NS}"
run kubectl get pv research-pv-037
run kubectl get pvc -n "${NS}"
run kubectl describe pvc research-pvc-037 -n "${NS}"
run kubectl get endpointslices -n "${NS}"
run curl -s -o /dev/null -w "%{http_code}  www /about/\n"   -H "Host: www.id-037.com"   http://172.25.1.181:31080/about/
run curl -s -o /dev/null -w "%{http_code}  www /research\n" -H "Host: www.id-037.com"   http://172.25.1.181:31080/research
run curl -s -o /dev/null -w "%{http_code}  www /api/test\n" -H "Host: www.id-037.com"   http://172.25.1.181:31080/api/test
run curl -s -o /dev/null -w "%{http_code}  admin /edit\n"   -H "Host: admin.id-037.com" http://172.25.1.181:31080/edit
