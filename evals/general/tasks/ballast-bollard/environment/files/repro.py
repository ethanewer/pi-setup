# Reproduction: a suppression comment on a later line does not work

identifier = "42"
value = 1

query = """
SELECT *
FROM accounts
WHERE id = '%s'
""" % identifier  # nosec

print(query)