# Commandes côté hôte pour piloter la box (just >= 1.30).
# Les variables de .env sont chargées et exportées dans l'environnement des
# recettes : on les lit avec ${VAR:-defaut} directement dans le shell.
set dotenv-load

# Nom du conteneur (container_name dans compose.yaml).
container := "dev-box"

# Commit du dépôt, gravé dans l'image au build (cf. compose.yaml) : le contrôle
# des mises à jour dans la box sait alors si l'image est en retard sur le dépôt.
export DEVBOX_COMMIT := `git rev-parse HEAD 2>/dev/null || echo unknown`
export DEVBOX_REPO := `git remote get-url origin 2>/dev/null || true`
export DEVBOX_BRANCH := `git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main`

# Liste les commandes disponibles.
default:
    @just --list

# Construit l'image si besoin et démarre la box.
up:
    docker compose up -d --build

# --pull récupère un archlinux:latest plus récent, --no-cache force la
# ré-exécution du `pacman -Syu` : sans lui la couche pacman reste en cache tant
# que l'image de base n'a pas changé de digest, et les paquets resteraient figés
# à la date du premier build.

# Met à jour Arch (image de base + paquets) et redémarre la box.
rebuild:
    docker compose build --pull --no-cache
    docker compose up -d

# Arrête et supprime le conteneur (les volumes ./data/ sont conservés).
down:
    docker compose down

# Redémarre le conteneur sans reconstruire.
restart:
    docker compose restart

# Suit les logs de l'entrypoint (dotarchy-sync, tailscale up, ...).
logs:
    docker compose logs -f --tail=100

# État du conteneur, du healthcheck, et de l'image par rapport au dépôt.
status:
    #!/usr/bin/env bash
    set -euo pipefail
    docker compose ps
    docker inspect -f 'health: {{{{ .State.Health.Status }} ({{{{ len .State.Health.Log }} check(s))' {{ container }} 2>/dev/null \
      || echo "health: n/a (conteneur arrêté ou sans healthcheck)"
    # Commit gravé dans l'image (cf. compose.yaml) contre le dépôt local : c'est
    # la comparaison que la box ne peut pas faire seule si le dépôt est privé.
    built="$(docker run --rm --entrypoint sh dev-box-dev-box -c '. /etc/devbox/release && echo "$DEVBOX_COMMIT"' 2>/dev/null || echo unknown)"
    head="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
    if [ "$built" = unknown ]; then
        echo "image : commit inconnu (construite sans just), just rebuild pour le graver"
    elif [ "$built" = "$head" ]; then
        echo "image : à jour (${built:0:7})"
    else
        echo "image : construite sur ${built:0:7}, dépôt à ${head:0:7} → just rebuild"
    fi

# Ouvre un shell zsh de login dans la box, en tant qu'utilisateur.
shell:
    docker exec -it -u "${USER_NAME:-dev}" {{ container }} zsh -l

# Se connecte en SSH : via Tailscale, ou via le port publié si TS_DISABLE=true.
ssh:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "${TS_DISABLE:-false}" = "true" ]; then
        ssh -p "${SSH_PORT:-2222}" "${USER_NAME:-dev}@${SSH_BIND:-127.0.0.1}"
    else
        ssh "${USER_NAME:-dev}@${TS_HOSTNAME:-dev-box}"
    fi

# Met à jour la box (dotfiles, outils mise, conf livrée) : dev-box-update
# accepte dotfiles|tools|seed|all, all par défaut.
update what="":
    docker exec -it -u "${USER_NAME:-dev}" {{ container }} zsh -lc "dev-box-update {{ what }}"

# Sauvegarde le home filtré et les projets dans une archive tar.zst.
backup dest="":
    ./scripts/backup.sh "{{ dest }}"

# Restaure une archive produite par `just backup`.
restore archive:
    ./scripts/restore.sh "{{ archive }}"
