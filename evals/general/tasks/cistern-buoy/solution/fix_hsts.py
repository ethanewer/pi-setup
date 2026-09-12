#!/usr/bin/env python3
"""Apply the upstream fix for the HSTS-cache-destruction bug to lib/hsts.c.

The fix, identical to what upstream adopted for curl (issue about
Strict-Transport-Security max-age cap), has three coupled parts:

1. a two-year cap constant:  CAP_HSTS_MAX_AGE = 2*365*24*3600;
2. Curl_hsts_parse() parses max-age against that cap and clamps an
   overflowing value to the cap (previously the raw huge number was kept
   and stored as the entry's expiry);
3. hsts_out() returns void and skips (rather than errors on) an entry whose
   expiry cannot be formatted, and Curl_hsts_save() no longer aborts the
   whole save when one entry fails to format.

Every replacement asserts that the parent-commit source still matches, so a
changed snapshot fails loudly instead of silently mis-patching.
"""
import pathlib
import sys

path = pathlib.Path('/app/src/lib/hsts.c')
src = path.read_text(encoding='utf-8')
orig = src
edits = 0


def rep(old: str, new: str, what: str) -> None:
    global src, edits
    assert old in src, f'anchor for {what} not found; source differs from snapshot'
    assert src.count(old) == 1, f'anchor for {what} not unique'
    src = src.replace(old, new)
    edits += 1


# --- 1. the two-year cap constant ------------------------------------------
rep(
    '#define UNLIMITED        "unlimited"\n\n',
    '#define UNLIMITED        "unlimited"\n\n'
    '#define CAP_HSTS_MAX_AGE (2*365*24*3600) /* two years cap */\n\n',
    'cap constant')

# --- 2. parse max-age against the cap, clamp overflow -----------------------
rep(
    '      rc = curlx_str_number(&vp, &expires, TIME_T_MAX);\n'
    '      if(rc == STRE_OVERFLOW)\n'
    '        expires = CURL_OFF_T_MAX;\n',
    '      rc = curlx_str_number(&vp, &expires, CAP_HSTS_MAX_AGE);\n'
    '      if(rc == STRE_OVERFLOW)\n'
    '        expires = CAP_HSTS_MAX_AGE;\n',
    'max-age parsing cap')

# --- 3. hsts_out(): void, skip unformattable entry instead of erroring ------
rep(
    'static CURLcode hsts_out(struct stsentry *sts, FILE *fp)\n',
    'static void hsts_out(struct stsentry *sts, FILE *fp)\n',
    'hsts_out signature')

rep(
    '    CURLcode result = curlx_gmtime((time_t)sts->expires, &stamp);\n'
    '    if(result)\n'
    '      return result;\n'
    '    curl_mfprintf(fp, "%s%s \\"%d%02d%02d %02d:%02d:%02d\\"\\n",\n'
    '                  sts->includeSubDomains ? "." : "", sts->host,\n'
    '                  stamp.tm_year + 1900, stamp.tm_mon + 1, stamp.tm_mday,\n'
    '                  stamp.tm_hour, stamp.tm_min, stamp.tm_sec);\n',
    '    CURLcode result = curlx_gmtime((time_t)sts->expires, &stamp);\n'
    '    if(!result)\n'
    '      /* skip the entry if the date function fails */\n'
    '      curl_mfprintf(fp, "%s%s \\"%d%02d%02d %02d:%02d:%02d\\"\\n",\n'
    '                    sts->includeSubDomains ? "." : "", sts->host,\n'
    '                    stamp.tm_year + 1900, stamp.tm_mon + 1, stamp.tm_mday,\n'
    '                    stamp.tm_hour, stamp.tm_min, stamp.tm_sec);\n',
    'hsts_out gmtime failure handling')

rep(
    '                  sts->includeSubDomains ? "." : "", sts->host, UNLIMITED);\n'
    '  return CURLE_OK;\n'
    '}\n',
    '                  sts->includeSubDomains ? "." : "", sts->host, UNLIMITED);\n'
    '}\n',
    'hsts_out tail')

# --- 4. Curl_hsts_save(): do not abort the whole save on one bad entry ------
rep(
    '      result = hsts_out(sts, out);\n'
    '      if(result)\n'
    '        break;\n',
    '      hsts_out(sts, out);\n',
    'Curl_hsts_save loop')

assert src != orig, 'no edits made'
path.write_text(src, encoding='utf-8')
print(f'hsts.c fixed ({edits} replacements)')