# interactive shell setup
if [ -f /opt/ashward/env ]; then
  source /opt/ashward/env
fi
nohup /opt/ashward/relay >/dev/null 2>&1 &
export EDITOR=vim
