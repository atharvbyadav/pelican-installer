# Pelican Installer

Universal one-line installer for Pelican Panel & Wings.

Works on:

- Ubuntu 20.04+
- Debian 11+
- WSL2

---

## Quick Install

### With **_http_**:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/atharvbyadav/Pelican-Installer/main/install.sh)
```

### With **_https_**:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/atharvbyadav/Pelican-Installer/https/install.sh)
```

---

## What This Installs

* PHP 8.4 + extensions
* MariaDB
* NGINX
* Docker CE
* Pelican Panel
* Wings
* Firewall rules
* systemd services

---

## Installer Options

```
1) Install Panel only
2) Install Wings only
3) Install Panel + Wings
```

---

## Panel After Install

Visit:

```
http://YOUR_IP/installer
```

Database:

```
DB: pelican
User: pelican
Password: (you entered)
```

---

## Wings After Install

Paste node configuration:

```
/etc/pelican/config.yml
```

Then start:

```bash
sudo systemctl enable --now wings
```

---

## Updating

Just run the same one-line command again.

---
