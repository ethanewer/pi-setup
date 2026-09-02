# Brume Delta single-node ShoreDFS bring-up

You operate the **Brume Delta** hydrology lab's single-node **ShoreDFS** store —
a small Hadoop-style distributed file system emulator. The daemon and client
programs are already shipped; the site configuration files are still empty
placeholders. Your job is to **configure them correctly** so the cluster comes
up on its designated address and RPC port with complementary namenode and
datanode functions.

You must not edit the shipped programs under `/opt/shoredfs`. You only edit
the two configuration files under `/app/conf`, which are the deliverables.

## Deliverables (both required)

| Path | What it is |
|------|------------|
| `/app/conf/core-site.xml` | Cluster-level site config (XML `<configuration>` with `<property>` name/value pairs). |
| `/app/conf/hdfs-site.xml` | Node-level site config (same XML shape). |

Both ship as templates with empty `<value></value>` placeholders. Keep them
**valid XML** and fill in exactly these values:

### `/app/conf/core-site.xml`

| Property | Required value |
|----------|----------------|
| `fs.defaultFS` | `hdfs://127.0.0.1:19310` |

### `/app/conf/hdfs-site.xml`

| Property | Required value |
|----------|----------------|
| `dfs.namenode.rpc-address` | `127.0.0.1:19310` |
| `dfs.datanode.address` | `127.0.0.1:19311` |
| `dfs.replication` | `1` |
| `dfs.permissions.enabled` | `false` |
| `dfs.namenode.name.dir` | `/app/data/namenode` |
| `dfs.datanode.data.dir` | `/app/data/datanode` |

## How the cluster works (why the values matter)

The grader starts the two roles with your config:

```
python3 /opt/shoredfs/dfsnode.py namenode
python3 /opt/shoredfs/dfsnode.py datanode
```

Both roles merge `core-site.xml` and `hdfs-site.xml` into one property map
(the same convention as real Hadoop: each file holds
`<configuration><property><name>…</name><value>…</value></property>…</configuration>`
blocks).

- The **namenode** reads `fs.defaultFS` (`hdfs://HOST:PORT`), validates that
  `dfs.namenode.rpc-address` names the **same** `HOST:PORT` (complementary
  functions — a mismatch makes it exit with an error), creates
  `dfs.namenode.name.dir`, binds `HOST:PORT`, and writes a ready marker to
  `/app/run/namenode.ready`. It answers connections with a
  `SHOREDFS-NN READY <host>:<port>` banner and serves `PUT`/`GET`/`LIST`
  metadata commands.
- The **datanode** reads `dfs.datanode.address`, validates
  `dfs.replication` is a positive integer, creates `dfs.datanode.data.dir`,
  binds that address, **registers itself with the namenode at the
  `fs.defaultFS` address**, and only then writes
  `/app/run/datanode.ready` (whose content records the namenode address it
  registered with). It answers with a `SHOREDFS-DN READY <host>:<port>`
  banner and stores block payloads on disk under `dfs.datanode.data.dir`.

Because the datanode registers at the `fs.defaultFS` address, any typo in
either file (wrong host, wrong port, wrong property name, empty value)
leaves the datanode unregistered and the cluster unable to serve data.

The client tool is used like this:

```
python3 /opt/shoredfs/dfsclient.py --config-dir /app/conf --ops <ops-file>
```

where `<ops-file>` contains lines `PUT <name> <value...>`, `GET <name>`, or
`LIST`. You can smoke-test locally with `/app/examples/smoke_ops.txt`:

```
python3 /opt/shoredfs/dfsclient.py --config-dir /app/conf --ops /app/examples/smoke_ops.txt
```

## How the grader checks you

1. It textually verifies both XML files parse and carry exactly the required
   property values above, and that the namenode RPC address agrees with the
   `fs.defaultFS` host:port.
2. It actually launches both roles with your config and requires the ready
   markers, the recorded registration address, and the `SHOREDFS-NN` /
   `SHOREDFS-DN` banners on the designated ports.
3. It runs several **hidden client-operation sequences** against the live
   cluster (each on a freshly started cluster) and requires the client's
   printed output to match independent ground truth exactly.

Do not modify anything under `/opt/shoredfs` or `/app/examples`, and do not
try to read `/tests` (it is unavailable to you). The grader starts and stops
the daemons itself; you do not need to leave anything running.
