#!/usr/bin/env bash

# Installs the app image in IMAGE into an empty MariaDB database with
# mautic-update, as a post-deployment action would, then checks the site, the
# app's own plugin, the cron and queue workers, an upgrade run and the cases
# where mautic-update must refuse. The same checks as wodby/mautic's test.

set -e

if [[ -n "${DEBUG}" ]]; then
    set -x
fi

network="${NAME}-net"
mariadb="${NAME}-mariadb"
mailpit="${NAME}-mailpit"
files="${NAME}-files"
web="${NAME}-web"
cron="${NAME}-cron"
worker="${NAME}-worker"

cleanup() {
    local status=$?
    if [[ "${status}" -ne 0 ]]; then
        for container in "${web}" "${cron}" "${worker}"; do
            echo "--- ${container}"
            docker logs --tail 30 "${container}" 2>&1 || true
        done
    fi
    docker rm -vf "${web}" "${cron}" "${worker}" "${mariadb}" "${mailpit}" > /dev/null 2>&1 || true
    docker volume rm -f "${files}" > /dev/null 2>&1 || true
    docker network rm "${network}" > /dev/null 2>&1 || true
    exit "${status}"
}
trap cleanup EXIT

env_args=(
    -e DB_HOST="${mariadb}"
    -e DB_PORT=3306
    -e DB_NAME=mautic
    -e DB_USERNAME=mautic
    -e 'DB_PASSWORD=mautic p@ss/w:rd#1'
    -e MSMTP_HOST="${mailpit}"
    -e MSMTP_PORT=1025
    -e MAUTIC_ADMIN_USERNAME=admin
    -e MAUTIC_ADMIN_PASSWORD=Secret-Pass-123
    -e MAUTIC_ADMIN_EMAIL=admin@example.com
    -e MAUTIC_SITE_NAME='Example Inc.'
    -e WODBY_PRIMARY_URL=https://mautic.example.com
    -e MAUTIC_CRON_INTERVAL=20
)

# A one-off container, as Wodby runs actions.
mautic_run() {
    docker run --rm --network "${network}" "${env_args[@]}" -v "${files}:/mnt/files" "${IMAGE}" "${@}"
}

mautic_start() {
    docker run -d --name "$1" --network "${network}" "${env_args[@]}" -v "${files}:/mnt/files" "${IMAGE}" "${@:2}" > /dev/null
}

sql() {
    docker exec "${mariadb}" mariadb -umautic '-pmautic p@ss/w:rd#1' mautic -NBe "${1}"
}

# Requests from inside the web container, as the gateway sends them, with a
# session. Mautic marks its cookies secure, and curl won't keep secure cookies
# over plain HTTP, so /tmp/request, installed below, keeps them itself.
request() {
    docker exec "${web}" /tmp/request "${@}"
}

install_request() {
    docker exec -i "${web}" sh -c 'cat > /tmp/request && chmod +x /tmp/request' <<'SCRIPT'
#!/bin/sh
touch /tmp/cookies
cookie=$(paste -sd ';' /tmp/cookies | sed 's/;/; /g')
set -- -H 'Host: mautic.example.com' -H 'X-Forwarded-Proto: https' "$@"
if [ -n "${cookie}" ]; then
    set -- -H "Cookie: ${cookie}" "$@"
fi
curl -sS -D /tmp/headers "$@"
status=$?
tr -d '\r' < /tmp/headers | sed -n -E 's/^[Ss]et-[Cc]ookie: *([^;]*).*/\1/p' | while IFS= read -r pair; do
    grep -v "^${pair%%=*}=" /tmp/cookies > /tmp/cookies.new
    echo "${pair}" >> /tmp/cookies.new
    mv /tmp/cookies.new /tmp/cookies
done
exit "${status}"
SCRIPT
}

status() {
    request -o /dev/null -w '%{http_code}' "http://localhost$1"
}

expect() {
    local description=$1 actual=$2 expected=$3
    echo -n "${description}... "
    if [[ "${actual}" != *"${expected}"* ]]; then
        echo "Error: expected ${expected}, got: ${actual}"
        exit 1
    fi
    echo "OK"
}

wait_for() {
    local description=$1 command=$2
    for _ in $(seq 1 90); do
        if eval "${command}" > /dev/null 2>&1; then
            return
        fi
        sleep 2
    done
    echo "Error: ${description} timed out"
    exit 1
}

docker network create "${network}" > /dev/null
docker volume create "${files}" > /dev/null
docker run -d --name "${mariadb}" --network "${network}" \
    -e MARIADB_ROOT_PASSWORD=root -e MARIADB_DATABASE=mautic -e MARIADB_USER=mautic -e 'MARIADB_PASSWORD=mautic p@ss/w:rd#1' \
    mariadb:11.8 > /dev/null
docker run -d --name "${mailpit}" --network "${network}" axllent/mailpit:v1.27 > /dev/null
wait_for "MariaDB" "sql 'SELECT 1'"

