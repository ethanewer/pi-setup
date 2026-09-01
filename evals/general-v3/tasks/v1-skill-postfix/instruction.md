# Postfix (mail transfer agent) fundamentals

Answer five short questions about the **Postfix** mail server and its standard configuration. Base your answers on standard Postfix conventions (the classic default configuration).

1. What is the **default TCP port** that Postfix listens on for the SMTP mail transport protocol? (integer)
2. What is the **absolute path** of Postfix's main configuration file, where core parameters such as `myhostname`, `mydomain`, and `mydestination` are defined?
3. Which **main.cf parameter** lists the domains for which this host accepts and delivers local mail (the domains it considers itself authoritative for)? (one word)
4. What command **reloads** the running Postfix processes so that edited configuration takes effect without restarting the service? (two lowercase words, e.g. `postfix reload`)
5. Which Postfix command-line tool **displays the mail queue** — a compact listing of queued messages (used to spot stuck mail)? (one word)

Write the five answers to `/app/answer.json`:

```json
{
  "smtp_port": "25",
  "main_config": "/etc/postfix/main.cf",
  "local_delivery_param": "mydestination",
  "reload_command": "postfix reload",
  "queue_tool": "mailq"
}
```

Replace the values with the correct answers. String answers are compared case-insensitively after trimming surrounding whitespace. (You do not need to install or run Postfix for this task.)