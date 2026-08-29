#!/usr/bin/env python3
"""Orchard platform Spark workload.

Reads every `<date>_events.log` under a data dir, attributes each record to the
date embedded in its own filename, and aggregates a per-date count. Prints a
machine-readable date-summary line. The orchestrator wraps this in spark-submit
for both local[*] and standalone-cluster masters and captures the wall-clock
duration of each run.
"""
import os, sys, time
from pyspark.sql import SparkSession


def main():
    start = time.time()
    evdir = sys.argv[1] if len(sys.argv) > 1 else "/app/events"
    files = sorted(os.listdir(evdir))
    records = []
    for fn in files:
        if not fn.endswith("_events.log"):
            continue
        date = fn[: -len("_events.log")]
        with open(os.path.join(evdir, fn)) as f:
            for line in f:
                line = line.strip()
                if line:
                    records.append([date, line])
    spark = SparkSession.builder.appName("orchard-events").getOrCreate()
    try:
        total = spark.sparkContext.parallelize(records, 4)
        counts = total.map(lambda r: (r[0], 1)) \
                      .reduceByKey(lambda a, b: a + b).collect()
        counts.sort()
        summary = ";".join("%s=%d" % (d, c) for d, c in counts)
        print("DATE_SUMMARY::" + summary)
        print("TOTAL_RECORDS=%d" % len(records))
        print("JOB_ELAPSED_MS=%d" % int(round((time.time() - start) * 1000)))
    finally:
        spark.stop()


if __name__ == "__main__":
    main()