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
    node-less libjpeg-dev libpq-dev libffi-dev libssl-dev xz-utils xfonts-75dpi

# === PostgreSQL Installation ===
echo ">>> Installing PostgreSQL..."
sudo apt install -y postgresql
sudo -u postgres createuser --createdb --username postgres --no-createrole --no-superuser $ODOO_USER || true

# === Wkhtmltopdf Installation ===
echo ">>> Installing Wkhtmltopdf and it's related dependancy..."
sudo wget http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb
sudo dpkg -i libssl1.1_1.1.1f-1ubuntu2_amd64.deb
sudo wget https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.bionic_amd64.deb
sudo dpkg -i wkhtmltox_0.12.5-1.bionic_amd64.deb
sudo apt install -f -y
rm wkhtmltox_0.12.6-1.focal_amd64.deb
rm libssl1.1_1.1.1f-1ubuntu2_amd64.deb

# === Create Odoo User ===
sudo adduser --system --quiet --shell=/bin/bash --home=$ODOO_HOME --group $ODOO_USER || true

# === Odoo Source Installation ===
echo ">>> Installing Odoo Community Edition..."
sudo git clone https://www.github.com/odoo/odoo --branch $ODOO_VERSION --depth=1 $ODOO_HOME/odoo

# === Python Virtual Environment ===
sudo -u $ODOO_USER python3 -m venv $ODOO_HOME/venv
sudo -u $ODOO_USER $ODOO_HOME/venv/bin/pip install wheel
sudo -u $ODOO_USER $ODOO_HOME/venv/bin/pip install -r $ODOO_HOME/odoo/requirements.txt

# === Log Directory ===
sudo mkdir /var/log/odoo
sudo chown $ODOO_USER:$ODOO_USER /var/log/odoo

# === Odoo Configuration ===
echo ">>> Creating /etc/odoo.conf..."
sudo tee /etc/odoo.conf > /dev/null <<EOF
[options]
admin_passwd = $ADMIN_PASS
csv_internal_sep = ,
data_dir = /opt/odoo/.local/share/Odoo
db_host = False
db_maxconn = 64
db_maxconn_gevent = False
db_name = False
db_password = False
db_port = False
db_replica_host = False
db_replica_port = False
db_sslmode = prefer
db_template = template0
db_user = $ODOO_USER
dbfilter =
email_from = False
from_filter = False
geoip_city_db = /usr/share/GeoIP/GeoLite2-City.mmdb
geoip_country_db = /usr/share/GeoIP/GeoLite2-Country.mmdb
gevent_port = $ODOO_LONGPOLLING_PORT
http_enable = True
http_interface =
http_port = $ODOO_PORT
import_partial =
list_db = True
log_db = False
log_db_level = warning
log_handler = :INFO
log_level = info
logfile = /var/log/odoo/odoo.log
max_cron_threads = 2
osv_memory_count_limit = 0
pg_path =
pidfile =
pre_upgrade_scripts =
proxy_mode = False
reportgz = False
screencasts =
screenshots = /tmp/odoo_tests
server_wide_modules = base,web
smtp_password = False
smtp_port = 25
smtp_server = localhost
smtp_ssl = False
smtp_ssl_certificate_filename = False
smtp_ssl_private_key_filename = False
smtp_user = False
syslog = False
test_enable = False
test_file =
test_tags = None
transient_age_limit = 1.0
translate_modules = ['all']
unaccent = False
upgrade_path =
websocket_keep_alive_timeout = 3600
websocket_rate_limit_burst = 10
websocket_rate_limit_delay = 0.2
without_demo = False
workers = 0
limit_memory_hard = 2684354560
limit_memory_hard_gevent = False
limit_memory_soft = 2147483648
limit_memory_soft_gevent = False
limit_request = 65536
limit_time_cpu = 60
limit_time_real = 120
limit_time_real_cron = -1
limit_time_worker_cron = 0
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
ExecStart=$ODOO_HOME/venv/bin/python3 $ODOO_HOME/odoo/odoo-bin -c /etc/odoo.conf
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable odoo
sudo systemctl restart odoo


if [[ "$INCLUDE_ENTERPRISE" == "True" ]]; then
    echo ">>> Installing Odoo Enterprise + Community..."
    sudo mkdir -p $ODOO_HOME/enterprise
    sudo git clone https://github.com/odoo/enterprise.git --branch $ODOO_VERSION --depth=1 $ODOO_HOME/enterprise
    sudo chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME/enterprise
    sudo -u $ODOO_USER $ODOO_HOME/venv/bin/pip install num2words ofxparse dbfread ebaysdk firebase_admin pyOpenSSL
    sudo apt install -y nodejs npm
    sudo npm install -g less
    sudo npm install -g less-plugin-clean-css
    sudo su root -c "printf 'addons_path=$ODOO_HOME/odoo/addons,$ODOO_HOME/odoo/odoo/addons,$ODOO_HOME/enterprise\n' >> /etc/odoo.conf"
else
    echo ">>> Installing Odoo Community Edition only..."
    sudo su root -c "printf 'addons_path=$ODOO_HOME/odoo/addons,$ODOO_HOME/odoo/odoo/addons\n' >> /etc/odoo.conf"
fi
sudo chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME

################################################################################
# === Nginx Installation (Optional) ===
################################################################################
if [[ "$INSTALL_NGINX" == "True" ]]; then
    echo ">>> Installing and Configuring Nginx..."
    sudo apt install -y nginx

    sudo tee /etc/nginx/sites-available/odoo > /dev/null <<EOF
#odoo server
upstream odoo {
  server 127.0.0.1:$ODOO_PORT;
}
upstream odoochat {
  server 127.0.0.1:$ODOO_LONGPOLLING_PORT;
}
map \$http_upgrade \$connection_upgrade {
  default upgrade;
  ''      close;
}

server {
  listen 80;
  server_name $DOMAIN;
  proxy_read_timeout 720s;
  proxy_connect_timeout 720s;
  proxy_send_timeout 720s;

  # log
  access_log /var/log/nginx/odoo.access.log;
  error_log /var/log/nginx/odoo.error.log;

  # Redirect websocket requests to odoo gevent port
  location /websocket {
    proxy_pass http://odoochat;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header X-Forwarded-Host \$http_host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
    proxy_cookie_flags session_id samesite=lax secure;  # requires nginx 1.19.8
  }

  # Redirect requests to odoo backend server
  location / {
    # Add Headers for odoo proxy mode
    proxy_set_header X-Forwarded-Host \$http_host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_redirect off;
    proxy_pass http://odoo;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
    proxy_cookie_flags session_id samesite=lax secure;  # requires nginx 1.19.8
  }

  # common gzip
  gzip_types text/css text/scss text/plain text/xml application/xml application/json application/javascript;
  gzip on;
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
