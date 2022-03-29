#!/bin/bash

# Copy SQL data
if [[ ! "$(ls -A /var/lib/mysql)" ]]; then
    # Initialize MariaDB database
    echo "Database not initialized. Initializing now..."
    mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
    service mariadb start
    mysql -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY 'yourPassword';"
    mysql -u root -e "CREATE DATABASE panel;"
    mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
fi

# Go into pterodactyl directory
cd /var/www/pterodactyl || exit

echo "Starting services..."

# Start services
service mariadb start
service redis-server start
service php8.0-fpm start

# Do stuff on first run
if [ ! -f "/var/lib/mysql/.firstrun" ]; then

    echo "First run detected. Generating initial configuration files..."

    # Copy default config
    cp .env.example .env

    echo "Setting up email configuration..."

    # Set mail driver
    php artisan p:environment:mail --driver=mail -n > /dev/null 2>&1

    echo "Configuring database connection..."

    # Configure pterodactyl
    if [ -n "$DB_PASSWORD" ] && [ -z "$DB_USER" ]; then
        mysql -u root -e "ALTER USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';" > /dev/null 2>&1
        php artisan p:environment:database -n --username=pterodactyl --password="${DB_PASSWORD}" > /dev/null 2>&1
    elif [ -z "$DB_PASSWORD" ] && [ -n "$DB_USER" ] && [ "$DB_USER" != "pterodactyl" ]; then
        mysql -u root -e "CREATE USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY 'pteropasswd';" > /dev/null 2>&1
        mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;" > /dev/null 2>&1
        php artisan p:environment:database -n --username="${DB_USER}" --password=pteropasswd > /dev/null 2>&1
    elif [ -n "$DB_PASSWORD" ] && [ -n "$DB_USER" ] && [ "$DB_USER" != "pterodactyl" ]; then
        mysql -u root -e "CREATE USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';" > /dev/null 2>&1
        mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;" > /dev/null 2>&1
        php artisan p:environment:database -n --username="${DB_USER}" --password="${DB_PASSWORD}" > /dev/null 2>&1
    else
        if [ -n "$DB_PASSWORD" ]; then
            mysql -u root -e "ALTER USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';" > /dev/null 2>&1
            php artisan p:environment:database -n --username=pterodactyl --password="${DB_PASSWORD}" > /dev/null 2>&1
        else
            mysql -u root -e "ALTER USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY 'pteropasswd';" > /dev/null 2>&1
            php artisan p:environment:database -n --username=pterodactyl --password=pteropasswd > /dev/null 2>&1
        fi
    fi

    echo "Setting up environment..."

    # More configuration
    if [ -n "${APP_URL}" ] && [ -z "${APP_AUTHOR}" ] && [ -z "${APP_TZ}" ]; then
        php artisan p:environment:setup -n --timezone=America/Los_Angeles \
            --url="${APP_URL}" --author=admin@local.host --cache=redis \
            --session=redis --queue=redis > /dev/null 2>&1
    elif [ -n "${APP_URL}" ] && [ -n "${APP_AUTHOR}" ] && [ -z "${APP_TZ}" ]; then
        php artisan p:environment:setup -n --timezone=America/Los_Angeles \
            --url="${APP_URL}" --author="${APP_AUTHOR}" --cache=redis \
            --session=redis --queue=redis > /dev/null 2>&1
    elif [ -n "${APP_URL}" ] && [ -n "${APP_AUTHOR}" ] && [ -n "${APP_TZ}" ]; then
        php artisan p:environment:setup -n --timezone="${APP_TZ}" \
            --url="${APP_URL}" --author="${APP_AUTHOR}" --cache=redis \
            --session=redis --queue=redis > /dev/null 2>&1
    elif [ -n "${APP_URL}" ] && [ -z "${APP_AUTHOR}" ] && [ -n "${APP_TZ}" ]; then
        php artisan p:environment:setup -n --timezone="${APP_TZ}" \
            --url="${APP_URL}" --author=admin@local.host --cache=redis \
            --session=redis --queue=redis > /dev/null 2>&1
    elif [ -z "${APP_URL}" ] && [ -n "${APP_AUTHOR}" ] && [ -n "${APP_TZ}" ]; then
        php artisan p:environment:setup -n --timezone="${APP_TZ}" \
            --url=https://local.host --author="${APP_AUTHOR}" --cache=redis \
            --session=redis --queue=redis > /dev/null 2>&1
    fi

    echo "Generating key..."

    # Generate key
    php artisan key:generate --force > /dev/null 2>&1

    echo "Migrating database..."

    # Migrate database
    php artisan migrate --seed --force > /dev/null 2>&1

    echo "Creating default admin user..."

    # Create admin user
    php artisan p:user:make -n --admin=yes --name-first=Local --name-last=Administrator \
        --username=Administrator --email=admin@local.host --password=password > /dev/null 2>&1
    mysql -u root -D panel -e "UPDATE users SET root_admin = 1 WHERE username = 'administrator';"; > /dev/null 2>&1

    echo "Creating default node location..."

    # Add location
    php artisan p:location:make -n --short=DF --long=Default > /dev/null 2>&1

    echo "Setting up permissions..."

    # Signify the first run
    touch /var/lib/mysql/.firstrun

    # Change permissions
    chown -R www-data:www-data /var/www/pterodactyl/* > /dev/null 2>&1

    # Setup nginx
    if [ -n "${APP_URL}" ]; then
        echo "Setting up nginx..."
        APP_DOMAIN="$(echo "${APP_URL}" | awk -F/ '{print $3}')"
        sed -i "s/server_name local\.host\;/server_name ${APP_DOMAIN}\;/g" > /dev/null 2>&1
        certbot --nginx --agree-tos -m admin@local.host -d "${APP_DOMAIN}" -n > /dev/null 2>&1
    fi

    # Disable 2FA
    if [ "${DISABLE_2FA}" == "true" ] || [ "${DISABLE_2FA}" == "yes" ]; then
        echo "Disabling 2FA..."
        mysql -u root -e "UPDATE panel.settings SET value = 0 WHERE \`key\` = 'settings::pterodactyl:auth:2fa_required';" > /dev/null 2>&1
    fi

fi

echo "Starting Pterodactyl..."

# Start pterodactyl
/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3 &
service cron start

echo "Starting nginx..."

# Start NGINX
nginx -g 'daemon off;'