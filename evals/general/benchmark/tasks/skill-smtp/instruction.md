# SMTP email message construction

Write a Python script `/app/build_mail.py` that constructs an RFC 5322 email message and
writes its **raw message bytes** to `/app/message.eml`.

The message must have these exact header values and body:

- `From`: `sender@example.com`
- `To`: `recipient@example.com`
- `Subject`: `Harbor SMTP Test`
- Message body (the payload text): `Hello from the SMTP test client!`

Use the standard library `email` module (for example
`from email.message import EmailMessage`, set the `From`/`To`/`Subject` fields and
`set_content(...)` for the body). This is the same message object model that `smtplib`
would wrap when sending mail over SMTP. Then write the serialized message to
`/app/message.eml`:

```python
with open("/app/message.eml", "wb") as f:
    f.write(msg.as_bytes())
```

Run the script so `/app/message.eml` exists containing the raw email. Leave
`/app/build_mail.py` and `/app/message.eml` in place when you are done.