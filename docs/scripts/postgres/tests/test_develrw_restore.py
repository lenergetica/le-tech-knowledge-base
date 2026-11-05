#!/usr/bin/env python3
"""Regression checks with fictitious data in a disposable PostgreSQL container.

Requires Docker and a cached PostgreSQL image; never pulls an image and starts
no network or published port. Removes the container on success or failure.
Run from any directory:
    python3 docs/scripts/postgres/tests/test_develrw_restore.py
To use another cached version:
    POSTGRES_TEST_IMAGE=postgres:18-alpine python3 docs/scripts/postgres/tests/test_develrw_restore.py

The default image is postgres:15-alpine. TimescaleDB views are represented by
empty fixtures only for the ownership diagnostic; compression and hypertable
operations need separate verification with the deployed TimescaleDB version.
"""
from pathlib import Path
import subprocess, tempfile, time, os, pty, re, shlex
root=Path(__file__).resolve().parents[4]
scripts=root/'docs/scripts/postgres'
def run(args, **kwargs):
    return subprocess.run(args, text=True, capture_output=True, **kwargs)
def must(result, label):
    if result.returncode: raise RuntimeError(label+'\n'+result.stdout+'\n'+result.stderr)
    print('PASS:',label)
# Check all shell blocks, including the actual argument received by sh -c.
for p in [root/'docs/01/postgres/restaurar-develrw-a-Hall.md',root/'docs/01/postgres/configurar-postgres_fdw.md']:
    text=p.read_text()
    for m in re.finditer(r'^\s*```bash\n(.*?)^\s*```',text,re.M|re.S):
        cmd=m.group(1)
        must(run(['bash','-n'],input=cmd),p.name+' bash block')
        args=shlex.split(cmd)
        if 'sh' in args and '-c' in args:
            i=args.index('-c')
            must(run(['sh','-n','-c',args[i+1]]),p.name+' nested sh -c')
    for link in re.findall(r'\]\(([^)]+)\)',text):
        if '://' not in link and not link.startswith('#'):
            assert (p.parent/link.split('#')[0]).exists(),link
for p in scripts.glob('*.sh'): must(run(['bash','-n',str(p)]),p.name+' syntax')
container='codex-develrw-review-'+str(os.getpid())
must(run(['docker','run','-d','--rm','--name',container,'--network','none','--tmpfs','/var/lib/postgresql','-e','PGDATA=/var/lib/postgresql/test-data','-e','POSTGRES_HOST_AUTH_METHOD=trust','--pull=never',os.environ.get('POSTGRES_TEST_IMAGE','postgres:15-alpine')]), 'start isolated PostgreSQL')
def sql(s, check=True):
    r=run(['docker','exec','-i','--user','postgres',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],input=s)
    if check and r.returncode: raise RuntimeError(r.stdout+'\n'+r.stderr)
    return r
