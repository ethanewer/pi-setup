# -*- coding: utf-8 -*-
# Legacy Python 2 climate report generator -- DO NOT RUN under Python 3.
# You must port this logic to a modern Python 3 module that preserves the
# high-level aggregation (per-year mean of maxtemp for rows whose year is at
# least the configured start_year) while rewriting every Python-2 idiom into
# Python 3 (pathlib + configparser + pandas with explicit UTF-8 I/O).
import ConfigParser
import csv
import os

config = ConfigParser.ConfigParser()
config.read("/app/cascade_config.ini")

csv_path = config.get("report", "csv_path")
start_year = int(config.get("report", "start_year"))
out_path = config.get("report", "out_path")

rows = []
with open(csv_path, "rb") as f:
    reader = csv.reader(f)
    header = reader.next()
    for line in reader:
        if int(line[0]) >= start_year:
            rows.append(line)

totals = {}
counts = {}
for line in rows:
    yr = int(line[0])
    val = float(line[2])
    totals[yr] = totals.get(yr, 0.0) + val
    counts[yr] = counts.get(yr, 0) + 1

out = open(out_path, "wb")
writer = csv.writer(out)
writer.writerow(["year", "mean_maxtemp"])
for yr in sorted(totals.iterkeys()):
    writer.writerow([yr, totals[yr] / counts[yr]])
out.close()

print "converted %d rows" % len(rows)