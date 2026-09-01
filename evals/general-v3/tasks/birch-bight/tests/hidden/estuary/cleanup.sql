-- hidden case estuary teardown
SELECT 'DROP DATABASE estuary'
WHERE EXISTS (SELECT FROM pg_database WHERE datname = 'estuary')\gexec
DROP ROLE IF EXISTS estuary;
