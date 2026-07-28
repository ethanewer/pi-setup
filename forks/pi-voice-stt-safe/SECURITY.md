# Security Policy

Pi extensions run with the same permissions as your user account. Review code before installing any Pi package.

## Secrets

Pi Voice STT never intentionally writes API keys to session history. Prefer environment variables or macOS Keychain for secrets. Do not commit config files containing `apiKey`.

## Endpoint policy

Non-local transcription endpoints must use HTTPS. Plain HTTP is accepted only for loopback hosts (`localhost`, `127.0.0.1`, `::1`) to support local STT servers.

## Reporting issues

Please report security issues privately if possible. If private reporting is not available, open a minimal public issue without credentials or sensitive logs.
