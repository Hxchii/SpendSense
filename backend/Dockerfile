# Runs the SpendSense API on any host that can build a Dockerfile.
FROM php:8.3-cli-alpine

# zip/unzip and git are for Composer; the PHP extensions are what Laravel and
# the Firestore REST client actually need at runtime.
RUN apk add --no-cache git zip unzip icu-dev oniguruma-dev libzip-dev \
    && docker-php-ext-install intl mbstring zip opcache

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app

# Dependencies first so a code-only change doesn't reinstall the whole vendor
# tree on every deploy.
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction

COPY . .
RUN composer dump-autoload --optimize --no-dev \
    && mkdir -p storage/framework/{cache,sessions,views} storage/logs bootstrap/cache \
    && chmod -R 777 storage bootstrap/cache

# The host tells us which port to listen on, and it is not fixed between
# deploys — so it is read at start rather than baked in.
CMD php artisan config:clear \
    && php artisan serve --host=0.0.0.0 --port=${PORT:-8000}
