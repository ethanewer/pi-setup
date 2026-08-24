import smtplib
def send(frm, rcpt, data):
    with smtplib.SMTP("127.0.0.1", 2525, timeout=5) as s:
        s.sendmail(frm, [rcpt], data)
token="5470762af11672d3d9fa09d4416512663e2cdceb"
# carol replies with the token, echoed header X-Confirm-Address
send("carol@example.test","confirm@lists.example.test",
     "From: carol@example.test\r\nTo: confirm@lists.example.test\r\nSubject: CONFIRM "+token+"\r\nX-Confirm-Address: carol@example.test\r\n\r\nconfirm\r\n")
# second post
send("admin@example.test","announce@lists.example.test",
     "From: admin@example.test\r\nTo: announce@lists.example.test\r\nSubject: Newsletter 2\r\n\r\nsecond\r\n")
print("sent confirm + second post")
