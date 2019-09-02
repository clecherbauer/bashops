#!/usr/bin/env bash
# shellcheck disable=SC1090
set -e

source "$(dirname "$(readlink -f "$0")")/functions.sh"
source "$(dirname "$(readlink -f "$0")")/../custom_vars.sh"
initOldNamespaceVariable

removeOldNameSpaces "$(getOldInstanceNamespace)" "$(getProjectPrefix)"

#remove old volume dirs
ssh -o StrictHostKeyChecking=no "selbstmade@$_REVIEW_HOST" "sudo rm -Rf /var/container_data/$(getProjectPrefix)/$CI_COMMIT_REF_SLUG"
