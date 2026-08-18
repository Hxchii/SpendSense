# Runs the SpendSense API on any host that can build a Dockerfile.
#
# Debian-based rather than Alpine: PHP extensions compile against glibc
# reliably, where musl needs per-extension workarounds. The image is larger,
# but build failures cost far more than disk here.
FROM php:8.3-cli

# Only what is actually needed: zip for Composer, mbstring for Laravel's
# string handling. Everything else Laravel requires is already compiled into
# the official image.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git unzip libzip-dev libonig-dev \
    && docker-php-ext-install -j"$(nproc)" zip mbstring \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app

# Dependencies first so a code-only change doesn't reinstall the whole vendor
# tree on every deploy.
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction

COPY . .

# Listed one per line rather than with brace expansion, which the shell that
# runs RUN does not reliably support.
RUN composer dump-autoload --optimize --no-dev \
    && mkdir -p storage/framework/cache \
                storage/framework/sessions \
                storage/framework/views \
                storage/logs \
                bootstrap/cache \
    && chmod -R 777 storage bootstrap/cache

# The host assigns the port and it is not fixed between deploys, so it is read
# at start rather than baked in.
CMD php artisan config:clear \
    && php artisan serve --host=0.0.0.0 --port=${PORT:-8000}
