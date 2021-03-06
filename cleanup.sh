#!/usr/bin/env bash
# shellcheck disable=SC1090
# shellcheck disable=SC1091
set -e

source "$(dirname "$(readlink -f "$0")")/functions.sh"
source "$(dirname "$(readlink -f "$0")")/../bashops.sh"

#delete only if there are at least two deployments
if [ "$(countNamespacesWithCurrentRefSlug)" -gt "1" ]; then
    kubectl delete namespace "$(getProjectNamespace)"
    helm del --purge "$(getReleaseName)"
fi
