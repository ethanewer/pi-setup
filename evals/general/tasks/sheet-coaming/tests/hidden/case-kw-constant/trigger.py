from django.db.models.expressions import RawSQL
from django.contrib.auth.models import User

User.objects.annotate(val=RawSQL(sql="SELECT 1", params=[]))
User.objects.annotate(val=RawSQL(params=[], sql="SELECT 2"))