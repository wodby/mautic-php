# check=skip=InvalidDefaultArgInFrom

# The Makefile supplies the required digest-pinned BASE_IMAGE: the Apache
# variant of wodby/php, which serves the application and runs PHP-FPM in one
# container.
ARG BASE_IMAGE

# PHP-FPM and Apache with Wodby's setup for Mautic, but no Mautic: an image
# built on this one copies an app's Mautic Composer project into
# /var/www/html and runs mautic-prepare-app.
FROM ${BASE_IMAGE}

ENV APP_NAME="Mautic" \
    APACHE_DOCUMENT_ROOT="/var/www/html/docroot" \
    \
    # PHP-FPM runs as the owner of the code, like Mautic's console commands, \
    # so the cache, settings and files any of them write stay writable by the \
    # others. \
    PHP_FPM_USER="wodby" \
    # Mautic's settings file reads the database and address from the environment. \
    PHP_FPM_CLEAR_ENV="no" \
    # Imports, exports and installation take longer than PHP's default limit. \
    PHP_MAX_EXECUTION_TIME="300" \
    PHP_UPLOAD_MAX_FILESIZE="64M" \
    PHP_POST_MAX_SIZE="64M" \
    # Mautic's installer asks for both. \
    PHP_ZEND_ASSERTIONS="-1" \
    PHP_ZEND_EXCEPTION_IGNORE_ARGS="1"

COPY share/parameters_local.php /usr/local/share/mautic/parameters_local.php
COPY apache/mautic.conf /etc/apache2/conf.d/mautic.conf
COPY bin /usr/local/bin/
