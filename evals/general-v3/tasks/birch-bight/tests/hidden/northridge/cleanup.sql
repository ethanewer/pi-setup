-- hidden case northridge teardown
SELECT 'DROP DATABASE northridge'
WHERE EXISTS (SELECT FROM pg_database WHERE datname = 'northridge')\gexec
DROP ROLE IF EXISTS nrreader;
