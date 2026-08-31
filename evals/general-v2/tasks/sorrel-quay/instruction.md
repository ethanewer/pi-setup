# Configure the Sorrel Quay single-node cluster

The **Sorrel Quay** observatory runs a single-node cluster (one namenode role,
one datanode role) whose daemons are configured exclusively through two
Hadoop-style site files. The daemons refuse to start while the site files are
missing, unparsable, or contain unset properties, so a miswritten value keeps
the whole cluster from coming up. Your job is to edit the two site files so the
cluster uses the designated node address, the designated RPC port, and the
complementary namenode/datanode settings listed below. The grader will start
the shipped daemons against **your** site files and run probes against the
live cluster, so the values must be exactly right.

## Environment

- Working directory: `/app`.
- The site templates live at `/app/conf/core-site.xml` and
  `/app/conf/hdfs-site.xml`; every `<value>` is currently **empty**.
- The role daemons are at `/app/sbin/name-daemon.py` and are started as
  `python3 /app/sbin/name-daemon.py namenode` / `... datanode`. Do **not**
  modify anything under `/app/sbin` or `/app/bin`.
- A local smoke probe is available for your own testing:
  `python3 /app/bin/smoke_probe.py`.

## Deliverables (both required)

1. `/app/conf/core-site.xml` — set:
   | Property         | Designated value        |
   |------------------|-------------------------|
   | `fs.defaultFS`   | `hdfs://127.0.0.1:9000` |
   | `hadoop.tmp.dir` | `/app/data/tmp`         |

2. `/app/conf/hdfs-site.xml` — set:
   | Property                    | Designated value     |
   |-----------------------------|----------------------|
   | `dfs.replication`           | `1`                  |
   | `dfs.namenode.http-address` | `127.0.0.1:9870`     |
   | `dfs.datanode.address`      | `127.0.0.1:9866`     |
   | `dfs.namenode.name.dir`     | `/app/data/namenode` |
   | `dfs.datanode.data.dir`     | `/app/data/datanode` |

Keep both files **valid XML** in the standard Hadoop site-file shape (a single
`<configuration>` root containing `<property>` elements each with exactly one
`<name>` and one `<value>`; no duplicated properties). The files must stay at
the paths above.

## How the grader checks you

1. **Textual/XML check:** both site files are parsed and every property above
   must carry exactly the designated value string; malformed XML, missing
   properties, or wrong values fail immediately.
2. **Live cluster check:** the grader starts both role daemons against your
   site files, waits for their ready markers, and requires the designated
   endpoints to actually listen: the namenode RPC socket on port `9000` (from
   `fs.defaultFS`), the namenode web UI on `9870`, and the datanode on `9866`.
   A daemonic single-node cluster that cannot bind its designated RPC port is
   a failure.
3. **Hidden probes:** several hidden probe programs are executed against the
   live cluster and their outputs compared to ground truth. The probes query
   the running daemons for the values the daemons themselves read out of your
   site files (ping, replication factor, default filesystem URI, web UI
   address, datanode data directory), so any miswritten config string shows up
   here as well.

## Constraints

- Edit only the two site files under `/app/conf`; do not touch
  `/app/sbin/*`, `/app/bin/*`, or anything else in the image.
- Do not start or stop the daemons yourself; the grader launches fresh ones.
- No network access beyond the local endpoints above.
