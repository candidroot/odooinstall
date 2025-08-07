#!/bin/bash

# === Configuration ===
ODOO_VERSION="18.0"
ODOO_PORT="8069"
ODOO_DIR="odoo18-docker"
POSTGRES_VERSION="15"
ODOO_DB_USER="odoo"
ODOO_DB_PASSWORD="odoo"
DOMAIN="odoo.yourdomain.com" # <<< CHANGE THIS
EMAIL="you@example.com"      # <<< CHANGE THIS

# === Update & Install Dependencies ===
echo "🔄 Updating system packages..."
sudo apt update && sudo apt upgrade -y

echo "📦 Installing Docker & Docker Compose..."
sudo apt install -y docker.io docker-compose curl

# Enable Docker
sudo systemctl enable docker
sudo systemctl start docker

# === Create Odoo Directory ===
mkdir -p ~/$ODOO_DIR/addons
cd ~/$ODOO_DIR || exit

# === Create docker-compose.yml ===
cat <<EOF > docker-compose.yml
version: '3.1'

services:
  web:
    image: odoo:${ODOO_VERSION}
    depends_on:
      - db
    expose:
      - "8069"
    volumes:
      - odoo-web-data:/var/lib/odoo
      - ./addons:/mnt/extra-addons
    environment:
      - HOST=db
      - USER=${ODOO_DB_USER}
      - PASSWORD=${ODOO_DB_PASSWORD}

  db:
    image: postgres:${POSTGRES_VERSION}
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=${ODOO_DB_USER}
      - POSTGRES_PASSWORD=${ODOO_DB_PASSWORD}
    volumes:
      - odoo-db-data:/var/lib/postgresql/data

  nginx:
    image: nginx:latest
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/ssl:/etc/letsencrypt
    depends_on:
      - web

volumes:
  odoo-web-data:
  odoo-db-data:
EOF

# === Create NGINX config ===
mkdir -p nginx/conf.d nginx/ssl

cat <<EOF > nginx/conf.d/odoo.conf
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://web:8069;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location ~ /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
}
EOF

# === Create SSL cert with Certbot in Docker ===
echo "📜 Getting SSL certificate for ${DOMAIN}..."
docker run --rm -v "$(pwd)/nginx/ssl:/etc/letsencrypt" \
  -v "$(pwd)/nginx/www:/var/www/certbot" \
  certbot/certbot certonly --webroot \
  --webroot-path=/var/www/certbot \
  --email ${EMAIL} --agree-tos --no-eff-email \
  -d ${DOMAIN}

# === Update NGINX config with SSL ===
cat <<EOF > nginx/conf.d/odoo.conf
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    location / {
        proxy_pass http://web:8069;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# === Start Everything ===
echo "🚀 Starting all services..."
sudo docker-compose up -d

# === Auto-Renew SSL with Cron Job ===
(crontab -l 2>/dev/null; echo "0 3 * * * docker run --rm -v $(pwd)/nginx/ssl:/etc/letsencrypt -v $(pwd)/nginx/www:/var/www/certbot certbot/certbot renew --webroot --webroot-path=/var/www/certbot && docker-compose restart nginx") | crontab -

# === Done ===
echo "✅ Odoo 18 with NGINX + SSL is now running!"
echo "🔗 Visit: https://${DOMAIN}"
