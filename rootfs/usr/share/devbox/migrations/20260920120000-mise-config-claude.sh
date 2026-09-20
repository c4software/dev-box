#!/usr/bin/env bash
# Conf mise des boxes créées avant l'arrivée de claude et codex.
#
# La toute première version livrée déclarait node, pi (via
# npm:@earendil-works/pi-coding-agent) et omp, mais ni claude ni codex. Le seed
# ne peut pas la remplacer : elle est « identique à la référence » seulement
# pour les boxes qui avaient déjà la référence, et sur les plus anciennes il
# n'y en a pas, donc dev-box-seed l'adopte telle quelle et ne touche plus à
# rien.
#
# Cette migration ne remplace le fichier que s'il est mot pour mot une des
# versions livrées jadis : une conf modifiée à la main n'est jamais écrasée.
set -euo pipefail

CFG="$HOME/.config/mise/config.toml"

# sha256 des versions livrées jadis qui ne déclarent ni claude ni codex.
OLD_SUMS=(
  5f70393fcc9f39339bef540b9bbfae21e265837b0c484cb3313e70d5e7d8c3fe
)

if [ ! -f "$CFG" ]; then
  echo "  ~/.config/mise/config.toml absent : rien à faire (dev-box-seed le posera)"
  exit 0
fi

if grep -Eq '^[[:space:]]*"?(claude|codex)"?[[:space:]]*=' "$CFG"; then
  echo "  conf mise déjà à jour (claude ou codex déclaré) : rien à faire"
  exit 0
fi

sum="$(sha256sum "$CFG" | awk '{print $1}')"
if ! printf '%s\n' "${OLD_SUMS[@]}" | grep -qxF "$sum"; then
  echo "  conf mise modifiée localement : rien écrasé"
  echo "  pour prendre la version livrée : devbox seed --force ~/.config/mise/config.toml"
  exit 0
fi

dev-box-seed --force "$CFG"
echo "  conf mise remplacée par la version livrée (claude et codex déclarés)"
echo "  installation : devbox update tools"
