#!/bin/bash
################################################################################
# Odoo 18 Multi-Instance Installation Script
# This script creates a user-specific installation (odoo, etc.)
################################################################################

# === Parameters ===
ODOO_USER="odoo"                # All configs/files will be named after this
ODOO_HOME="/opt/$ODOO_USER"
ODOO_VERSION="18.0"
ODOO_PORT="8069"               # Change if running multiple instances on 1 server
ODOO_LONGPOLLING_PORT="8072"   # Change if running multiple instances on 1 server
ADMIN_PASS="admin"

INSTALL_NGINX="True"           # True/False
INSTALL_SSL="False"            # True/False
DOMAIN="yourdomain.com"
SSL_EMAIL="admin@yourdomain.com"

INCLUDE_ENTERPRISE="False"     # True/False

# Calculated Variables
CONFIG_FILE="/etc/${ODOO_USER}.conf"
SERVICE_NAME="${ODOO_USER}.service"
LOG_DIR="/var/log/${ODOO_USER}"

################################################################################
# Start Installation
################################################################################

echo ">>> Starting Odoo $ODOO_VERSION installation for user: $ODOO_USER..."

# === Update & Install Required Packages ===
sudo apt update && sudo apt upgrade -y
sudo apt install -y git python3-pip build-essential wget python3-dev python3-venv \
    libxslt-dev libzip-dev libldap2-dev libsasl2-dev python3-setuptools \
    node-less libjpeg-dev libpq-dev libffi-dev libssl-dev xz-utils xfonts-75dpi

# === PostgreSQL User ===
echo ">>> Setting up PostgreSQL user..."
sudo apt install -y postgresql
sudo -u postgres createuser --createdb --username postgres --no-createrole --no-superuser $ODOO_USER || true

# === Wkhtmltopdf Installation ===
if [ ! -f "/usr/local/bin/wkhtmltopdf" ]; then
    echo ">>> Installing Wkhtmltopdf..."
    sudo wget http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb
    sudo dpkg -i libssl1.1_1.1.1f-1ubuntu2_amd64.deb || sudo apt install -f -y
    sudo wget https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.bionic_amd64.deb
    sudo dpkg -i wkhtmltox_0.12.5-1.bionic_amd64.deb || sudo apt install -f -y
    sudo apt install -f -y
    rm -rf wkhtmltox_0.12.5-1.bionic_amd64.deb libssl1.1_1.1.1f-1ubuntu2_amd64.deb
fi

# === Create Odoo System User ===
sudo adduser --system --quiet --shell=/bin/bash --home=$ODOO_HOME --group $ODOO_USER || true

# === Odoo Source Installation ===
echo ">>> Cloning Odoo $ODOO_VERSION into $ODOO_HOME..."
sudo git clone https://www.github.com/odoo/odoo --branch $ODOO_VERSION --depth=1 $ODOO_HOME/odoo

# === Python Virtual Environment ===
sudo -u $ODOO_USER python3 -m venv $ODOO_HOME/venv
sudo -u $ODOO_USER $ODOO_HOME/venv/bin/pip install --upgrade pip
sudo -u $ODOO_USER $ODOO_HOME/venv/bin/pip install wheel
sudo -u $ODOO_USER $ODOO_HOME/venv/bin/pip install -r $ODOO_HOME/odoo/requirements.txt

# === Log Directory ===
sudo mkdir -p $LOG_DIR
sudo chown $ODOO_USER:$ODOO_USER $LOG_DIR

# === Odoo Configuration ===
echo ">>> Creating configuration: $CONFIG_FILE..."

# Set proxy_mode to True if Nginx is used
PROXY_MODE="False"
if [[ "$INSTALL_NGINX" == "True" ]]; then PROXY_MODE="True"; fi

