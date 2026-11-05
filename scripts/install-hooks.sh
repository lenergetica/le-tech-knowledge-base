#!/bin/sh
set -eu
repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"
python3 -c 'import sys; assert sys.version_info >= (3, 9), "Cal Python 3.9 o superior"'
existing=$(git config --get core.hooksPath || true)
if [ -n "$existing" ] && [ "$existing" != '.githooks' ]; then
    echo "Ja hi ha core.hooksPath configurat. Integreu el pre-push de la KB amb els hooks existents." >&2
    exit 1
fi
if [ -z "$existing" ]; then
    hooks_dir=$(git rev-parse --git-path hooks)
    for hook in "$hooks_dir"/*; do
        case "$hook" in *.sample) continue ;; esac
        if [ -f "$hook" ] && [ -x "$hook" ]; then
            echo "Ja hi ha hooks actius. Integreu el pre-push de la KB abans de canviar core.hooksPath." >&2
            exit 1
        fi
    done
fi
git config --local core.hooksPath .githooks
echo 'Hook pre-push de la KB activat en aquest checkout.'
