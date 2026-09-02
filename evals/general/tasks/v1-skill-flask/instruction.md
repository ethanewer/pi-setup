You need to build a small **Flask** web application.

Write `/app/app.py` that creates a Flask app. It must define exactly two routes:

1. `GET /`  → returns JSON `{"status": "ok"}`
2. `GET /api/greet?name=<X>` → returns JSON `{"message": "Hello, <X>!"}` where `<X>` is the value of the `name` query parameter (default to `"world"` if absent).

The module-level variable must be named `app` (i.e., `app = Flask(__name__)`), so that `from app import app` works and `app.test_client()` can be used to make test requests.

The test harness will import your module and call `client.get("/")` and `client.get("/api/greet?name=Ada")` to verify the responses. Flask is already installed. Do **not** run `app.run()` at import time (guard it with `if __name__ == "__main__":`).