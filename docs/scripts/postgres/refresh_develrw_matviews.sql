-- Invocat per restore_develrw_matviews.sh amb l'inventari del TSV carregat.
-- No executar directament: necessita les taules temporals source_* i :refresh.
DO $check$
DECLARE
    item record;
    actual_rows bigint;
BEGIN
    IF NOT EXISTS (SELECT FROM source_tables) THEN
        RAISE EXCEPTION 'No completed tables in report';
    END IF;
    IF EXISTS (
        (SELECT c.relname::text FROM pg_class c
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'develrw' AND c.relkind IN ('r', 'p')
           AND NOT EXISTS (SELECT FROM pg_inherits i WHERE i.inhrelid = c.oid)
         EXCEPT SELECT name FROM source_tables)
        UNION ALL
        (SELECT name FROM source_tables EXCEPT
         SELECT c.relname::text FROM pg_class c
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'develrw' AND c.relkind IN ('r', 'p')
           AND NOT EXISTS (SELECT FROM pg_inherits i WHERE i.inhrelid = c.oid))
    ) THEN
        RAISE EXCEPTION 'Destination table inventory differs from completed report entries';
    END IF;
    IF EXISTS (
        (SELECT c.relname::text FROM pg_class c
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'develrw' AND c.relkind = 'm'
         EXCEPT SELECT name FROM source_matviews)
        UNION ALL
        (SELECT name FROM source_matviews EXCEPT
         SELECT c.relname::text FROM pg_class c
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'develrw' AND c.relkind = 'm')
    ) THEN
        RAISE EXCEPTION 'Destination materialized-view inventory differs from report';
    END IF;
    FOR item IN SELECT * FROM source_tables ORDER BY name LOOP
        EXECUTE format('SELECT count(*) FROM develrw.%I', item.name) INTO actual_rows;
        IF actual_rows <> item.expected_rows THEN
            RAISE EXCEPTION 'Row count mismatch for %: expected %, found %',
                item.name, item.expected_rows, actual_rows;
        END IF;
    END LOOP;
    IF EXISTS (
        SELECT FROM source_matviews s
        JOIN pg_class c ON c.relname = s.name
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'develrw' AND c.relkind = 'm'
          AND NOT s.populated AND c.relispopulated
    ) THEN
        RAISE EXCEPTION 'A source-unpopulated materialized view is populated at destination';
    END IF;
END;
$check$;

\if :refresh
-- Estadístiques locals abans dels joins que calcularan les vistes.
SELECT format('ANALYZE develrw.%I;', name) FROM source_tables ORDER BY name
\gexec

WITH RECURSIVE target_mvs AS (
    SELECT c.oid, n.nspname, c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'develrw'
      AND c.relkind = 'm'
      AND c.relname IN (SELECT name FROM source_matviews WHERE populated)
),
view_refs(root_oid, ref_oid, path) AS (
    SELECT t.oid, d.refobjid, ARRAY[t.oid, d.refobjid]::oid[]
    FROM target_mvs t
    JOIN pg_rewrite rw
      ON rw.ev_class = t.oid AND rw.rulename = '_RETURN'
    JOIN pg_depend d
      ON d.classid = 'pg_rewrite'::regclass
     AND d.objid = rw.oid
     AND d.refclassid = 'pg_class'::regclass
    JOIN pg_class ref ON ref.oid = d.refobjid
    WHERE ref.relkind IN ('v', 'm')
      AND d.refobjid <> t.oid

    UNION ALL

    SELECT vr.root_oid, d.refobjid, vr.path || d.refobjid
    FROM view_refs vr
    JOIN pg_class current_view
      ON current_view.oid = vr.ref_oid AND current_view.relkind = 'v'
    JOIN pg_rewrite rw
      ON rw.ev_class = current_view.oid AND rw.rulename = '_RETURN'
    JOIN pg_depend d
      ON d.classid = 'pg_rewrite'::regclass
     AND d.objid = rw.oid
     AND d.refclassid = 'pg_class'::regclass
    JOIN pg_class ref ON ref.oid = d.refobjid
    WHERE ref.relkind IN ('v', 'm')
      AND NOT d.refobjid = ANY (vr.path)
),
mv_edges AS (
    SELECT DISTINCT vr.root_oid AS dependent_oid, vr.ref_oid AS dependency_oid
    FROM view_refs vr
    JOIN pg_class dependency ON dependency.oid = vr.ref_oid
    JOIN target_mvs target_dependency ON target_dependency.oid = dependency.oid
    WHERE dependency.relkind = 'm'
      AND vr.root_oid <> vr.ref_oid
),
dependency_walk(root_oid, current_oid, depth, path) AS (
    SELECT oid, oid, 0, ARRAY[oid]::oid[]
    FROM target_mvs

    UNION ALL

    SELECT w.root_oid, e.dependency_oid, w.depth + 1, w.path || e.dependency_oid
    FROM dependency_walk w
    JOIN mv_edges e ON e.dependent_oid = w.current_oid
    WHERE NOT e.dependency_oid = ANY (w.path)
),
depths AS (
    SELECT root_oid, max(depth) AS dependency_depth
    FROM dependency_walk
    GROUP BY root_oid
)
SELECT format('REFRESH MATERIALIZED VIEW %I.%I;', t.nspname, t.relname)
FROM target_mvs t
JOIN depths d ON d.root_oid = t.oid
ORDER BY d.dependency_depth, t.relname
\gexec

\endif

DO $check$
BEGIN
    IF EXISTS (
        SELECT FROM source_matviews s
        JOIN pg_class c ON c.relname = s.name
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'develrw' AND c.relkind = 'm'
          AND s.populated <> c.relispopulated
    ) THEN
        RAISE EXCEPTION 'Destination materialized-view population state differs from report';
    END IF;
END;
$check$;

\if :refresh
SELECT format('ANALYZE develrw.%I;', name)
FROM source_matviews WHERE populated ORDER BY name
\gexec
\endif
\echo 'OK: inventories, table row counts and materialized-view population states match the report.'
