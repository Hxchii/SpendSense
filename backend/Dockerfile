# Runs the SpendSense API on any host that can build a Dockerfile.
#
# Debian-based rather than Alpine: PHP extensions compile against glibc
# reliably, where musl needs per-extension workarounds. The image is larger,
# but build failures cost far more than disk here.
# 8.4 specifically: composer.lock resolved Symfony 8.1, which requires
# PHP >= 8.4.1. An older image cannot install the locked versions at all.
FROM php:8.4-cli

# Only what is actually needed: zip for Composer, mbstring for Laravel's
# string handling. Everything else Laravel requires is already compiled into
# the official image.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git unzip libzip-dev libonig-dev \
    && docker-php-ext-install -j"$(nproc)" zip mbstring \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# This API has no relational database — Firestore is the store — but Laravel
# defaults to keeping cache and sessions in one. Without these, caching
# Google's signing certificates fails, which surfaces as every request being
# rejected as unauthenticated.
ENV CACHE_STORE=file \
    SESSION_DRIVER=file \
    QUEUE_CONNECTION=sync \
    LOG_CHANNEL=stderr

WORKDIR /app

# Dependencies first so a code-only change doesn't reinstall the whole vendor
# tree on every deploy.
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction

COPY . .

# Directories first: dumping the autoloader triggers Laravel's package
# discovery, which writes into bootstrap/cache — creating it afterwards meant
# that step ran against a directory that did not exist yet.
#
# --no-scripts on top of that, because package discovery boots the framework,
# and the environment it needs (app key, credentials) only exists at run time.
# Laravel falls back to discovering packages on the first request when no
# cached manifest is present.
RUN mkdir -p storage/framework/cache \
             storage/framework/sessions \
             storage/framework/views \
             storage/logs \
             bootstrap/cache \
    && chmod -R 777 storage bootstrap/cache \
    && composer dump-autoload --optimize --no-dev --no-scripts

# The host assigns the port and it is not fixed between deploys, so it is read
# at start rather than baked in.
CMD php artisan config:clear \
    && php artisan serve --host=0.0.0.0 --port=${PORT:-8000}
