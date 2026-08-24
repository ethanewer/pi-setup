import smtplib
def send(frm, rcpt, data):
    with smtplib.SMTP("127.0.0.1", 2525, timeout=5) as s:
        s.sendmail(frm, [rcpt], data)

# 1. normal post to announce list
send("admin@example.test","announce@lists.example.test",
     "From: admin@example.test\r\nTo: announce@lists.example.test\r\nSubject: Newsletter 1\r\n\r\nHello world\r\n")
print("sent post")
