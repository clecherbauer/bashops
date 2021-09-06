#!/usr/bin/env bash
# shellcheck disable=SC1090
# shellcheck disable=SC1091
set -e

_REVIEW_CLUSTER_USER=""
_REVIEW_CLUSTER_TOPLEVEL_DOMAIN=""

source "$(dirname "$(readlink -f "$0")")/functions.sh"
source "$(dirname "$(readlink -f "$0")")/../bashops.sh"
initOldNamespaceVariable

removeOldNameSpaces "$(getOldInstanceNamespace)" "$(getProjectPrefix)"

#remove old volume dirs
ssh -o StrictHostKeyChecking=no "$_REVIEW_CLUSTER_USER@$_REVIEW_CLUSTER_TOPLEVEL_DOMAIN" "sudo rm -Rf /var/container_data/$(getProjectPrefix)/$CI_COMMIT_REF_SLUG"
