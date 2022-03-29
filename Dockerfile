# Base OS
FROM ubuntu:focal

# Environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=US/Pacific \
    LC_ALL=C.UTF-8

# Update system
RUN apt-get update && \
    apt-get -y upgrade

# Install base dependencies
RUN apt-get -y install software-properties-common \
    curl apt-transport-https ca-certificates gnupg \
    tar wget unzip zip apt dpkg sudo bash dash \
    lsb-release lsb-core

# Use bash
SHELL [ "/bin/bash", "-c" ]

# Add repositories
RUN add-apt-repository -y ppa:ondrej/php && \
    add-apt-repository -y ppa:chris-lea/redis-server && \
    curl -fsSL https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash && \
    apt-get update && \
    apt-get -y upgrade

# Install dependencies
RUN apt-get -y install php8.0 php8.0-cli php8.0-gd php8.0-mysql \
    php8.0-pdo php8.0-mbstring php8.0-tokenizer php8.0-bcmath \
    php8.0-xml php8.0-fpm php8.0-curl php8.0-zip mariadb-server \
    nginx tar unzip git redis-server certbot python3-certbot-nginx \
    cron

# Install composer
RUN curl -fsSL https://getcomposer.org/installer | php -- \
    --install-dir=/usr/local/bin --filename=composer

# Download pterodactyl
RUN mkdir -p /var/www/pterodactyl
WORKDIR /var/www/pterodactyl
RUN curl -fsSLo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz && \
    tar zxvf panel.tar.gz && \
    chmod -R 755 storage/* bootstrap/cache/

# Setup database
RUN service mariadb start && \
    mysql -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY 'yourPassword';" && \
    mysql -u root -e "CREATE DATABASE panel;" && \
    mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"

# Install dependencies
RUN cp .env.example .env && \
    composer install --no-dev --optimize-autoloader && \
    echo "* * * * * /usr/local/bin/php /app/artisan schedule:run >> /dev/null 2>&1" >> /var/spool/cron/crontabs/root

# Add queue worker
COPY pteroq.service /etc/systemd/system/pteroq.service

# Setup NGINX
RUN rm /etc/nginx/sites-enabled/default
COPY pterodactyl.conf /etc/nginx/sites-available/pterodactyl.conf
RUN ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf

# Add entrypoint
COPY entrypoint.sh /docker-entrypoint.sh
RUN chmod a+rx /docker-entrypoint.sh

# NGINX things
RUN ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

# Volumes
VOLUME [ "/var/lib/mysql" ]

# SQL Healthcheck
HEALTHCHECK --start-period=5m \
  CMD mariadb -e 'SELECT @@datadir;' || exit 1

# Start
ENTRYPOINT [ "/bin/bash", "/docker-entrypoint.sh" ]