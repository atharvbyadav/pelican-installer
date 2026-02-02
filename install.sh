#!/usr/bin/env bash
set -e

#############################################
# Pelican Universal Installer (HTTPS Edition)
# Repo: pelican-installer
#############################################

clear

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo:"
  echo "curl ... | sudo bash"
  exit 1
fi

echo "======================================"
echo "     Pelican Universal Installer"
echo "          HTTPS + SSL"
echo "======================================"
echo "1) Install Panel only"
echo "2) Install Wings only"
echo "3) Install Panel + Wings"
echo "======================================"
read -p "Select option: " MODE

#############################################
# COMMON
#############################################

install_base() {
  apt update && apt upgrade -y
  apt install -y software-properties-common ca-certificates \
  apt-transport-https curl git unzip tar ufw lsb-release
}

install_php() {
  add-apt-repository ppa:ondrej/php -y
  apt update
  apt install -y php8.4 php8.4-fpm php8.4-cli php8.4-gd php8.4-mysql \
  php8.4-mbstring php8.4-bcmath php8.4-xml php8.4-curl php8.4-zip \
  php8.4-intl php8.4-sqlite3
  systemctl enable --now php8.4-fpm
}

install_nginx() {
  apt install -y nginx
  systemctl enable --now nginx
}

install_mariadb() {
  apt install -y mariadb-server mariadb-client
  systemctl enable --now mariadb
}

install_composer() {
  curl -sS https://getcomposer.org/installer | php \
  -- --install-dir=/usr/local/bin --filename=composer
}

install_certbot() {
  apt install -y certbot python3-certbot-nginx
}

install_docker() {
  curl -sSL https://get.docker.com/ | sh
  systemctl enable --now docker
}

#############################################
# PANEL INSTALL
#############################################

install_panel() {

read -p "Enter Panel Domain (example: panel.example.com): " DOMAIN
read -p "Enter SSL Email: " EMAIL
read -p "Enter MariaDB root password: " DBPASS

install_base
install_php
install_nginx
install_mariadb
install_composer
install_certbot

#############################################
# FIREWALL
#############################################

ufw allow 22
ufw allow 80
ufw allow 443
ufw --force enable

#############################################
# DATABASE
#############################################

mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DBPASS}'; FLUSH PRIVILEGES;"

mysql -uroot -p${DBPASS} <<EOF
CREATE DATABASE pelican;
CREATE USER 'pelican'@'127.0.0.1' IDENTIFIED BY '${DBPASS}';
GRANT ALL PRIVILEGES ON pelican.* TO 'pelican'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF

#############################################
# DOWNLOAD PANEL
#############################################

mkdir -p /var/www/pelican
cd /var/www/pelican

curl -L https://github.com/pelican-dev/panel/releases/latest/download/panel.tar.gz | tar -xz
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

php artisan p:environment:setup --no-interaction
php artisan key:generate --force
php artisan optimize:clear

chown -R www-data:www-data /var/www/pelican
chmod -R 755 storage/* bootstrap/cache/

#############################################
# TEMP HTTP CONFIG (for certbot)
#############################################

rm -f /etc/nginx/sites-enabled/default

server {
  listen 80;
  server_name ${DOMAIN};
  root /var/www/pelican/public;
  index index.php;

  location / {
    try_files \$uri \$uri/ /index.php?\$query_string;
  }

  location ~ \\.php\$ {
    include fastcgi_params;
    fastcgi_pass unix:/run/php/php8.4-fpm.sock;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
  }
}
EOL

ln -sf /etc/nginx/sites-available/pelican.conf /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx

#############################################
# SSL CERTIFICATE
#############################################

certbot --nginx -d ${DOMAIN} --agree-tos -m ${EMAIL} --non-interactive

#############################################
# FINAL HTTPS CONFIG
#############################################

cat > /etc/nginx/sites-available/pelican.conf <<EOL
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    root /var/www/pelican/public;
    index index.php;

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \\.php\$ {
        fastcgi_split_path_info ^(.+\\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOL

nginx -t
systemctl restart nginx

echo "--------------------------------------"
echo "Pelican Panel Installed!"
echo "Open: https://${DOMAIN}/installer"
echo "DB: pelican"
echo "User: pelican"
echo "Pass: ${DBPASS}"
echo "--------------------------------------"
}

#############################################
# WINGS INSTALL
#############################################

install_wings() {

install_base
install_docker

mkdir -p /etc/pelican /var/run/wings

ARCH=$(uname -m)
[[ "$ARCH" == "x86_64" ]] && WARCH="amd64" || WARCH="arm64"

curl -L -o /usr/local/bin/wings \
https://github.com/pelican-dev/wings/releases/latest/download/wings_linux_${WARCH}

chmod +x /usr/local/bin/wings

cat > /etc/systemd/system/wings.service <<EOF
[Unit]
Description=Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pelican
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

ufw allow 2022
ufw allow 8080:8090/tcp

echo "--------------------------------------"
echo "Wings Installed!"
echo "Paste node config to:"
echo "/etc/pelican/config.yml"
echo "Then run:"
echo "systemctl enable --now wings"
echo "--------------------------------------"
}

#############################################
# MENU
#############################################

case $MODE in
1) install_panel ;;
2) install_wings ;;
3) install_panel && install_wings ;;
*) echo "Invalid option"; exit 1 ;;
esac

