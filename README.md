# TP Conteneurisation Hybride – Docker & LXD
Groupe : Jilani LESSUEUR, Benit Landry MUSINDI, Aichä Khefif
Ce projet illustre une approche **hybride de la conteneurisation** en deux étapes :
- **Partie 1 : Infrastructure de base sous Docker**
- **Partie 2 : Infrastructure cible sous LXD (avec reverse proxy Docker)**

---

## Partie 1 – Infra de base (Docker)

L’infrastructure initiale repose uniquement sur **Docker** :
- Un conteneur **Apache/PHP** qui héberge le site `site1`.
- Un conteneur **MariaDB** pour la base de données.
- Un conteneur **Reverse Proxy** (NGINX) exposé en frontal.
- Un réseau Docker privé pour la communication inter-containers.

 Répertoires concernés :
- `docker/` → Dockerfiles (Apache, MariaDB, Reverse Proxy)
- `projects/site1/www/` → contenu du site web

Lancement manuel :
```bash
# Construction et lancement
docker build -t site1-apache docker/apache
docker build -t site1-mariadb docker/mariadb
docker build -t reverse-proxy docker/reverse-proxy
```
```bash
# Création du réseau et démarrage
docker network create site1-net
docker run -d --name site1-apache --network site1-net site1-apache
docker run -d --name site1-mariadb --network site1-net site1-mariadb
docker run -d -p 8081:80 --name reverse-proxy --network site1-net reverse-proxy
```
##  Partie 2 – Infra cible (LXD + Reverse Proxy Docker)

L’infrastructure visée repose sur :
Deux conteneurs LXD :
- site2apache (Apache/PHP)
- site2mariadb (MariaDB)

Une configuration iptables sur site2mariadb qui restreint l’accès uniquement à site2apache.
Un partage de données entre Apache et MariaDB.
Le Reverse Proxy Docker reste utilisé pour exposer les services.

📂 Répertoires concernés :
scripts/lxd_deploy.sh → script d’automatisation du déploiement
projects/site2/www/ → contenu du site web migré

⚙️ Lancement automatisé :

# Déploiement LXD (exemple pour site2 sur port 8082)
./scripts/lxd_deploy.sh site2 8082

👉 Ce script crée automatiquement :
- Les conteneurs LXD site2apache et site2mariadb
- La configuration réseau
- Le pare-feu iptables (port 3306 limité à Apache)
- Le déploiement du site web
