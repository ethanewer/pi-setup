from django.db.models.expressions import RawSQL
from django.contrib.auth.models import User

User.objects.annotate(val=RawSQL("SELECT 1", []))
current = "SELECT 2"
User.objects.annotate(val=RawSQL(current, []))