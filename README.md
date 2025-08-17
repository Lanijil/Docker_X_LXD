# TP – Conteneurisation Hybride (Docker + LXD)

## Sommaire
- [Objectifs](#objectifs)
- [Arborescence](#arborescence)
- [Prérequis](#prérequis)
- [Partie 1 — Docker (état actuel)](#partie-1--docker-état-actuel)
- [Partie 2 — LXD (état cible)](#partie-2--lxd-état-cible)
- [Migration Docker → LXD](#migration-docker--lxd)
- [Sécurité](#sécurité)
- [Dépannage](#dépannage)

## Objectifs
- Infra **Docker** : Apache + MariaDB + reverse proxy Nginx.
- Infra **LXD** : Apache + MariaDB, dossier partagé hôte→web, exposition via proxy device, **DB accessible uniquement depuis le web**.
- **Reverse proxy** conservé sous Docker en cible.
- Procédures de **déploiement manuel** et de **migration**.

## Arborescence
.
├─ docker/
│ ├─ web/ # Dockerfile Apache
│ ├─ db/ # Dockerfile MariaDB
│ └─ reverse-proxy/ # Dockerfile Nginx + nginx.conf
├─ projects/
│ ├─ site1/www/ # contenu web (Docker)
│ └─ site2/www/ # contenu web (LXD)
└─ scripts/
├─ lxd_deploy.sh # déploiement LXD (web+db, firewall, proxy, shared dir)
└─ (option) lxd_remove.sh

## Prérequis
- Linux récent, `sudo`.
- **Docker** : `sudo apt install -y docker.io && sudo systemctl enable --now docker`
- **LXD** : `sudo snap install lxd && sudo lxd init`

## Partie 1 — Docker (état actuel)
### Build

docker build -t company01-web:22.04 ./docker/web
docker build -t company01-db:11    ./docker/db
docker build -t company01-rp:stable ./docker/reverse-proxy
Déploiement manuel (exemple site1 sur port 8081)

docker network create net_site1

docker run -d --name db_site1 --network net_site1 \
  -e MARIADB_ROOT_PASSWORD=rootpass \
  -e MARIADB_DATABASE=site1_db \
  -e MARIADB_USER=site1_user \
  -e MARIADB_PASSWORD=pass \
  company01-db:11

docker run -d --name web_site1 --network net_site1 \
  -p 8081:80 \
  -v "$PWD/projects/site1/www:/var/www/html:rw" \
  company01-web:22.04

docker run -d --name reverse-proxy -p 80:80 company01-rp:stable

Vérifs

curl -s http://localhost:8081 | head -n1   # direct
curl -s http://localhost      | head -n1   # via RP
