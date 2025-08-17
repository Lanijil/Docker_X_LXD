#!/usr/bin/env bash
set -euo pipefail

# Usage
if [ $# -ne 2 ]; then
  echo "Usage: $0 nom_projet port_web"
  exit 1
fi
PROJ="$1"
PORT="$2"

# 1) Prérequis LXD (via snap)
if ! command -v lxc >/dev/null 2>&1; then
  echo "LXD n'est pas installé. Installe-le avec: sudo snap install lxd"
  exit 1
fi
if ! lxc info >/dev/null 2>&1; then
  echo "LXD n'est pas initialisé. Lance: sudo lxd init"
  exit 1
fi

# 2) (Re)création propre des conteneurs
WEB_C="${PROJ}apache"
DB_C="${PROJ}mariadb"

lxc delete "$WEB_C" --force >/dev/null 2>&1 || true
lxc delete "$DB_C" --force >/dev/null 2>&1 || true

echo "[+] Création conteneurs LXD ($WEB_C, $DB_C)…"
lxc launch ubuntu:22.04 "$WEB_C"
lxc launch ubuntu:22.04 "$DB_C"

# Attente courte que le DHCP attribue une IP
sleep 5

# 3) Install & enable services
echo "[+] Installation Apache…"
lxc exec "$WEB_C" -- bash -lc "apt-get update -qq && apt-get install -y apache2 iptables-persistent && systemctl enable --now apache2"

echo "[+] Installation MariaDB…"
lxc exec "$DB_C" -- bash -lc "apt-get update -qq && apt-get install -y mariadb-server iptables-persistent && systemctl enable --now mariadb"

# 4) Récup IP du web (méthode robuste)
WEB_IP="$(lxc list "$WEB_C" -c 4 --format csv | awk -F'[ ,]+' '{print $1; exit}')"
if [ -z "${WEB_IP:-}" ]; then
  echo "Impossible de récupérer l'IP de $WEB_C"
  exit 1
fi
echo "[i] IP Web: $WEB_IP"

# 5) Exposer port HTTP du web vers l’hôte (proxy device)
#    Noms de devices uniques pour éviter les collisions si on relance
DEV_PROXY="http-proxy-${PROJ}"
lxc config device remove "$WEB_C" "$DEV_PROXY" >/dev/null 2>&1 || true
lxc config device add "$WEB_C" "$DEV_PROXY" proxy listen="tcp:0.0.0.0:${PORT}" connect="tcp:127.0.0.1:80"

# 6) Dossier partagé hôte -> conteneur web
HOST_DIR="$(pwd)/${PROJ}_web"
mkdir -p "$HOST_DIR"
DEV_DISK="shared-${PROJ}"
lxc config device remove "$WEB_C" "$DEV_DISK" >/dev/null 2>&1 || true
lxc config device add "$WEB_C" "$DEV_DISK" disk source="$HOST_DIR" path="/var/www/html"
echo "[i] Dossier web partagé: $HOST_DIR"

# 7) Sécurisation MariaDB: root + DB + user restreint à l’IP du web
DB_ROOT="rootpass"
DB_NAME="${PROJ}_db"
DB_USER="${PROJ}_user"
DB_PASS="pass"

lxc exec "$DB_C" -- bash -lc "mysql -uroot <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT}';
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'${WEB_IP}' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'${WEB_IP}';
FLUSH PRIVILEGES;
EOF"

# 8) Pare-feu DANS les conteneurs (persistant)
# DB: n'accepte 3306 que depuis le web
lxc exec "$DB_C" -- bash -lc "
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp -s ${WEB_IP} --dport 3306 -j ACCEPT
iptables-save > /etc/iptables/rules.v4
"

# Web: n’accepte que 80
lxc exec "$WEB_C" -- bash -lc "
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables-save > /etc/iptables/rules.v4
"

echo
echo "[OK] Conteneurs prêts pour le projet '${PROJ}'."
echo "    Web:   http://localhost:${PORT}  (via proxy device)"
echo "    Dossier web: ${HOST_DIR}"
echo "    DB:    ${DB_NAME} (user: ${DB_USER} / pass: ${DB_PASS} / host autorisé: ${WEB_IP})"
echo
echo "Si tu utilises un reverse-proxy Docker, pointe-le vers 127.0.0.1:${PORT}."
