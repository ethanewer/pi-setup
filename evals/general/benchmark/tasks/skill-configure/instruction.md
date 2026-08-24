`/app/server_app.py` is a small service program. It reads its configuration from `/app/settings.json` and then prints its startup status.

You must **author** the configuration file `/app/settings.json` so that the service starts successfully. Inspect `/app/server_app.py` to learn exactly which JSON keys it requires and the constraints each key must satisfy (types/ranges). Make sure `settings.json` is one line of valid JSON.

After writing the config, run `python3 /app/server_app.py`. The program prints a single line: `STARTED` if the config satisfies all requirements, or an error message otherwise.

The verifier runs `/app/server_app.py` after your config is in place and checks that it prints `STARTED` exactly. Create the config without removing or renaming any of the pre-existing files.