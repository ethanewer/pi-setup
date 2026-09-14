from django.db.models.expressions import RawSQL
from django.contrib.auth.models import User

q = "SELECT username FROM auth_user"
User.objects.annotate(val=RawSQL(params=[0], sql=q))

def build():
    return RawSQL(sql=q, params=[])

User.objects.annotate(val=build())
User.objects.annotate(val=RawSQL(params=[], sql=q))