#!/usr/bin/env bash
# Restaure une archive produite par scripts/backup.sh, à la racine du dépôt.
#
# Usage : scripts/restore.sh <archive.tar.zst> [--yes]
#
# Le conteneur est arrêté avant l'extraction, puis l'archive est déballée par
# dessus l'existant : rien n'est supprimé, seuls les fichiers présents dans
# l'archive sont écrasés. --yes saute la confirmation (obligatoire hors terminal).
set -euo pipefail

cd "$(dirname "$0")/.."

archive=""
assume_yes=0

for arg in "$@"; do
    case "$arg" in
        --yes|-y) assume_yes=1 ;;
        -h|--help)
            sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "Option inconnue : $arg" >&2
            exit 1
            ;;
        *) archive="$arg" ;;
    esac
done

# Même dépendance que pour la sauvegarde : tar appelle le binaire zstd.
if ! command -v zstd >/dev/null 2>&1; then
    echo "zstd introuvable : installez-le (pacman -S zstd / apt install zstd)." >&2
    exit 1
fi

if [ -z "$archive" ]; then
    echo "Usage : scripts/restore.sh <archive.tar.zst> [--yes]" >&2
    exit 1
fi
if [ ! -f "$archive" ]; then
    echo "Archive introuvable : $archive" >&2
    exit 1
fi
archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"

# Contenu de l'archive : on s'en sert pour lister ce qui existe déjà et va donc
# être écrasé, et pour savoir s'il faut sudo (entrées appartenant à un autre UID).
mapfile -t entries < <(tar -tf "$archive")
if [ "${#entries[@]}" -eq 0 ]; then
    echo "Archive vide : $archive" >&2
    exit 1
fi

echo "Archive : $archive (${#entries[@]} entrées)"
echo "Racines restaurées :"
printf '%s\n' "${entries[@]}" | awk -F/ '{print $1}' | sort -u | sed 's/^/  - /'

existing=()
for top in $(printf '%s\n' "${entries[@]}" | awk -F/ '{print $1}' | sort -u); do
    if [ -e "$top" ]; then existing+=("$top"); fi
done
if [ "${#existing[@]}" -gt 0 ]; then
    echo "Déjà présent, sera écrasé fichier par fichier (rien n'est supprimé) :"
    printf '  ! %s\n' "${existing[@]}"
else
    echo "Rien d'existant ne sera écrasé."
fi

if printf '%s\n' "${entries[@]}" | grep -q '^projets-external/'; then
    echo "Note : l'archive contient projets-external/ (PROJECTS_DIR hors du dépôt)."
    echo "       Il sera extrait ici, à remettre en place à la main."
fi

# Confirmation : refus pur et simple si on n'est pas dans un terminal.
if [ "$assume_yes" -eq 0 ]; then
    if [ ! -t 0 ]; then
        echo "Mode non interactif : relancer avec --yes pour confirmer." >&2
        exit 1
    fi
    read -r -p "Restaurer dans $PWD ? [y/N] " answer
    case "$answer" in
        y|Y|yes|YES) ;;
        *) echo "Annulé."; exit 1 ;;
    esac
fi

# Le conteneur doit être arrêté : il écrit en permanence dans le home monté.
if command -v docker >/dev/null 2>&1; then
    echo "Arrêt du conteneur..."
    docker compose stop || echo "docker compose stop a échoué (conteneur déjà arrêté ?)"
else
    echo "docker absent : arrêt du conteneur ignoré."
fi

# Restaurer des fichiers appartenant à un autre UID (root pour data/tailscale)
# demande les droits ; sinon on extrait tel quel sous l'utilisateur courant.
sudo_cmd=()
if [ "$(id -u)" -ne 0 ] && tar --numeric-owner -tvf "$archive" \
        | awk -v me="$(id -u)" '{split($2, o, "/"); if (o[1] != me) found=1} END {exit !found}'; then
    if command -v sudo >/dev/null 2>&1; then
        echo "L'archive contient des fichiers d'un autre utilisateur : passage par sudo."
        sudo_cmd=(sudo)
    else
        echo "Attention : sudo absent, les propriétaires ne seront pas restaurés." >&2
    fi
fi

"${sudo_cmd[@]}" tar --zstd --numeric-owner -xpf "$archive" -C "$PWD"

echo "Restauration terminée."
echo "Relancer la box : just up"
