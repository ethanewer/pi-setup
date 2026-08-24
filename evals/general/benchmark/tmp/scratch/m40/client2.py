import smtplib, glob, os, re
def send(frm, rcpt, data):
    with smtplib.SMTP("127.0.0.1", 2525, timeout=5) as s:
        s.sendmail(frm, [rcpt], data)

# carol requests subscription
send("carol@example.test","subscribe@lists.example.test",
     "From: carol@example.test\r\nTo: subscribe@lists.example.test\r\nSubject: subscribe me\r\n\r\nsub\r\n")
print("sent subscribe request")
