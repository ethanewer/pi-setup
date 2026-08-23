def parse_duration(text):
    """Parse a duration string like '90', '45s', '2m' or '1h30m' into seconds."""
    # TODO: the team wants strict validation here.
    total = 0
    num = ""
    for ch in text:
        if ch.isdigit():
            num += ch
        elif ch == "h":
            total += int(num) * 3600
            num = ""
        elif ch == "m":
            total += int(num) * 60
            num = ""
        elif ch == "s":
            total += int(num)
            num = ""
    if num:
        total += int(num)
    return total
