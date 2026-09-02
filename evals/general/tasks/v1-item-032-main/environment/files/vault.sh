#!/bin/bash
# Interactive numeric vault: solve three arithmetic gates to open it.
# - clears the screen, then prints coloured ANSI prompts
# - reads answers with `read -s` (no echo), which requires a real terminal;
#   when stdin is a plain pipe bash refuses ("may not be used when reading
#   from a file") - a pseudo-terminal is required.
# - after three correct answers prints OPEN, waits, then prints the token in
#   two chunks with a sleep between them.
printf '\033[2J\033[H\033[1;92mVault v3.2 - interactive lock\033[0m\n'
for gate in 1 2 3; do
  case "$gate" in
    1) q="17 + 19"; ans=36 ;;
    2) q="9 * 14";  ans=126 ;;
    3) q="81 / 3";  ans=27 ;;
  esac
  printf '\033[33mgate %s\033[0m: %s = ? ' "$gate" "$q"
  IFS= read -sr line
  while [ -z "$line" ] || [ "$line" != "$ans" ]; do
    printf '\033[31mno.\033[0m %s = ? ' "$q"
    IFS= read -sr line || exit 0
  done
done
printf '\033[1;32mOPEN\033[0m\n'
sleep 1
printf 'GOLDEN-'
sleep 1
printf '2112\n'
exit 0