sudo tee $CONFIG_FILE > /dev/null <<EOF
[options]
admin_passwd = $ADMIN_PASS
db_user = $ODOO_USER
db_port = False
db_host = False
db_password = False
http_port = $ODOO_PORT
gevent_port = $ODOO_LONGPOLLING_PORT
proxy_mode = $PROXY_MODE
logfile = $LOG_DIR/odoo.log
data_dir = $ODOO_HOME/.local/share/Odoo
EOF

# === Addons Path & Enterprise Logic ===
if [[ "$INCLUDE_ENTERPRISE" == "True" ]]; then
    echo ">>> Installing Odoo Enterprise..."
    sudo git clone https://github.com/odoo/enterprise.git --branch $ODOO_VERSION --depth=1 $ODOO_HOME/enterprise
    sudo chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME/enterprise
    sudo -u $ODOO_USER $ODOO_HOME/venv/bin/pip install num2words ofxparse dbfread ebaysdk firebase_admin pyOpenSSL
    sudo su root -c "printf 'addons_path=$ODOO_HOME/enterprise,$ODOO_HOME/odoo/addons\n' >> $CONFIG_FILE"
else
    sudo su root -c "printf 'addons_path=$ODOO_HOME/odoo/addons\n' >> $CONFIG_FILE"
fi

# === Systemd Service for Odoo ===
echo ">>> Creating service: $SERVICE_NAME..."
sudo tee /etc/systemd/system/$SERVICE_NAME > /dev/null <<EOF
[Unit]
Description=Odoo Instance ($ODOO_USER)
After=network.target postgresql.service

[Service]
Type=simple
User=$ODOO_USER
Group=$ODOO_USER
ExecStart=$ODOO_HOME/venv/bin/python3 $ODOO_HOME/odoo/odoo-bin -c $CONFIG_FILE
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME
sudo systemctl restart $SERVICE_NAME

################################################################################
# === Nginx Installation (Optional) ===
################################################################################
if [[ "$INSTALL_NGINX" == "True" ]]; then
    echo ">>> Configuring Nginx for $ODOO_USER..."
    sudo apt install -y nginx

    # We use unique upstream names to avoid conflicts with other Odoo users
    sudo tee /etc/nginx/sites-available/$ODOO_USER > /dev/null <<EOF
upstream ${ODOO_USER}-backend {
  server 127.0.0.1:$ODOO_PORT;
}
upstream ${ODOO_USER}-chat {
  server 127.0.0.1:$ODOO_LONGPOLLING_PORT;
}

server {
  listen 80;
  server_name $DOMAIN;

  access_log /var/log/nginx/${ODOO_USER}.access.log;
  error_log /var/log/nginx/${ODOO_USER}.error.log;

  proxy_read_timeout 720s;
  proxy_connect_timeout 720s;
  proxy_send_timeout 720s;

  location /websocket {
    proxy_pass http://${ODOO_USER}-chat;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header X-Forwarded-Host \$http_host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;
  }

  location / {
    proxy_pass http://${ODOO_USER}-backend;
    proxy_set_header X-Forwarded-Host \$http_host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_redirect off;
  }

  gzip on;
  gzip_types text/css text/scss text/plain text/xml application/xml application/json application/javascript;
}
EOF

    sudo ln -sf /etc/nginx/sites-available/$ODOO_USER /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo systemctl restart nginx
fi

################################################################################
# === SSL Installation (Optional) ===
################################################################################
if [[ "$INSTALL_SSL" == "True" && "$INSTALL_NGINX" == "True" ]]; then
    echo ">>> Installing Let's Encrypt SSL..."
    sudo apt install -y certbot python3-certbot-nginx
    sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $SSL_EMAIL
fi

# Final Permissions fix
sudo chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME

echo "-----------------------------------------------------------"
echo "✅ Installation Completed!"
echo "User: $ODOO_USER"
echo "Config: $CONFIG_FILE"
echo "Service: $SERVICE_NAME"
echo "Log: $LOG_DIR/odoo.log"
echo "Port: $ODOO_PORT"
echo "-----------------------------------------------------------"
