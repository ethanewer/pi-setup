"""priya's phone microservice (Tern Systems offsite stack)."""
from offsite_common import make_person_app

app = make_person_app("priya")

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8704, debug=False, use_reloader=False)
