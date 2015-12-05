\c regression

SELECT * FROM pglogical.create_subscription(
    subscription_name := 'test_bidirectional',
    provider_dsn := 'dbname=postgres user=super',
    synchronize_structure := false,
    synchronize_data := false,
    forward_origins := '{}');

DO $$
BEGIN
    FOR i IN 1..100 LOOP
        IF EXISTS (SELECT 1 FROM pglogical.local_sync_status WHERE sync_status = 'r') THEN
            EXIT;
        END IF;
        PERFORM pg_sleep(0.1);
    END LOOP;
END;$$;

\c postgres
SELECT pglogical.replicate_ddl_command($$
    CREATE TABLE public.basic_dml (
        id serial primary key,
        other integer,
        data text,
        something interval
    );
$$);

SELECT pg_xlog_wait_remote_apply(pg_current_xlog_location(), 0);

\c regression

-- check basic insert replication
INSERT INTO basic_dml(other, data, something)
VALUES (5, 'foo', '1 minute'::interval),
       (4, 'bar', '12 weeks'::interval),
       (3, 'baz', '2 years 1 hour'::interval),
       (2, 'qux', '8 months 2 days'::interval),
       (1, NULL, NULL);
SELECT pg_xlog_wait_remote_apply(pg_current_xlog_location(), 0);

\c postgres
SELECT id, other, data, something FROM basic_dml ORDER BY id;

UPDATE basic_dml SET other = id, something = something - '10 seconds'::interval WHERE id < 3;
UPDATE basic_dml SET other = id, something = something + '10 seconds'::interval WHERE id > 3;
SELECT pg_xlog_wait_remote_apply(pg_current_xlog_location(), 0);

\c regression
SELECT id, other, data, something FROM basic_dml ORDER BY id;

\c regression
SELECT pglogical.replicate_ddl_command($$
    DROP TABLE public.basic_dml;
$$);

SELECT pglogical.drop_subscription('test_bidirectional');