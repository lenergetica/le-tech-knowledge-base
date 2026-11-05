#!/usr/bin/env bash
# Crea el mapping sense exposar la contrasenya en arguments, historial o fitxers.
# Cal revisar prèviament el registre SQL del servidor i qualsevol auditoria.
set +x
set -Eeuo pipefail
if (( $# != 2 )); then
    printf 'Usage: %s DOCKER_CONTAINER DEST_DB\n' "$0" >&2
    exit 2
fi
[[ -t 0 ]] || { printf 'Run from an interactive terminal.\n' >&2; exit 1; }
trap 'unset fdw_password escaped_password' EXIT
read -r -s -p 'Contrasenya del rol energetica a PRO: ' fdw_password
printf '\n' >&2
[[ -n "$fdw_password" ]] || { printf 'Empty password refused.\n' >&2; exit 1; }
escaped_password=${fdw_password//\'/\'\'}
{
    printf '%s\n' 'SET standard_conforming_strings = on;'
    printf "CREATE USER MAPPING FOR energetica SERVER energetica_pro OPTIONS (user 'energetica', password '%s');\n" "$escaped_password"
} | docker exec -i --user postgres "$1" \
    psql -X -q -v ON_ERROR_STOP=1 -U postgres -d "$2"
