#!/bin/bash
# shellcheck disable=SC1091
set -o errexit -o nounset -o pipefail
command -v shellcheck > /dev/null && shellcheck "$0"

#
# Travis helpers
#

if [[ "${TRAVIS_COMMIT:-}" != "" ]]; then
  function fold_start() {
    export CURRENT_FOLD_NAME="$1"
    travis_fold start "$CURRENT_FOLD_NAME"
    travis_time_start
  }

  function fold_end() {
    travis_time_finish
    travis_fold end "$CURRENT_FOLD_NAME"
  }
else
  function fold_start() { true; }
  function fold_end() { true; }
fi

#
# Environment
#

TRAVIS_BUILD_VERSION=$(echo "${TRAVIS_COMMIT:-}" | cut -c 1-10)
BUILD_VERSION=${TRAVIS_BUILD_VERSION:-manual}

#
# Install
#

fold_start "yarn-install"
yarn install
fold_end

#
# Build
#

fold_start "yarn-build"
yarn build
yarn format
fold_end

fold_start "check-dirty"
# Ensure build step didn't modify source files to avoid unprettified repository state
SOURCE_CHANGES=$(git status --porcelain)
if [[ -n "$SOURCE_CHANGES" ]]; then
  echo "Error: repository contains changes."
  echo "Showing 'git status' and 'git diff' for debugging reasons now:"
  git status
  git diff
  exit 1
fi
fold_end

#
# Lint
#

fold_start "lint"
yarn lint
fold_end

#
# Deploy
#

fold_start "docker-build"
docker build -t "iov1/ethereum-deployment:${BUILD_VERSION}" .
fold_end

fold_start "docker-run-tests"
docker run --read-only --rm "iov1/ethereum-deployment:${BUILD_VERSION}" version
docker run --read-only --rm "iov1/ethereum-deployment:${BUILD_VERSION}" help
docker run --read-only --rm "iov1/ethereum-deployment:${BUILD_VERSION}" generate bns some-test-chain-id
fold_end

fold_start "dockerhub-upload"
if [[ "${TRAVIS_NODE_VERSION:-}" == "10" && "${TRAVIS_OS_NAME:-}" == "linux" ]]; then
  # only run in one job of the build matrix

  if [[ "$TRAVIS_BRANCH" == "master" ]] && [[ "$TRAVIS_TAG" == "" ]] && [[ "$TRAVIS_PULL_REQUEST_BRANCH" == "" ]]; then
    docker login -u "$DOCKER_USERNAME" -p "$DOCKER_PASSWORD"
    docker tag  "iov1/ethereum-deployment:${BUILD_VERSION}" "iov1/ethereum-deployment:latest"
    docker push "iov1/ethereum-deployment:latest"
    docker logout
  fi

  if [[ "$TRAVIS_TAG" != "" ]]; then
    docker login -u "$DOCKER_USERNAME" -p "$DOCKER_PASSWORD"
    docker tag  "iov1/ethereum-deployment:${BUILD_VERSION}" "iov1/ethereum-deployment:$TRAVIS_TAG"
    docker push "iov1/ethereum-deployment:$TRAVIS_TAG"
    docker logout
  fi
fi
fold_end