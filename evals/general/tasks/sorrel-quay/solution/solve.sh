#!/bin/bash
# Oracle for sorrel-quay: fill in the two site files with the designated
# single-node cluster configuration. Never reads /tests.
set -eu

CORE="/app/conf/core-site.xml"
HDFS="/app/conf/hdfs-site.xml"

cat > "$CORE" <<'XML'
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
  <property>
    <name>fs.defaultFS</name>
    <value>hdfs://127.0.0.1:9000</value>
  </property>
  <property>
    <name>hadoop.tmp.dir</name>
    <value>/app/data/tmp</value>
  </property>
</configuration>
XML

cat > "$HDFS" <<'XML'
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
  <property>
    <name>dfs.replication</name>
    <value>1</value>
  </property>
  <property>
    <name>dfs.namenode.http-address</name>
    <value>127.0.0.1:9870</value>
  </property>
  <property>
    <name>dfs.datanode.address</name>
    <value>127.0.0.1:9866</value>
  </property>
  <property>
    <name>dfs.namenode.name.dir</name>
    <value>/app/data/namenode</value>
  </property>
  <property>
    <name>dfs.datanode.data.dir</name>
    <value>/app/data/datanode</value>
  </property>
</configuration>
XML

chmod 644 "$CORE" "$HDFS"
echo "solve.sh done -> $CORE $HDFS"
ls -l "$CORE" "$HDFS"
