# system-wide shell settings
if [ -f /etc/bashrc.local ]; then
  . /etc/bashrc.local
fi
export EDITOR=vim
