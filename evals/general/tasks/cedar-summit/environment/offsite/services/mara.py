"""mara's phone microservice (Tern Systems offsite stack)."""
from offsite_common import make_person_app

app = make_person_app("mara")

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8702, debug=False, use_reloader=False)
