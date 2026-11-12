# PHP image for buildable Mautic

[![Build Status](https://github.com/wodby/mautic-php/workflows/Build%20docker%20image/badge.svg)](https://github.com/wodby/mautic-php/actions)

PHP-FPM and Apache with Wodby's setup for Mautic, but no Mautic. The
[buildable Mautic](https://github.com/wodby/service-mautic-buildable) service
builds an app's image on it from the app's Mautic Composer project. For Mautic
without your own plugins, use the prebuilt
[wodby/mautic](https://github.com/wodby/mautic) image.

Based on the Apache variant of [wodby/php](https://github.com/wodby/php).

## Tags

| Tag | PHP |
| --- | --- |
| `8.4`, `8`, `latest` | 8.4 |

Image revisions are tagged `rN`, such as `8.4-r0`.

## What's inside

The same setup as wodby/mautic:

- Apache serves `/var/www/html/docroot`, with rules for the directories Mautic
  keeps in the files volume and the web installer turned off.
- `mautic-update` installs Mautic into an empty database or migrates it, then
  registers the plugins. `mautic-cron` and `mautic-worker` run Mautic's cron
  jobs and queues. `mautic-installed` tells whether Mautic is installed.
- `mautic-prepare-app` finishes a Composer project copied into `/var/www/html`:
  it adds Wodby's settings file, which reads the database and address from the
  environment, and links Mautic's settings, uploads, language packs, imports
  and logs to the files directory. It refuses a project with its own
  `config/local.php`.

## Environment variables

The variables of [wodby/mautic](https://github.com/wodby/mautic) apply: the
database (`DB_*`), the administrator (`MAUTIC_ADMIN_*`), the site address
(`MAUTIC_SITE_URL` or `WODBY_PRIMARY_URL`), the mail server (`MSMTP_*`) and the
workers (`MAUTIC_CRON_*`, `MAUTIC_WORKER_TRANSPORTS`).

## Use

```Dockerfile
FROM wodby/mautic-php:8.4 AS build
USER root
RUN apk add --no-cache nodejs npm
USER wodby
COPY --chown=wodby:wodby . /var/www/html
RUN composer install -d /var/www/html --no-interaction --no-dev

FROM wodby/mautic-php:8.4
COPY --from=build --chown=wodby:wodby /var/www/html /var/www/html
RUN mautic-prepare-app
```