try:
    for _ in range(60):
        logs=run(['docker','logs',container]); ready='PostgreSQL init process complete' in logs.stdout+logs.stderr
        if ready and sql('SELECT 1;',check=False).returncode==0: break
        time.sleep(.2)
    else:
        raise RuntimeError('PostgreSQL test container did not become ready')
    sql('''
CREATE ROLE energetica LOGIN;
CREATE EXTENSION postgres_fdw;
CREATE SERVER energetica_pro FOREIGN DATA WRAPPER postgres_fdw OPTIONS(host '127.0.0.1');
GRANT USAGE ON FOREIGN SERVER energetica_pro TO energetica;
GRANT CREATE ON SCHEMA public TO energetica;
SET ROLE energetica;
CREATE FOREIGN TABLE public.remote_example(id integer) SERVER energetica_pro;
RESET ROLE;
CREATE SCHEMA develrw;
CREATE TABLE develrw.t1(id serial PRIMARY KEY, value integer);
INSERT INTO develrw.t1(value) VALUES (10),(20),(30);
CREATE TABLE develrw.t2(id integer GENERATED ALWAYS AS IDENTITY);
CREATE SEQUENCE develrw.independent_seq;
CREATE TYPE develrw.mood AS ENUM ('ok','bad');
CREATE DOMAIN develrw.positive AS integer CHECK (VALUE>0);
CREATE TYPE develrw.pair AS (a integer,b text);
CREATE TYPE develrw.int_range AS RANGE(subtype=integer);
CREATE FUNCTION develrw.plus(integer) RETURNS integer LANGUAGE SQL AS 'SELECT $1+1';
CREATE PROCEDURE develrw.nothing() LANGUAGE SQL AS 'SELECT 1';
CREATE AGGREGATE develrw.custom_sum(bigint)(sfunc=int8pl,stype=bigint,initcond='0');
CREATE MATERIALIZED VIEW develrw.z_base AS SELECT * FROM develrw.t1 WITH NO DATA;
CREATE VIEW develrw.middle AS SELECT * FROM develrw.z_base;
CREATE MATERIALIZED VIEW develrw.a_dependent AS SELECT sum(value) AS total FROM develrw.middle WITH NO DATA;
CREATE MATERIALIZED VIEW develrw.unpopulated AS SELECT * FROM develrw.t1 WITH NO DATA;
CREATE SCHEMA timescaledb_information;
CREATE VIEW timescaledb_information.chunks AS SELECT NULL::text AS chunk_schema,
 NULL::text AS chunk_name, NULL::text AS hypertable_schema WHERE false;
''')
    for name in ['configure_develrw_fdw_permissions.sql','finalize_develrw_ownership.sql']:
        must(sql((scripts/name).read_text()),name+' execution')
    # All independent routines and types, including range and aggregate, now owned by target.
    r=sql("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='develrw' AND p.proowner<>'energetica'::regrole;")
    assert re.search(r'\n\s*0\n',r.stdout),r.stdout
    print('PASS: routine ownership including aggregate and range support functions')
    r=sql((scripts/'verify_develrw_restore.sql').read_text())
    assert '(0 rows)' in r.stdout
    print('PASS: ownership/permission diagnostic SQL')
    # Exercise hidden input and quote/backslash escaping using a pseudo-terminal.
    secret="test'\\sensitive$only"
    master,slave=pty.openpty()
    proc=subprocess.Popen([str(scripts/'configure_develrw_fdw_mapping.sh'),container,'postgres'],stdin=slave,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    os.close(slave)
    prompt=''
    while not prompt.endswith(': '):
        c=proc.stderr.read(1)
        if not c: raise RuntimeError('Missing password prompt: '+prompt)
        prompt+=c
    os.write(master,(secret+'\n').encode())
    out,err=proc.communicate(timeout=15)
    os.close(master)
    assert proc.returncode==0,(out,err)
    assert secret not in out+err
    # Compare in PostgreSQL without printing the credential.
    literal=secret.replace("'","''")
    r=sql("SET standard_conforming_strings=on; SELECT umoptions @> ARRAY['password="+literal+"'] FROM pg_user_mapping WHERE umuser='energetica'::regrole;")
    assert re.search(r'\n\s*t\n',r.stdout)
    print('PASS: hidden password input, SQL escaping, no secret in stdout/stderr')
    with tempfile.TemporaryDirectory() as tmp:
        report=Path(tmp)/'counts.tsv'
        header='object_type\tobject_name\trows_or_sequence_state\tstatus\n'
        body='table\tt1\t3\tcomplete\ntable\tt2\t0\tcomplete\nmaterialized_view\tz_base\tsource_populated=true\trefresh_required\nmaterialized_view\ta_dependent\tsource_populated=true\trefresh_required\nmaterialized_view\tunpopulated\tsource_populated=false\tsource_unpopulated\n'
        report.write_text(header+body)
        cmd=[str(scripts/'restore_develrw_matviews.sh'),container,'postgres',str(report)]
        must(run(cmd),'refresh from report with dependency through normal view')
        must(run(cmd+['--check-only']),'check-only after refresh')
        assert '60' in sql('TABLE develrw.a_dependent;').stdout
        must(run(cmd),'repeat refresh safely')
        report.write_text(header+body.replace('t1\t3','t1\t4'))
        r=run(cmd); assert r.returncode!=0 and 'Row count mismatch' in r.stderr
        print('PASS: incorrect row count rejected')
        report.write_text(header+body.replace('materialized_view\tz_base\tsource_populated=true\trefresh_required\n',''))
        r=run(cmd); assert r.returncode!=0 and 'inventory differs' in r.stderr
        print('PASS: missing materialized view rejected')
        report.write_text(header+body+'table\tx\x27; SELECT 1; --\t1\tcomplete\n')
        r=run(cmd); assert r.returncode!=0 and 'Invalid restore report' in r.stderr
        print('PASS: malformed report rejected before SQL execution')
        report.write_text(header+body+'table\tt1\t3\tcomplete\n')
        r=run(cmd); assert r.returncode!=0 and 'duplicate key' in r.stderr
        print('PASS: duplicate completed-table record rejected')
        report.write_text(header+body)
        sql('SET ROLE energetica; REFRESH MATERIALIZED VIEW develrw.unpopulated;')
        r=run(cmd); assert r.returncode!=0 and 'source-unpopulated' in r.stderr
        print('PASS: unexpected population of source-unpopulated view rejected')
        sql('SET ROLE energetica; REFRESH MATERIALIZED VIEW develrw.unpopulated WITH NO DATA;')
        sql('CREATE MATERIALIZED VIEW develrw.new_mv AS SELECT 1 AS value WITH NO DATA; ALTER MATERIALIZED VIEW develrw.new_mv OWNER TO energetica;')
        r=run(cmd); assert r.returncode!=0 and 'inventory differs' in r.stderr
        print('PASS: additional destination materialized view rejected')
        sql('DROP MATERIALIZED VIEW develrw.new_mv; DROP MATERIALIZED VIEW develrw.a_dependent; DROP VIEW develrw.middle; DROP MATERIALIZED VIEW develrw.z_base; DROP MATERIALIZED VIEW develrw.unpopulated;')
        report.write_text(header+'table\tt1\t3\tcomplete\ntable\tt2\t0\tcomplete\n')
        must(run(cmd),'report without materialized views')
    print('ALL CHECKS PASSED (no actual TimescaleDB extension)')
finally:
    must(run(['docker','rm','-f',container]),'remove isolated test container')
