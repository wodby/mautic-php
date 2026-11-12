#!/usr/bin/env bash

# Builds a Mautic Composer project with a plugin of its own on the image, as the
# buildable Mautic service does, then runs the prebuilt image's checks on the
# result. Also checks the build's refusals.

set -eo pipefail

if [[ -n "${DEBUG}" ]]; then
    set -x
fi

: "${IMAGE:?}" "${NAME:?}"
app="${NAME}:app"
work="$(mktemp -d)"
trap 'rm -rf "${work}"; docker image rm -f "${app}" > /dev/null 2>&1 || true' EXIT

# Builds the project in $1 with the buildable Mautic service's Dockerfile.
build() {
    rm -rf "${work}/context"
    mkdir -p "${work}/context"
    cp -R "$1" "${work}/context/app"
    docker build --build-arg WODBY_BASE_IMAGE="${IMAGE}" --build-arg COPY_FROM=app \
        -f Dockerfile -t "$2" "${work}/context"
}

expect_failure() {
    local description=$1 expected=$2 output
    echo -n "${description}... "
    if output=$(build "$3" "${NAME}:refused" 2>&1); then
        echo "Error: the build succeeded"
        exit 1
    fi
    if [[ "${output}" != *"${expected}"* ]]; then
        echo "Error: expected ${expected}, got:"
        tail -20 <<<"${output}"
        exit 1
    fi
    echo "OK"
}

cp -R app "${work}/nolock"
rm "${work}/nolock/composer.lock"
expect_failure "Refusing a project without composer.lock" "Commit composer.json and composer.lock" "${work}/nolock"

echo "Building the app image"
build app "${app}"

cp -R app "${work}/local"
mkdir -p "${work}/local/config"
echo '<?php $parameters = [];' > "${work}/local/config/local.php"
expect_failure "Refusing a committed settings file" "config/local.php is Mautic's own settings file" "${work}/local"

IMAGE="${app}" ./mautic.sh
