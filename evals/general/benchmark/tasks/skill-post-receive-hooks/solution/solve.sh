#!/bin/bash
set -euo pipefail

rm -rf /app/repo.git /app/hook.log
git init --bare -q /app/repo.git

cat > /app/repo.git/hooks/post-receive <<'HOOK'
#!/bin/bash
while read -r old_value new_value refname; do
  echo "push_received $refname" >> /app/hook.log
done
HOOK
chmod +x /app/repo.git/hooks/post-receive