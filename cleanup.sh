#!/usr/bin/env bash
# shellcheck disable=SC1090
set -e

source "$(dirname "$(readlink -f "$0")")/functions.sh"
source "$(dirname "$(readlink -f "$0")")/../custom_vars.sh"

#delete only if there are at least two deployments
if [ "$(countNamespacesWithCurrentRefSlug)" -gt "1" ]; then
    kubectl delete namespace "$(getProjectNamespace)"
    helm del --purge "$(getReleaseName)"
fi
