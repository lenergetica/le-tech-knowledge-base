#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_HOST="${SOURCE_HOST:-192.168.24.3}"
SOURCE_PORT="${SOURCE_PORT:-5432}"
SOURCE_USER="${SOURCE_USER:-energetica}"
SOURCE_DB="${SOURCE_DB:-energetica}"
if (($# < 1)); then
    printf 'Usage: %s DOCKER_CONTAINER [DEST_DB] [--resume REPORT_FILE]\n' "$0" >&2
    exit 2
fi
DEST_CONTAINER="$1"
shift
DEST_DB="${DEST_DB:-energetica_develrw}"
if (($# > 0)) && [[ "$1" != "--resume" ]]; then
    DEST_DB="$1"
    shift
fi
RESUME_REPORT=""
if (($# > 0)); then
    [[ "$1" == "--resume" && $# -eq 2 ]] || {
        printf 'Usage: %s DOCKER_CONTAINER [DEST_DB] [--resume REPORT_FILE]\n' "$0" >&2
        exit 2
    }
    RESUME_REPORT="$2"
fi
DEST_USER="${DEST_USER:-postgres}"
DEST_DOCKER_USER="${DEST_DOCKER_USER:-postgres}"
SCHEMA="develrw"
if [[ -n "$RESUME_REPORT" ]]; then
    REPORT_FILE="$RESUME_REPORT"
else
    REPORT_FILE="${REPORT_FILE:-develrw_restore_counts_$(date '+%Y%m%d_%H%M%S').tsv}"
fi
RESUME_MODE=0
[[ -z "$RESUME_REPORT" ]] || RESUME_MODE=1
MUTATION_STARTED=0

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
    log "ERROR: $*"
    exit 1
}

cleanup() {
    local exit_status=$?
    trap - EXIT

    if [[ -n "${KEEPER_PID:-}" ]]; then
        if kill -0 "$KEEPER_PID" 2>/dev/null; then
            printf '\\q\n' >&"$KEEPER_IN" 2>/dev/null || true
        fi
        wait "$KEEPER_PID" 2>/dev/null || true
    fi

    if [[ -n "${PGPASSWORD:-}" ]]; then
        unset PGPASSWORD
    fi

    if (( exit_status != 0 )); then
        if (( MUTATION_STARTED )); then
            if (( RESUME_MODE )); then
                log "Resume stopped. The destination may be partially populated."
                log "Inspect it before attempting another resume."
            else
                log "Migration stopped. The destination may be partially populated."
                log "Do not rerun against this destination; inspect it or recreate it."
            fi
        else
            log "Preflight stopped before any destination changes."
        fi
        if [[ -n "${REPORT_FILE:-}" && -f "$REPORT_FILE" ]]; then
            log "Report file: $REPORT_FILE"
        fi
    fi

    exit "$exit_status"
}
trap cleanup EXIT

for command_name in psql docker awk dd; do
    command -v "$command_name" >/dev/null 2>&1 ||
        die "Required command not found: $command_name"
done

if [[ -z "${PGPASSWORD:-}" ]]; then
    [[ -t 0 ]] || die "Run interactively or set up an approved password file."
    read -r -s -p "Password for $SOURCE_USER@$SOURCE_HOST: " PGPASSWORD
    printf '\n'
    export PGPASSWORD
fi

src() {
    psql -X -w -v ON_ERROR_STOP=1 \
        -h "$SOURCE_HOST" -p "$SOURCE_PORT" \
        -U "$SOURCE_USER" -d "$SOURCE_DB" "$@"
}

dst() {
    docker exec --user "$DEST_DOCKER_USER" "$DEST_CONTAINER" \
        psql -X -w -v ON_ERROR_STOP=1 \
        -U "$DEST_USER" -d "$DEST_DB" "$@"
}

src_snapshot() {
    src -qAt -F $'\t' -c "
        BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
        SET TRANSACTION SNAPSHOT '$SNAPSHOT_ID';
        $1
        COMMIT;
    "
}

quote_check_identifier() {
    [[ "$1" =~ ^[a-z_][a-z0-9_]*$ ]] ||
        die "Unsupported identifier in source schema: $1"
}

log "Checking source and destination connectivity and versions"
SOURCE_PG_MAJOR=$(src -Atc "SELECT current_setting('server_version_num')::integer / 10000")
DEST_PG_MAJOR=$(dst -Atc "SELECT current_setting('server_version_num')::integer / 10000")
SOURCE_TS_VERSION=$(src -Atc "SELECT extversion FROM pg_extension WHERE extname='timescaledb'")
DEST_TS_VERSION=$(dst -Atc "SELECT extversion FROM pg_extension WHERE extname='timescaledb'")

[[ "$SOURCE_PG_MAJOR" == "$DEST_PG_MAJOR" ]] ||
    die "PostgreSQL major versions differ (source $SOURCE_PG_MAJOR, destination $DEST_PG_MAJOR)"
[[ -n "$SOURCE_TS_VERSION" ]] || die "TimescaleDB is not installed on the source"
[[ "$SOURCE_TS_VERSION" == "$DEST_TS_VERSION" ]] ||
    die "TimescaleDB versions differ (source $SOURCE_TS_VERSION, destination $DEST_TS_VERSION)"

log "PostgreSQL major: $SOURCE_PG_MAJOR; TimescaleDB: $SOURCE_TS_VERSION"

declare -A COMPLETED_TABLES=()
declare -A COMPLETED_ROWS=()
if (( RESUME_MODE )); then
    [[ -f "$REPORT_FILE" ]] || die "Resume report not found: $REPORT_FILE"
    while IFS=$'\t' read -r object_type object_name row_state status; do
        if [[ "$object_type" == "table" && "$status" == "complete" ]]; then
            quote_check_identifier "$object_name"
            [[ "$row_state" =~ ^[0-9]+$ ]] ||
                die "Invalid completed row count in resume report for $object_name"
            if [[ -n "${COMPLETED_TABLES[$object_name]:-}" ]]; then
                die "Duplicate completed-table entry in report: $object_name"
            fi
            COMPLETED_TABLES["$object_name"]=1
            COMPLETED_ROWS["$object_name"]="$row_state"
        fi
    done <"$REPORT_FILE"
    ((${#COMPLETED_TABLES[@]} > 0)) ||
        die "Resume report contains no completed tables: $REPORT_FILE"
    log "Resume mode: loaded ${#COMPLETED_TABLES[@]} completed tables from $REPORT_FILE"
else
    [[ ! -e "$REPORT_FILE" ]] || die "Report file already exists: $REPORT_FILE"
    umask 077
    printf 'object_type\tobject_name\trows_or_sequence_state\tstatus\n' >"$REPORT_FILE"
fi

log "Opening a persistent read-only repeatable-read snapshot on the source"
coproc SNAPSHOT_KEEPER {
    psql -X -w -qAt -v ON_ERROR_STOP=1 \
        -h "$SOURCE_HOST" -p "$SOURCE_PORT" \
        -U "$SOURCE_USER" -d "$SOURCE_DB"
}
KEEPER_PID=$SNAPSHOT_KEEPER_PID
KEEPER_IN=${SNAPSHOT_KEEPER[1]}
KEEPER_OUT=${SNAPSHOT_KEEPER[0]}
printf 'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;\nSELECT pg_export_snapshot();\n' >&"$KEEPER_IN"
IFS= read -r SNAPSHOT_ID <&"$KEEPER_OUT" ||
    die "Could not export a source snapshot"
[[ "$SNAPSHOT_ID" =~ ^[0-9A-Fa-f-]+$ ]] ||
    die "Invalid snapshot identifier returned by PostgreSQL"
log "Source snapshot is ready; reading table and hypertable metadata"

TABLE_OUTPUT=$(src_snapshot "
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = '$SCHEMA'
      AND c.relkind IN ('r', 'p')
      AND NOT EXISTS (
          SELECT 1 FROM pg_inherits i WHERE i.inhrelid = c.oid
      )
    ORDER BY c.relname COLLATE \"C\";
")
[[ -n "$TABLE_OUTPUT" ]] || die "No source tables found in schema $SCHEMA"
mapfile -t TABLES <<<"$TABLE_OUTPUT"

if (( RESUME_MODE )); then
    for table in "${!COMPLETED_TABLES[@]}"; do
        [[ " ${TABLES[*]} " == *" $table "* ]] ||
            die "Resume report contains a table not present in the source schema: $table"
    done
fi

MATVIEW_OUTPUT=$(src_snapshot "
    SELECT c.relname, c.relispopulated::text
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = '$SCHEMA' AND c.relkind = 'm'
    ORDER BY c.relname COLLATE \"C\";
")

SOURCE_FK_COUNT=$(src_snapshot "
    SELECT count(*)
    FROM pg_constraint c
    JOIN pg_class r ON r.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = r.relnamespace
    WHERE n.nspname = '$SCHEMA' AND c.contype = 'f';
")
DEST_FK_COUNT=$(dst -Atc "
    SELECT count(*)
    FROM pg_constraint c
    JOIN pg_class r ON r.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = r.relnamespace
    WHERE n.nspname = '$SCHEMA' AND c.contype = 'f';
")
[[ "$SOURCE_FK_COUNT" == "0" && "$DEST_FK_COUNT" == "0" ]] ||
    die "Foreign keys exist in $SCHEMA; review load ordering before using this script"

HYPERTABLE_OUTPUT=$(src_snapshot "
    SELECT h.hypertable_name,
           count(*)::text,
           count(*) FILTER (WHERE d.dimension_type = 'Time')::text,
           coalesce(max(d.column_name) FILTER (WHERE d.dimension_type = 'Time'), ''),
           coalesce(max(extract(epoch FROM d.time_interval))
               FILTER (WHERE d.dimension_type = 'Time')::text, ''),
           coalesce(bool_and(
               extract(year FROM d.time_interval) = 0
               AND extract(month FROM d.time_interval) = 0
           ) FILTER (WHERE d.dimension_type = 'Time')::text, '')
    FROM timescaledb_information.hypertables h
    JOIN timescaledb_information.dimensions d
      USING (hypertable_schema, hypertable_name)
    WHERE h.hypertable_schema = '$SCHEMA'
    GROUP BY h.hypertable_name
    ORDER BY h.hypertable_name;
")

declare -A HT_TIME_COLUMN=()
declare -A HT_INTERVAL_SECONDS=()
declare -A HT_TABLE=()
declare -A BLOCKER_TRIGGER=()
declare -A INSERT_COLUMNS=()

if [[ -n "$HYPERTABLE_OUTPUT" ]]; then
    while IFS=$'\t' read -r table dimension_count time_count time_column interval_seconds fixed_interval; do
        quote_check_identifier "$table"
        quote_check_identifier "$time_column"
        [[ "$dimension_count" == "1" && "$time_count" == "1" ]] ||
            die "Unsupported multidimensional hypertable: $SCHEMA.$table"
        [[ "$fixed_interval" == "true" ]] ||
            die "Unsupported calendar-based chunk interval on $SCHEMA.$table"
        [[ "$interval_seconds" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
            die "Invalid time chunk interval for $SCHEMA.$table"
        awk -v seconds="$interval_seconds" 'BEGIN { exit !(seconds > 0) }' ||
            die "Non-positive time chunk interval for $SCHEMA.$table"
        HT_TABLE["$table"]=1
        HT_TIME_COLUMN["$table"]="$time_column"
        HT_INTERVAL_SECONDS["$table"]="$interval_seconds"
    done <<<"$HYPERTABLE_OUTPUT"
fi

for table in "${TABLES[@]}"; do
    quote_check_identifier "$table"
done

DEST_TABLE_OUTPUT=$(dst -Atc "
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = '$SCHEMA'
      AND c.relkind IN ('r', 'p')
      AND NOT EXISTS (
          SELECT 1 FROM pg_inherits i WHERE i.inhrelid = c.oid
      )
    ORDER BY c.relname COLLATE \"C\";
")
mapfile -t DEST_TABLES <<<"$DEST_TABLE_OUTPUT"
[[ "${TABLES[*]}" == "${DEST_TABLES[*]}" ]] ||
    die "Source and destination table lists differ in schema $SCHEMA"

column_signature_sql() {
    local table="$1"
    printf "
        SELECT coalesce(string_agg(
            format('%%I|%%s|%%s|%%s|%%s|%%s',
                a.attname,
                format_type(a.atttypid, a.atttypmod),
                a.attnotnull,
                a.attidentity,
                a.attgenerated,
                coalesce(coll_ns.nspname || '.' || coll.collname, '')
            ),
            E'\\\\n' ORDER BY a.attnum
        ), '')
        FROM pg_attribute a
        LEFT JOIN pg_collation coll ON coll.oid = a.attcollation
        LEFT JOIN pg_namespace coll_ns ON coll_ns.oid = coll.collnamespace
        WHERE a.attrelid = format('%%I.%%I', '%s', '%s')::regclass
          AND a.attnum > 0
          AND NOT a.attisdropped;
    " "$SCHEMA" "$table"
}

insert_columns_sql() {
    local table="$1"
    printf "
        SELECT coalesce(string_agg(format('%%I', a.attname), ', ' ORDER BY a.attnum), '')
        FROM pg_attribute a
        WHERE a.attrelid = format('%%I.%%I', '%s', '%s')::regclass
          AND a.attnum > 0
          AND NOT a.attisdropped
          AND a.attgenerated = '';
    " "$SCHEMA" "$table"
}

log "Preflight: ${#TABLES[@]} source tables and ${#HT_TABLE[@]} hypertables"
if [[ -n "$MATVIEW_OUTPUT" ]]; then
    SOURCE_MATVIEW_NAMES=$(printf '%s\n' "$MATVIEW_OUTPUT" | awk -F '\t' '{print $1}' | LC_ALL=C sort)
    DEST_MATVIEW_NAMES=$(dst -Atc "
        SELECT c.relname
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = '$SCHEMA' AND c.relkind = 'm'
        ORDER BY c.relname COLLATE \"C\";
    ")
    [[ "$SOURCE_MATVIEW_NAMES" == "$DEST_MATVIEW_NAMES" ]] ||
        die "Source and destination materialized-view lists differ"

    while IFS=$'\t' read -r matview source_populated; do
        quote_check_identifier "$matview"
        log "Preflight: checking materialized view $SCHEMA.$matview"
        [[ "$source_populated" == "true" || "$source_populated" == "false" ]] ||
            die "Invalid materialized-view state for $SCHEMA.$matview"
        destination_populated=$(dst -Atc "
            SELECT coalesce((
                SELECT c.relispopulated::text FROM pg_class c
                JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = '$SCHEMA'
                  AND c.relname = '$matview'
                  AND c.relkind = 'm'
            )::text, 'missing');
        ")
        [[ "$destination_populated" != "missing" ]] ||
            die "Missing destination materialized view $SCHEMA.$matview"
        [[ "$destination_populated" == "false" ]] ||
            die "Destination materialized view $SCHEMA.$matview is already populated"
        if (( ! RESUME_MODE )); then
            if [[ "$source_populated" == "true" ]]; then
                printf 'materialized_view\t%s\tsource_populated=true\trefresh_required\n' \
                    "$matview" >>"$REPORT_FILE"
            else
                printf 'materialized_view\t%s\tsource_populated=false\tsource_unpopulated\n' \
                    "$matview" >>"$REPORT_FILE"
            fi
        fi
    done <<<"$MATVIEW_OUTPUT"
    log "Materialized views are not copied; see $REPORT_FILE for their source states."
fi

SOURCE_COMPRESSED_COUNT=$(src_snapshot "
    SELECT count(*)
    FROM timescaledb_information.hypertables
    WHERE hypertable_schema = '$SCHEMA' AND compression_enabled;
")
if (( SOURCE_COMPRESSED_COUNT > 0 )); then
    log "WARNING: $SOURCE_COMPRESSED_COUNT source hypertables have compression enabled."
    log "Compression settings and policies are not migrated by this script."
fi

preflight_current=0
preflight_total=${#TABLES[@]}
for table in "${TABLES[@]}"; do
    preflight_current=$((preflight_current + 1))
    log "Preflight [$preflight_current/$preflight_total]: checking $SCHEMA.$table"
    relation_kind=$(dst -Atc "
        SELECT coalesce((
            SELECT c.relkind::text
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = '$SCHEMA' AND c.relname = '$table'
        ), '');
    ")
    [[ "$relation_kind" == "r" || "$relation_kind" == "p" ]] ||
        die "Missing local destination table $SCHEMA.$table"

    has_data=$(dst -Atc "SELECT EXISTS (SELECT 1 FROM \"$SCHEMA\".\"$table\" LIMIT 1)")
    if [[ -n "${COMPLETED_TABLES[$table]:-}" ]]; then
        expected_rows="${COMPLETED_ROWS[$table]}"
        if (( expected_rows > 0 )); then
            [[ "$has_data" == "t" ]] ||
                die "Report marks $SCHEMA.$table complete, but the destination is empty"
        else
            [[ "$has_data" == "f" ]] ||
                die "Report marks empty table $SCHEMA.$table complete, but destination has rows"
        fi
    else
        [[ "$has_data" == "f" ]] ||
            die "Uncompleted destination table $SCHEMA.$table is not empty; refusing to risk duplicate rows"
    fi

    is_hypertable=$(dst -Atc "
        SELECT EXISTS (
            SELECT 1 FROM timescaledb_information.hypertables
            WHERE hypertable_schema = '$SCHEMA'
              AND hypertable_name = '$table'
        );
    ")
    if [[ -n "${HT_TABLE[$table]:-}" ]]; then
        if (( RESUME_MODE )); then
            [[ "$is_hypertable" == "t" ]] ||
                die "Destination hypertable $SCHEMA.$table is missing during resume"
        else
            [[ "$is_hypertable" == "f" ]] ||
                die "Destination $SCHEMA.$table is already a hypertable; use a fresh DDL restore"
        fi
    else
        [[ "$is_hypertable" == "f" ]] ||
            die "Unexpected destination hypertable for ordinary table $SCHEMA.$table"
    fi

    if (( ! RESUME_MODE )) && [[ -n "${HT_TABLE[$table]:-}" ]]; then
        blocker_state=$(dst -Atc "
            SELECT CASE
                WHEN NOT EXISTS (
                    SELECT 1 FROM pg_trigger
                    WHERE tgrelid = format('%I.%I', '$SCHEMA', '$table')::regclass
                      AND tgname = 'ts_insert_blocker'
                ) THEN 'absent'
                WHEN EXISTS (
                    SELECT 1
                    FROM pg_trigger t
                    JOIN pg_proc p ON p.oid = t.tgfoid
                    JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE t.tgrelid = format('%I.%I', '$SCHEMA', '$table')::regclass
                      AND t.tgname = 'ts_insert_blocker'
                      AND n.nspname = '_timescaledb_internal'
                      AND p.proname = 'insert_blocker'
                ) THEN 'timescale'
                ELSE 'unexpected'
            END;
        ")
        [[ "$blocker_state" != "unexpected" ]] ||
            die "Unexpected trigger named ts_insert_blocker on $SCHEMA.$table"
        if [[ "$blocker_state" == "timescale" ]]; then
            BLOCKER_TRIGGER["$table"]=1
        fi
    fi

    source_signature=$(src_snapshot "$(column_signature_sql "$table")")
    destination_signature=$(dst -Atc "$(column_signature_sql "$table")")
    [[ "$source_signature" == "$destination_signature" ]] ||
        die "Column definitions differ for $SCHEMA.$table"

    source_columns=$(src_snapshot "$(insert_columns_sql "$table")")
    destination_columns=$(dst -Atc "$(insert_columns_sql "$table")")
    [[ -n "$source_columns" && "$source_columns" == "$destination_columns" ]] ||
        die "Writable columns differ or are missing for $SCHEMA.$table"
    INSERT_COLUMNS["$table"]="$source_columns"
done

for table in "${!HT_TABLE[@]}"; do
    [[ " ${TABLES[*]} " == *" $table "* ]] ||
        die "Source hypertable $SCHEMA.$table is not in the source table list"
done

log "Preflight passed. No destination data or schema has been changed."
if (( RESUME_MODE )); then
    log "This operation resumes from $REPORT_FILE and copies only tables without a complete report entry."
    log "The new source snapshot may differ from the snapshot used by the interrupted run."
else
    log "This operation creates hypertables and copies all tables in $SCHEMA."
fi
if [[ -t 0 ]]; then
    if (( RESUME_MODE )); then
        read -r -p "Type RESUME develrw to continue: " confirmation
    else
        read -r -p "Type RESTORE develrw to continue: " confirmation
    fi
else
    confirmation="${RESTORE_CONFIRMATION:-}"
fi
if (( RESUME_MODE )); then
    [[ "$confirmation" == "RESUME develrw" ]] ||
        die "Confirmation did not match; no data copied"
else
    [[ "$confirmation" == "RESTORE develrw" ]] ||
        die "Confirmation did not match; no data copied"
fi

MUTATION_STARTED=1
if (( RESUME_MODE )); then
    log "Resume mode: existing destination hypertables are retained."
else
    log "Creating destination hypertables"
    for table in "${TABLES[@]}"; do
        if [[ -n "${HT_TABLE[$table]:-}" ]]; then
            time_column="${HT_TIME_COLUMN[$table]}"
            interval_seconds="${HT_INTERVAL_SECONDS[$table]}"
            if [[ -n "${BLOCKER_TRIGGER[$table]:-}" ]]; then
                dst -q -c "DROP TRIGGER ts_insert_blocker ON \"$SCHEMA\".\"$table\""
            fi
            dst -q -c "
                SELECT create_hypertable(
                    format('%I.%I', '$SCHEMA', '$table')::regclass,
                    '$time_column',
                    chunk_time_interval => make_interval(secs => $interval_seconds),
                    if_not_exists => FALSE,
                    migrate_data => FALSE
                );
            "
            log "Created hypertable $SCHEMA.$table (time column $time_column, chunk interval $interval_seconds seconds)"
        fi
    done
fi

log "Copying tables using the exported source snapshot"
current=0
total=$((${#TABLES[@]} - ${#COMPLETED_TABLES[@]}))
if (( total == 0 )); then
    log "No incomplete tables remain; continuing with sequence synchronization."
fi
for table in "${TABLES[@]}"; do
    if [[ -n "${COMPLETED_TABLES[$table]:-}" ]]; then
        log "Skipping completed table $SCHEMA.$table"
        continue
    fi
    current=$((current + 1))
    columns="${INSERT_COLUMNS[$table]}"
    log "[$current/$total] Copying $SCHEMA.$table; live byte progress follows"

    copy_result=$(
        src -q -v ON_ERROR_STOP=1 -c "
            BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
            SET TRANSACTION SNAPSHOT '$SNAPSHOT_ID';
            COPY (
                SELECT $columns FROM \"$SCHEMA\".\"$table\"
            ) TO STDOUT;
            COMMIT;
        " |
            dd bs=1M status=progress |
            docker exec -i --user "$DEST_DOCKER_USER" "$DEST_CONTAINER" \
                psql -X -A -t -v ON_ERROR_STOP=1 \
                    -U "$DEST_USER" -d "$DEST_DB" \
                    -c "COPY \"$SCHEMA\".\"$table\" ($columns) FROM STDIN"
    )
    [[ "$copy_result" =~ ^COPY[[:space:]]+([0-9]+)$ ]] ||
        die "Could not read COPY row count for $SCHEMA.$table: $copy_result"
    rows_copied="${BASH_REMATCH[1]}"
    printf 'table\t%s\t%s\tcomplete\n' "$table" "$rows_copied" >>"$REPORT_FILE"
    log "[$current/$total] $SCHEMA.$table complete: $rows_copied rows copied"
done

log "Copying source sequence states"
SEQUENCE_NAMES=$(src -Atc "
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = '$SCHEMA' AND c.relkind = 'S'
    ORDER BY c.relname;
")
if [[ -n "$SEQUENCE_NAMES" ]]; then
    while IFS= read -r sequence_name; do
        quote_check_identifier "$sequence_name"
        sequence_state=$(src -At -F $'\t' -c "
            SELECT last_value, is_called
            FROM \"$SCHEMA\".\"$sequence_name\";
        ")
        IFS=$'\t' read -r last_value is_called <<<"$sequence_state"
        [[ "$last_value" =~ ^-?[0-9]+$ && ( "$is_called" == "t" || "$is_called" == "f" ) ]] ||
            die "Invalid source state for sequence $SCHEMA.$sequence_name"

        destination_sequence_kind=$(dst -Atc "
            SELECT coalesce((
                SELECT c.relkind::text
                FROM pg_class c
                JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = '$SCHEMA' AND c.relname = '$sequence_name'
            ), '');
        ")
        [[ "$destination_sequence_kind" == "S" ]] ||
            die "Missing destination sequence $SCHEMA.$sequence_name"

        dst -q -c "
            SELECT setval(
                format('%I.%I', '$SCHEMA', '$sequence_name')::regclass,
                $last_value,
                '$is_called'::boolean
            );
        "
        printf 'sequence\t%s\t%s:%s\tcomplete\n' \
            "$sequence_name" "$last_value" "$is_called" >>"$REPORT_FILE"
        log "Updated sequence $SCHEMA.$sequence_name to $last_value (is_called=$is_called)"
    done <<<"$SEQUENCE_NAMES"
fi

log "Verifying destination hypertable count"
SOURCE_HYPERTABLE_COUNT=${#HT_TABLE[@]}
DEST_HYPERTABLE_COUNT=$(dst -Atc "
    SELECT count(*)
    FROM timescaledb_information.hypertables
    WHERE hypertable_schema = '$SCHEMA';
")
[[ "$SOURCE_HYPERTABLE_COUNT" == "$DEST_HYPERTABLE_COUNT" ]] ||
    die "Hypertable count mismatch (source $SOURCE_HYPERTABLE_COUNT, destination $DEST_HYPERTABLE_COUNT)"

SOURCE_HYPERTABLE_NAMES=""
if (( SOURCE_HYPERTABLE_COUNT > 0 )); then
    SOURCE_HYPERTABLE_NAMES=$(printf '%s\n' "${!HT_TABLE[@]}" | LC_ALL=C sort)
fi
DEST_HYPERTABLE_NAMES=$(dst -Atc "
    SELECT hypertable_name
    FROM timescaledb_information.hypertables
    WHERE hypertable_schema = '$SCHEMA'
    ORDER BY hypertable_name COLLATE \"C\";
")
[[ "$SOURCE_HYPERTABLE_NAMES" == "$DEST_HYPERTABLE_NAMES" ]] ||
    die "Destination hypertable names differ from source"

if (( RESUME_MODE )); then
    log "SUCCESS: resume completed; copied $total remaining tables and synchronized sequence states"
else
    log "SUCCESS: copied ${#TABLES[@]} tables and $DEST_HYPERTABLE_COUNT hypertables"
fi
log "Copy counts and sequence states: $REPORT_FILE"
