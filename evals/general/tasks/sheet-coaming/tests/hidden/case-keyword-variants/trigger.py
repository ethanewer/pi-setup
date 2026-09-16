from django.db.models.expressions import RawSQL
from django.contrib.auth.models import User

queries = {"report": "SELECT id FROM auth_user"}
User.objects.annotate(val=RawSQL(sql=queries["report"], params=[]))

def make_sql():
    return "SELECT 1 FROM auth_user WHERE 1=1"

User.objects.annotate(val=RawSQL(sql=make_sql(), params=[]))
User.objects.annotate(val=RawSQL(sql=queries.get("report"), params=[]))