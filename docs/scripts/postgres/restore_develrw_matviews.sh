#!/usr/bin/env bash
# Refresca segons el TSV de càrrega; --check-only valida sense refrescar ni ANALYZE.
set -Eeuo pipefail
if (( $# < 3 || $# > 4 )) || { (( $# == 4 )) && [[ "$4" != '--check-only' ]]; }; then
    printf 'Usage: %s DOCKER_CONTAINER DEST_DB REPORT_FILE [--check-only]\n' "$0" >&2
    exit 2
fi
container=$1
database=$2
report=$3
refresh=true
[[ ${4:-} != '--check-only' ]] || refresh=false
[[ -f "$report" ]] || { printf 'Report not found: %s\n' "$report" >&2; exit 1; }
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
umask 077
sql_file=$(mktemp)
trap 'rm -f -- "$sql_file"' EXIT
cat >"$sql_file" <<'SQL'
SET ROLE energetica;
CREATE TEMP TABLE source_tables (name text PRIMARY KEY, expected_rows bigint NOT NULL);
CREATE TEMP TABLE source_matviews (name text PRIMARY KEY, populated boolean NOT NULL);
SQL
# Valida tot el TSV abans d'obrir la connexió. Els identificadors admesos són
# els mateixos que admet restore_develrw_data.sh; no s'interpola SQL arbitrari.
awk -F '\t' '
    function fail() { print "Invalid restore report at line " NR > "/dev/stderr"; exit 1 }
    NR == 1 {
        if ($0 != "object_type\tobject_name\trows_or_sequence_state\tstatus") fail()
        next
    }
    {
        if (NF != 4 || $2 !~ /^[a-z_][a-z0-9_]*$/) fail()
        if ($1 == "table" && $4 == "complete" && $3 ~ /^[0-9]+$/) {
            printf "INSERT INTO source_tables VALUES (%c%s%c, %s);\n", 39, $2, 39, $3
        } else if ($1 == "materialized_view" &&
                   (($3 == "source_populated=true" && $4 == "refresh_required") ||
                    ($3 == "source_populated=false" && $4 == "source_unpopulated"))) {
            printf "INSERT INTO source_matviews VALUES (%c%s%c, %s);\n", 39, $2, 39,
                ($3 == "source_populated=true" ? "true" : "false")
        } else if (!($1 == "sequence" && $4 == "complete" && $3 ~ /^-?[0-9]+:[tf]$/)) fail()
    }
    END { if (NR == 0) { print "Empty restore report" > "/dev/stderr"; exit 1 } }
' "$report" >>"$sql_file"
cat "$script_dir/refresh_develrw_matviews.sql" >>"$sql_file"
docker exec -i --user postgres "$container" \
    psql -X -v ON_ERROR_STOP=1 -v "refresh=$refresh" -U postgres -d "$database" <"$sql_file"
