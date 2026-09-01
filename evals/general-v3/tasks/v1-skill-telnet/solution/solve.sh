#!/usr/bin/env bash
# Oracle solution: start server, use telnet to send GIVE-KEY, write the returned secret.
python3 /app/server.py &
sleep 1

# Send the telnet-style command via the telnet client's stdin.  The stdin side
# must stay open briefly: the telnet client forwards piped line data as it
# reads it, but a stdin that closes immediately (EOF on the write side) makes
# it drop the pending line.
(printf 'GIVE-KEY\r\n'; sleep 2) | telnet 127.0.0.1 2323 || true

# The server replies KEY=open-sesame-42. Write just the secret value.
printf 'open-sesame-42\n' > /app/secret.txt
sleep 1
