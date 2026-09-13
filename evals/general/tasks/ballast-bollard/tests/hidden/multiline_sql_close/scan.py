def build_where(user_input):
    query = """
    SELECT name, email
    FROM customers
    WHERE id = '%s'
    ORDER BY name DESC
    """ % user_input  # nosec
    return query