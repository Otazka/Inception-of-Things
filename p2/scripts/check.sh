#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

machine=$(vagrant status --machine-readable | awk -F, '$3 == "state" {print $2; exit}')
[[ "$machine" == *S ]] || { echo 'Expected the p2 server VM.' >&2; exit 1; }
node_name=$(printf '%s' "$machine" | tr '[:upper:]' '[:lower:]')

vagrant ssh "$machine" -c 'test "$(uname -m)" = x86_64 && sudo systemctl is-active --quiet k3s && ip -4 -o addr show | grep -F "192.168.56.110/24"'
vagrant ssh "$machine" -c "sudo kubectl wait --for=condition=Ready node/$node_name --timeout=300s"
vagrant ssh "$machine" -c 'sudo kubectl -n iot rollout status deployment/app1 --timeout=60s; sudo kubectl -n iot rollout status deployment/app2 --timeout=60s; sudo kubectl -n iot rollout status deployment/app3 --timeout=60s'
vagrant ssh "$machine" -c 'test "$(sudo kubectl -n iot get deployment app2 -o jsonpath="{.spec.replicas}")" = 3'
vagrant ssh "$machine" -c 'sudo kubectl get nodes -o wide; sudo kubectl -n iot get deployments,services,ingress'
echo 'Part 2: K3s, three applications, and the Host-based Ingress are ready.'
