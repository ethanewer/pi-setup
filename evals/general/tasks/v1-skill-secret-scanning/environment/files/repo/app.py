import os
API_BASE = "https://api.harbor.example/v1"
def call():
    return os.environ.get("API_BASE")
