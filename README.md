# 🚀 Odoo Automated Installation Script

This repository contains a **Bash script (`odooinstall.sh`)** to install **Odoo 18** with optional components such as **Nginx reverse proxy**, **Let’s Encrypt SSL**, and **Odoo Enterprise** support.

## ✅ Features
- Installs **Odoo 18 (Community or Enterprise)**
- Installs and configures **PostgreSQL**
- Installs **wkhtmltopdf** (for PDF report generation)
- Optional: **Nginx Reverse Proxy**
- Optional: **Let’s Encrypt SSL (Certbot)**
- Supports **longpolling** configuration for live chat/POS
- Pre-configured **systemd service** (`odoo.service`)
- Uses a parameterized configuration for easy customization

## ⚙️ Parameters
Edit these variables at the top of `odooinstall.sh`:

```
ODOO_USER="odoo"
ODOO_HOME="/opt/odoo"
ODOO_VERSION="18.0"
ODOO_PORT="8069"
ODOO_LONGPOLLING_PORT="8072"
ADMIN_PASS="admin"

INSTALL_NGINX="False"   # True to install and configure Nginx
INSTALL_SSL="False"     # True to enable SSL (requires Nginx)
DOMAIN="yourdomain.com"
SSL_EMAIL="admin@yourdomain.com"

INCLUDE_ENTERPRISE="False" # True to include Odoo Enterprise repository
```

## 🛠️ Installation Steps
```bash
git clone https://github.com/candidroot/odooinstall.git
cd odooinstall
chmod +x odooinstall.sh
sudo ./odooinstall.sh
```

## 🌐 Accessing Odoo
- Without Nginx: `http://<server-ip>:8069`
- With Nginx: `http://yourdomain.com`
- With SSL: `https://yourdomain.com`

## 🔒 SSL Notes
- SSL requires Nginx to be enabled.
- Ensure the domain points to the server before enabling SSL.

## 🏢 Odoo Enterprise
- Set `INCLUDE_ENTERPRISE="True"` and configure your private repository with a valid token.

## 📂 Installed Files
- Source: `/opt/odoo`
- Config: `/etc/odoo.conf`
- Logs: `/var/log/odoo/odoo.log`
- Service: `/etc/systemd/system/odoo.service`

## 🛑 Uninstallation
```bash
sudo systemctl stop odoo
sudo systemctl disable odoo
sudo rm -rf /opt/odoo /var/log/odoo /etc/odoo.conf /etc/systemd/system/odoo.service
```

## 🤝 Contributions
Fork the repo, open issues, and submit PRs.

## 📜 License
Released under the **MIT License**.