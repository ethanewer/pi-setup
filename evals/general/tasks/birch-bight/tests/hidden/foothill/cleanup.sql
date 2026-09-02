-- hidden case foothill teardown
SELECT 'DROP DATABASE foothill'
WHERE EXISTS (SELECT FROM pg_database WHERE datname = 'foothill')\gexec
DROP ROLE IF EXISTS fhwatch;