expect "Refusing to install without an admin password" \
    "$(docker run --rm --network "${network}" -e DB_HOST="${mariadb}" -v "${files}:/mnt/files" "${IMAGE}" mautic-update 2>&1 || true)" \
    "set MAUTIC_ADMIN_PASSWORD"

# The workers wait for the installation.
mautic_start "${cron}" mautic-cron
mautic_start "${worker}" mautic-worker
mautic_start "${web}"
docker exec "${web}" make check-ready max_try=60 -f /usr/local/bin/actions.mk > /dev/null
install_request

echo -n "Installing Mautic... "
mautic_run mautic-update > /dev/null
echo "OK"
expect "Registering the plugin from the repository" "$(sql "SELECT bundle FROM plugins WHERE bundle = 'WodbyHelloBundle'")" "WodbyHelloBundle"
expect "Removing the administrator from the settings" "$(docker exec "${web}" grep -c admin_password /mnt/files/config/local.php || true)" "0"
expect "Queueing email in the database" "$(docker exec "${web}" grep messenger_dsn_email /mnt/files/config/local.php)" "doctrine://default"

expect "Showing the sign-in page" "$(status /s/login)" "200"
expect "Using the main route over HTTPS" "$(request http://localhost/mtc.js)" "https://mautic.example.com"
expect "Serving built assets" "$(status /media/js/app.js)" "200"
expect "Applying Mautic's .htaccess rules" "$(status /app/AppKernel.php)" "403"
expect "Hiding the web installer" "$(status /installer)" "403"
expect "Hiding uploaded files" "$(docker exec "${web}" sh -c 'echo secret > /mnt/files/media/files/x.txt' && status /media/files/x.txt)" "403"
docker exec "${web}" sh -c 'cp docroot/app/assets/images/favicon.ico /mnt/files/media/images/test.ico && echo "<?php echo 1;" > /mnt/files/media/images/x.php'
expect "Serving uploaded images" "$(status /media/images/test.ico)" "200"
expect "Not running uploaded scripts" "$(status /media/images/x.php)" "403"

echo -n "Sending queued email... "
form=$(request http://localhost/passwordreset | tr '\n' ' ')
reset_token=$(echo "${form}" | grep -o -E 'name="passwordreset\[_token\]"[^>]*' | grep -o 'value="[^"]*' | cut -d'"' -f2)
request -o /dev/null --data-urlencode "passwordreset[identifier]=admin" \
    --data-urlencode "passwordreset[_token]=${reset_token}" --data-urlencode "passwordreset[submit]=" \
    http://localhost/passwordreset
wait_for "the password reset email" \
    "docker exec ${web} curl -sf http://${mailpit}:8025/api/v1/messages | grep -q 'Mautic password reset'"
echo "OK"

echo -n "Signing in... "
token=$(request http://localhost/s/login | grep -o '_csrf_token" value="[^"]*' | cut -d'"' -f3)
location=$(request -o /dev/null -w '%{redirect_url}' \
    -d "_username=admin&_password=Secret-Pass-123&_csrf_token=${token}" http://localhost/s/login_check)
if [[ "${location}" != */s/dashboard ]]; then
    echo "Error: signing in redirected to ${location}"
    exit 1
fi
# The first dashboard request after signing in redirects to itself.
for _ in 1 2 3; do
    code=$(status /s/dashboard)
    [[ "${code}" == "200" ]] && break
done
if [[ "${code}" != "200" ]]; then
    echo "Error: the dashboard answered ${code} after signing in"
    exit 1
fi
echo "OK"

echo -n "Running cron jobs... "
wait_for "the cron run" "docker logs ${cron} 2>&1 | grep -q 'Scheduler has finished'"
if docker logs "${cron}" 2>&1 | grep -q ' failed$'; then
    docker logs "${cron}" 2>&1 | grep ' failed$'
    exit 1
fi
echo "OK"

expect "Upgrading an installed Mautic" "$(mautic_run mautic-update 2>&1)" "plugins were installed"

echo -n "Stopping the workers gracefully... "
for container in "${cron}" "${worker}"; do
    docker stop -t 30 "${container}" > /dev/null
    if [[ "$(docker inspect -f '{{.State.ExitCode}}' "${container}")" != "0" ]]; then
        echo "Error: ${container} exited with $(docker inspect -f '{{.State.ExitCode}}' "${container}")"
        exit 1
    fi
done
echo "OK"

tables=$(sql 'SHOW TABLES' | wc -l | tr -d ' ')
docker exec "${web}" mv /mnt/files/config/local.php /mnt/files/config/local.php.lost
expect "Refusing to install over existing tables" "$(mautic_run mautic-update 2>&1 || true)" "its database has tables"
expect "Leaving the database alone" "$(sql 'SHOW TABLES' | wc -l | tr -d ' ')" "${tables}"
expect "Writing no new settings file" "$(docker exec "${web}" sh -c 'test -e /mnt/files/config/local.php && echo written || echo none')" "none"
