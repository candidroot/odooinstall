#!/bin/bash
################################################################################
# Odoo 18 Installation Script (Parameter Based)
# Controlled by variables at the top of this script
################################################################################

# === Parameters ===
ODOO_USER="odoo"
ODOO_HOME="/opt/odoo"
ODOO_VERSION="18.0"
ODOO_PORT="8069"
ODOO_LONGPOLLING_PORT="8072"
ADMIN_PASS="admin"

INSTALL_NGINX="False"   # True/False
INSTALL_SSL="False"     # True/False
DOMAIN="yourdomain.com"
SSL_EMAIL="admin@yourdomain.com"

INCLUDE_ENTERPRISE="False"  # True/False to include Odoo Enterprise

################################################################################
# Start Installation
################################################################################

echo ">>> Starting Odoo $ODOO_VERSION installation..."

# === Update & Install Required Packages ===
sudo apt update && sudo apt upgrade -y
sudo apt install -y git python3-pip build-essential wget python3-dev python3-venv \
    libxslt-dev libzip-dev libldap2-dev libsasl2-dev python3-setuptools \
    node-less libjpeg-dev libpq-dev libffi-dev libssl-dev xz-utils

# === PostgreSQL Installation ===
echo ">>> Installing PostgreSQL..."
sudo apt install -y postgresql
sudo -u postgres createuser --createdb --username postgres --no-createrole --no-superuser $ODOO_USER || true

# === Wkhtmltopdf Installation ===
echo ">>> Installing Wkhtmltopdf..."
wget https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.6/wkhtmltox_0.12.6-1.focal_amd64.deb
sudo apt install -y ./wkhtmltox_0.12.6-1.focal_amd64.deb
rm wkhtmltox_0.12.6-1.focal_amd64.deb

# === Create Odoo User ===
sudo adduser --system --quiet --shell=/bin/bash --home=$ODOO_HOME --group $ODOO_USER || true

# === Odoo Source Installation ===
if [[ "$INCLUDE_ENTERPRISE" == "True" ]]; then
    echo ">>> Installing Odoo Enterprise + Community..."
    sudo mkdir -p $ODOO_HOME/enterprise
    sudo git clone https://www.github.com/odoo/odoo --branch $ODOO_VERSION --depth=1 $ODOO_HOME
    # Here you should also add enterprise addons repository (requires access token)
else
    echo ">>> Installing Odoo Community Edition..."
    sudo git clone https://www.github.com/odoo/odoo --branch $ODOO_VERSION --depth=1 $ODOO_HOME
fi
sudo chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME

# === Python Virtual Environment ===
sudo -u $ODOO_USER python3 -m venv $ODOO_HOME/venv
sudo -u $ODOO_USER $ODOO_HOME/venv/bin/pip install wheel
sudo -u $ODOO_USER $ODOO_HOME/venv/bin/pip install -r $ODOO_HOME/requirements.txt

# === Log Directory ===
sudo mkdir /var/log/odoo
sudo chown $ODOO_USER:$ODOO_USER /var/log/odoo

# === Odoo Configuration ===
echo ">>> Creating /etc/odoo.conf..."
sudo tee /etc/odoo.conf > /dev/null <<EOF
[options]
admin_passwd = $ADMIN_PASS
db_host = False
db_port = False
db_user = $ODOO_USER
db_password = False
addons_path = $ODOO_HOME/addons
logfile = /var/log/odoo/odoo.log
xmlrpc_port = $ODOO_PORT
longpolling_port = $ODOO_LONGPOLLING_PORT
workers = 2
max_cron_threads = 1
limit_memory_hard = 2684354560
limit_memory_soft = 2147483648
limit_request = 8192
limit_time_cpu = 60
limit_time_real = 120
proxy_mode = True
EOF

# === Systemd Service for Odoo ===
echo ">>> Creating odoo.service..."
sudo tee /etc/systemd/system/odoo.service > /dev/null <<EOF
[Unit]
Description=Odoo
After=network.target postgresql.service

[Service]
Type=simple
User=$ODOO_USER
ExecStart=$ODOO_HOME/venv/bin/python3 $ODOO_HOME/odoo-bin -c /etc/odoo.conf
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable odoo
sudo systemctl restart odoo

################################################################################
# === Nginx Installation (Optional) ===
################################################################################
if [[ "$INSTALL_NGINX" == "True" ]]; then
    echo ">>> Installing and Configuring Nginx..."
    sudo apt install -y nginx

    sudo tee /etc/nginx/sites-available/odoo > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;

    access_log /var/log/nginx/odoo_access.log;
    error_log /var/log/nginx/odoo_error.log;

    location / {
        proxy_pass http://127.0.0.1:$ODOO_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /longpolling {
        proxy_pass http://127.0.0.1:$ODOO_LONGPOLLING_PORT;
    }

    location ~* /web/static/ {
        proxy_cache_valid 200 90m;
        proxy_buffering on;
        expires 864000;
        proxy_pass http://127.0.0.1:$ODOO_PORT;
    }
}
EOF

    sudo ln -s /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo systemctl restart nginx
else
    echo ">>> Nginx installation skipped (INSTALL_NGINX=False)."
fi

################################################################################
# === SSL Installation (Optional) ===
################################################################################
if [[ "$INSTALL_SSL" == "True" && "$INSTALL_NGINX" == "True" ]]; then
    echo ">>> Installing Let's Encrypt SSL..."
    sudo apt install -y certbot python3-certbot-nginx
    sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $SSL_EMAIL
    echo ">>> ✅ SSL successfully installed for $DOMAIN"
elif [[ "$INSTALL_SSL" == "True" && "$INSTALL_NGINX" == "False" ]]; then
    echo ">>> ⚠️ Cannot install SSL because Nginx is not installed. Set INSTALL_NGINX=True first."
else
    echo ">>> SSL installation skipped (INSTALL_SSL=False)."
fi

################################################################################
# === Finish ===
################################################################################
echo ">>> ✅ Odoo Installation Completed!"
if [[ "$INSTALL_SSL" == "True" && "$INSTALL_NGINX" == "True" ]]; then
    echo "Access your Odoo at: https://$DOMAIN"
elif [[ "$INSTALL_NGINX" == "True" ]]; then
    echo "Access your Odoo at: http://$DOMAIN"
else
    echo "Access your Odoo at: http://<server-ip>:$ODOO_PORT"
fi
