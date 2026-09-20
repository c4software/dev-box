#!/usr/bin/env bash
# Sauvegarde la box : home filtré + dossier des projets, dans une archive
# tar.zst déposée dans <dest_dir> (par défaut ./backups, ignoré par git).
#
# Usage : scripts/backup.sh [--with-tailscale] [dest_dir]
#
# Ce qui est gardé : data/home (sans les caches régénérables), le dossier des
# projets (PROJECTS_DIR, dépôts git complets, .git/objects inclus), et une copie
# de .env et compose.override.yaml s'ils existent.
# Ce qui est exclu par défaut : data/tailscale (identité du nœud, on ne veut pas
# la dupliquer sans le demander) — voir --with-tailscale.
set -euo pipefail

# On travaille toujours depuis la racine du dépôt : les chemins stockés dans
# l'archive sont relatifs à celle-ci, ce qui rend la restauration triviale.
cd "$(dirname "$0")/.."
repo_root="$PWD"

with_tailscale=0
dest_dir=""

for arg in "$@"; do
    case "$arg" in
        --with-tailscale) with_tailscale=1 ;;
        -h|--help)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "Option inconnue : $arg" >&2
            exit 1
            ;;
        *) dest_dir="$arg" ;;
    esac
done

dest_dir="${dest_dir:-./backups}"

# Valeurs issues de .env (TS_HOSTNAME pour nommer l'archive, PROJECTS_DIR pour
# savoir quoi sauvegarder). set -a exporte tout ce qui est défini dans le fichier.
if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091  # .env est généré par l'utilisateur
    . ./.env
    set +a
fi
ts_hostname="${TS_HOSTNAME:-dev-box}"
projects_dir="${PROJECTS_DIR:-./data/projets}"

# tar délègue la compression au binaire zstd : il n'est pas toujours installé
# (image Debian minimale d'un Raspberry Pi par exemple).
if ! command -v zstd >/dev/null 2>&1; then
    echo "zstd introuvable : installez-le (pacman -S zstd / apt install zstd)." >&2
    exit 1
fi

if [ ! -d data/home ]; then
    echo "data/home introuvable : rien à sauvegarder (mauvais dossier ?)" >&2
    exit 1
fi

mkdir -p "$dest_dir"
dest_dir="$(cd "$dest_dir" && pwd)"
archive="$dest_dir/dev-box-${ts_hostname}-$(date +%Y%m%d-%H%M%S).tar.zst"

# Membres de l'archive, en chemins relatifs à la racine du dépôt.
members=(data/home)

# Le dossier des projets est normalement dans le dépôt (./data/projets). S'il
# pointe ailleurs (autre disque), on le range sous projets-external/ dans
# l'archive : la restauration ne doit pas l'écraser au mauvais endroit.
transform=()
projects_abs="$(cd "$projects_dir" 2>/dev/null && pwd || true)"
if [ -z "$projects_abs" ]; then
    echo "Attention : $projects_dir introuvable, projets non sauvegardés." >&2
elif [ "${projects_abs#"$repo_root"/}" != "$projects_abs" ]; then
    members+=("${projects_abs#"$repo_root"/}")
else
    members+=("$projects_abs")
    transform+=(--transform "s,^${projects_abs#/},projets-external,")
    echo "Note : PROJECTS_DIR est hors du dépôt ($projects_abs)."
    echo "       Il sera archivé sous projets-external/ et devra être remis en place à la main."
fi

if [ -f .env ]; then members+=(.env); fi
if [ -f compose.override.yaml ]; then members+=(compose.override.yaml); fi
if [ "$with_tailscale" -eq 1 ] && [ -d data/tailscale ]; then
    members+=(data/tailscale)
fi

# Caches et artefacts régénérables : inutiles, volumineux, et reconstruits au
# premier démarrage ou au premier `mise install`.
excludes=(
    --exclude=data/home/.cache
    --exclude=data/home/.local/share/mise
    --exclude=data/home/.local/share/nvim
    --exclude=data/home/.local/state/nvim
    --exclude=data/home/.local/share/dotarchy
    --exclude=data/home/.local/share/containers
    --exclude=data/home/.local/share/lazyvim-starter
    --exclude=data/home/.npm
    --exclude=data/home/.bun
    --exclude='*/node_modules'
)

# data/home peut contenir des fichiers root (et data/tailscale est root:root) :
# on ne passe par sudo que si quelque chose n'est pas lisible tel quel.
# Le test ignore ce que tar exclura de toute façon (les caches mise contiennent
# des liens cassés) ainsi que les liens symboliques (tar les archive sans les
# suivre). Le dossier ~/projets, point de montage créé par Docker, est un
# répertoire root mais lisible : il ne pose pas de problème.
prune=()
for e in "${excludes[@]}"; do
    pat="${e#--exclude=}"
    case "$pat" in
        \*/*) prune+=(-name "${pat#*/}" -prune -o) ;;
        *)    prune+=(-path "$pat" -prune -o) ;;
    esac
done
sudo_cmd=()
unreadable=""
for m in "${members[@]}"; do
    [ -e "$m" ] || continue
    if ! find "$m" "${prune[@]}" -print >/dev/null 2>&1 \
       || [ -n "$(find "$m" "${prune[@]}" ! -type l ! -readable -print -quit 2>/dev/null)" ]; then
        unreadable="$m"
        break
    fi
done
if [ -n "$unreadable" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        : # déjà root
    elif command -v sudo >/dev/null 2>&1; then
        echo "Fichiers non lisibles dans $unreadable : passage par sudo."
        sudo_cmd=(sudo)
    else
        echo "Fichiers non lisibles dans $unreadable et sudo absent." >&2
        exit 1
    fi
fi

echo "Archive : $archive"
# --numeric-owner : on conserve les UID/GID (1000:1000 côté box, root pour
# tailscale) sans dépendre des noms d'utilisateurs de la machine de restauration.
"${sudo_cmd[@]}" tar --zstd --numeric-owner \
    "${excludes[@]}" \
    "${transform[@]}" \
    -cf "$archive" \
    "${members[@]}"

# L'archive créée sous sudo appartiendrait à root : on la rend à l'utilisateur.
if [ "${#sudo_cmd[@]}" -gt 0 ]; then
    sudo chown "$(id -u):$(id -g)" "$archive"
fi

# Vérification : on relit l'archive de bout en bout (décompression incluse).
count="$(tar -tf "$archive" | wc -l)"
size="$(du -h "$archive" | cut -f1)"
echo "OK : $count entrées, $size"
