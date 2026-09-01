"""ledgelib.rendering - framework template-rendering entry point.

This is the message-copy path that turns a user-written banner string into an
HTML fragment. It hands the raw string DIRECTLY to the Jinja environment's
from_string() call and then renders it. Any `{{ ... }}` server-side-template
expression carried inside a member-supplied string is evaluated by that call.
"""
import jinja2

# A standalone engine (autoescape off) used only for the banner copy channel.
_ENGINE = jinja2.Environment(autoescape=False)


def render_user_copy(ledger_code, user_string):
    """Render a user-supplied template string against a small context.

    SSTI SINK: `user_string` (untrusted) is the TEMPLATE handed to
    Environment.from_string(). It is executed, not escaped, by Jinja2.
    """
    template = _ENGINE.from_string(user_string)
    return template.render(ledger=ledger_code, who="valet")