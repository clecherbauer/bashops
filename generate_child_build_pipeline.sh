#!/usr/bin/env bash
# shellcheck disable=SC1090
# shellcheck disable=SC2034
# shellcheck disable=SC1091
set -e

source "$(dirname "$(readlink -f "$0")")/functions.sh"
source "$(dirname "$(readlink -f "$0")")/../bashops.sh"

cat >> child-build-pipeline-gitlab-ci.yml <<EOL
.if_production: &if_production
  only:
  - master
  except:
  - tags

stages:
- prepare
- build

variables:
  GIT_SUBMODULE_STRATEGY: recursive
  KUBECONFIG: /etc/kubeconfig
  KUBECTL_HELM_IMAGE: registry.gitlab.com/clecherbauer/docker-images/k8s-tools:helm-3
  REVIEW_HOST: review.selbstmade.ch
  REVIEW_INSTANCES: "true"

tag:
  stage: prepare
  image: docker:git
  <<: *if_production
  script:
  - git fetch --tags -f
  - if [ -z "$(git tag -l --points-at HEAD)" ]; then echo "There is no tag on this commit!"; exit 1; fi

build-docker-build-env:
  except:
  - tags
  stage: prepare
  image: docker:git
  script:
   - apk add --update bash;
   - .devops/bashops/write-docker-build-env.sh
  artifacts:
    paths:
    - .docker_build_env

EOL

for _CONTAINER in $_CONTAINERS_TO_BUILD; do
  cat >> child-build-pipeline-gitlab-ci.yml <<EOL
build_${_CONTAINER}:
  stage: build
  image: docker:git
  services:
  - name: docker:dind
  allow_failure: false
  script:
  - apk add --no-cache bash
  - .devops/bashops/build_and_push.sh ${_CONTAINER}
  retry: 2
EOL
done