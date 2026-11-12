# Builds the app's Mautic Composer project on top of wodby/mautic-php, which has
# PHP-FPM, Apache and Wodby's setup for Mautic but no Mautic. composer.lock pins
# Mautic and the plugins and themes installed with Composer.
ARG WODBY_BASE_IMAGE

# Mautic's Composer scripts install the npm packages and build Mautic's
# JavaScript and CSS, so this stage has Node.js.
FROM ${WODBY_BASE_IMAGE} AS build

ARG COPY_FROM

USER root

RUN apk add --no-cache nodejs npm

USER wodby

# An npm package Mautic uses reports its installations to IBM unless told not to.
ENV IBM_TELEMETRY_DISABLED=true \
    COMPOSER_HOME=/tmp/composer

COPY --chown=wodby:wodby ${COPY_FROM} /var/www/html

RUN set -e; \
    cd /var/www/html; \
    if [ ! -f composer.json ] || [ ! -f composer.lock ]; then \
        echo "Commit composer.json and composer.lock: the repository must be a Mautic Composer project" >&2; \
        exit 1; \
    fi; \
    # Mautic writes its own settings there, in the files directory. \
    if [ -e config/local.php ]; then \
        echo "config/local.php is Mautic's own settings file and is kept in the files directory: remove it from the repository" >&2; \
        exit 1; \
    fi; \
    composer install --no-interaction --no-progress --no-dev --optimize-autoloader; \
    # Assets are built; the packages that built them aren't needed. \
    rm -rf node_modules /tmp/composer /home/wodby/.npm

FROM ${WODBY_BASE_IMAGE}

COPY --from=build --chown=wodby:wodby /var/www/html /var/www/html

RUN mautic-prepare-app
