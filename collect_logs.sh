#!/usr/bin/env bash
# shellcheck disable=SC1090
# shellcheck disable=SC2086
set -e

source "$(dirname "$(readlink -f "$0")")/functions.sh"
source "$(dirname "$(readlink -f "$0")")/../custom_vars.sh"

echo ">>> Overview $(getProjectNamespace)"
echo ""
kubectl get all -n "$(getProjectNamespace)"
echo ""
echo ""

for p in $(kubectl get services --no-headers -n "$(getProjectNamespace)" | cut -f 1 -d ' '); do
    echo ">>> Description of Service $p in $(getProjectNamespace)"
    echo ""
    kubectl describe service "$p" -n "$(getProjectNamespace)"
    echo ""
    echo ""
done

for p in $(kubectl get deployments --no-headers -n "$(getProjectNamespace)" | cut -f 1 -d ' '); do
    echo ">>> Description of Deployment $p in $(getProjectNamespace)"
    echo ""
    kubectl describe deployment "$p" -n "$(getProjectNamespace)"
    echo ""
    echo ""
done

for p in $(kubectl get pods --no-headers -n "$(getProjectNamespace)" | cut -f 1 -d ' '); do
    echo ">>> Description of Pod $p in $(getProjectNamespace)"
    echo ""
    kubectl describe pod "$p" -n "$(getProjectNamespace)"
    echo ""
    echo ""
    echo ">>> Logs of Pod $p in $(getProjectNamespace)"
    echo ""
    kubectl logs "$p" -n "$(getProjectNamespace)"
    echo ""
    echo ""
done
