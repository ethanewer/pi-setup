#!/usr/bin/env python3
"""Meridian Coast Research Station - rendezvous cluster controller.

Subcommands (each is a self-contained, re-runnable unit of work):
  train-gloo   --world N        multi-process distributed aggregation under the
                                 gloo collective backend (cpu); N worker ranks are
                                 spawned, each all-reduces its share, each writes a
                                 worker marker to /app/markers; rank 0 prints GLOO_SUM.
  export-netflow --in F --out O  serialize flow records from F (lines
                                 SRCIP,DSTIP,SRCPORT,DSTPORT,PROTO,PKTS,OCTETS) into
                                 binary NetFlow v5 export datagrams written to O.
  fetch-flows  --port P --out O  reverse-engineered Meridian-7 client: handshake,
                                 authenticate, retrieve the rendezvous flow records and
                                 write them (one line per flow) to O.
  make-bucket  --name B --port P create an S3 bucket on the local emulated endpoint
                                 (moto server) using the AWS CLI with test credentials,
                                 confirm it appears in the endpoint's bucket list.
  mail-init    --list L          bring up postfix + bring up an mlmmj mailing-list L so
                                 inbound mail to L@localhost is routed to the list
                                 processor (mlmmj-receive).
  run-all                        run the full visible bundle and lay down all markers.
"""
import argparse
import hashlib
import os
import shutil
import socket
import struct
import subprocess
import sys
import time

MARKER_DIR = "/app/markers"

# ---------------------------------------------------------------- gloo
def gloo_worker(rank, size):
    import torch
    import torch.distributed as dist
    dist.init_process_group("gloo", rank=rank, world_size=size)
    # device/dtype movement: build an int64 local value, move to float32 on cpu
    local = torch.tensor([(rank + 1) * 3], dtype=torch.int64).to(device="cpu",
                                                                 dtype=torch.float32)
    dist.all_reduce(local, op=dist.ReduceOp.SUM)
    os.makedirs(MARKER_DIR, exist_ok=True)
    with open(os.path.join(MARKER_DIR, "gloo_rank%d.marker" % rank), "w") as fh:
        fh.write("rank %d reduced %.1f\n" % (rank, local.item()))
    if rank == 0:
        print("GLOO_SUM=%.1f" % local.item(), flush=True)
    dist.destroy_process_group()


def gloo_spawn(world):
    import torch.multiprocessing as mp
    os.environ["MASTER_ADDR"] = "127.0.0.1"
    os.environ["MASTER_PORT"] = "29501"
    mp.spawn(gloo_worker, args=(world,), nprocs=world, join=True)
    return 0

# ---------------------------------------------------------------- netflow v5
HEADER_FMT = ">HHIIIIBBH"      # version,count,sysUptime,unix_secs,unix_nsecs,seq,et,ei,samp
RECORD_FMT = ">IIIHHIIIIHHBBBBHHBBH"
SYS_UPTIME = 3000000
UNIX_SECS = 1700000000
UNIX_NSECS = 0
MAX_PER_DATAGRAM = 30


def parse_flows(path):
    out = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            if len(parts) != 7:
                continue
            out.append(tuple(parts))
    return out


def ip_to_u32(ip):
    return struct.unpack(">I", socket.inet_aton(ip))[0]


def build_datagrams(flows, start_seq=1):
    dgs = []
    seq = start_seq
    for chunk_start in range(0, len(flows), MAX_PER_DATAGRAM):
        chunk = flows[chunk_start:chunk_start + MAX_PER_DATAGRAM]
        nrec = len(chunk)
        record_bytes = b""
        for i, fl in enumerate(chunk):
            srcip, dstip, sport, dport, proto, pkts, octets = fl
            first = SYS_UPTIME - (nrec - i) * 500
            last = SYS_UPTIME - (nrec - 1 - i) * 200
            flags = 0x10
            rec = (ip_to_u32(srcip), ip_to_u32(dstip), 0, 0, 0,
                   int(pkts), int(octets), first, last,
                   int(sport), int(dport), 0, flags, int(proto), 0,
                   0, 0, 0, 0, 0)
            record_bytes += struct.pack(RECORD_FMT, *rec)
        header = struct.pack(HEADER_FMT, 5, nrec, SYS_UPTIME, UNIX_SECS,
                             UNIX_NSECS, seq, 0, 0, 0)
        dgs.append(header + record_bytes)
        seq += 1
    return dgs


def netflow_sub(inpath, outpath):
    flows = parse_flows(inpath)
    dgs = build_datagrams(flows, start_seq=1)
    with open(outpath, "wb") as fh:
        for dg in dgs:
            fh.write(dg)
    print("NETFLOW datagrams=%d flows=%d" % (len(dgs), len(flows)))


# ---------------------------------------------------------------- meridian-7 client
MERIDIAN_SECRET = b"MERIDIANKEY-7f3c"
MERIDIAN_MAGIC = 0x1357BEEF


def recv_frame(sock):
    hdr = b""
    while len(hdr) < 3:
        chunk = sock.recv(3 - len(hdr))
        if not chunk:
            raise RuntimeError("connection closed in header")
        hdr += chunk
    op, ln = struct.unpack(">BH", hdr)
    payload = b""
    while len(payload) < ln:
        chunk = sock.recv(ln - len(payload))
        if not chunk:
            raise RuntimeError("connection closed in payload")
        payload += chunk
    return op, payload


def send_frame(sock, op, payload=b""):
    sock.sendall(struct.pack(">BH", op, len(payload)) + payload)


def fetch_flows(host, port):
    s = socket.create_connection((host, port), timeout=8)
    send_frame(s, 0x11, struct.pack(">I", MERIDIAN_MAGIC))
    op, nonce = recv_frame(s)
    if op != 0x21 or len(nonce) != 8:
        raise RuntimeError("handshake failed op=%d" % op)
    mac = hashlib.sha256(MERIDIAN_SECRET + nonce).hexdigest()[:32].encode()
    send_frame(s, 0x12, mac)
    op, cntb = recv_frame(s)
    if op != 0x22 or len(cntb) != 4:
        raise RuntimeError("auth failed op=%d" % op)
    nflows = struct.unpack(">I", cntb)[0]
    send_frame(s, 0x13, b"")
    op, data = recv_frame(s)
    if op != 0x24:
        raise RuntimeError("flows failed op=%d" % op)
    flows = []
    off = 0
    while off + 2 <= len(data):
        ln = struct.unpack(">H", data[off:off + 2])[0]
        off += 2
        flows.append(data[off:off + ln].decode())
        off += ln
    s.close()
    return flows


def fetch_sub(port, outpath, host="127.0.0.1"):
    flows = fetch_flows(host, port)
    with open(outpath, "w") as fh:
        fh.write("\n".join(flows) + "\n")
    print("FETCHED %d" % len(flows))


# ---------------------------------------------------------------- S3 bucket (local endpoint)
def wait_port(port, tries=40):
    for _ in range(tries):
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.4):
                return True
        except OSError:
            time.sleep(0.25)
    return False


def bucket_sub(name, port):
    server = subprocess.Popen(["moto_server", "-p", str(port)],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        env = dict(os.environ)
        env["AWS_ACCESS_KEY_ID"] = "rendezvous"
        env["AWS_SECRET_ACCESS_KEY"] = "rendezvous"
        env["AWS_DEFAULT_REGION"] = "us-east-1"
        if not wait_port(port):
            raise RuntimeError("moto did not come up")
        subprocess.run(["aws", "--endpoint-url", "http://127.0.0.1:%d" % port,
                        "s3api", "create-bucket", "--bucket", name],
                       check=True, capture_output=True, env=env)
        lst = subprocess.run(["aws", "--endpoint-url", "http://127.0.0.1:%d" % port,
                              "s3", "ls"], capture_output=True, text=True, env=env)
        listing = lst.stdout
        if name not in listing:
            raise RuntimeError("bucket %s not listed" % name)
        os.makedirs(MARKER_DIR, exist_ok=True)
        with open(os.path.join(MARKER_DIR, "s3_%s.ok" % name), "w") as fh:
            fh.write("created\n")
        print("BUCKET %s CREATED" % name)
        print(listing.rstrip())
    finally:
        server.terminate()
        try:
            server.wait(timeout=3)
        except subprocess.TimeoutExpired:
            server.kill()


# ---------------------------------------------------------------- mailing-list stack
def mail_init(listname):
    subprocess.run(["postfix", "start"], capture_output=True)
    time.sleep(1)
    subprocess.run(["postfix", "reload"], capture_output=True)
    spool = "/var/spool/mlmmj"
    os.makedirs(spool, exist_ok=True)
    listdir = os.path.join(spool, listname)
    if not os.path.isdir(listdir):
        subprocess.run("echo n | /usr/bin/mlmmj-make-ml -L %s" % listname, shell=True,
                       cwd=spool, capture_output=True)
    subprocess.run(["chown", "-R", "nobody:nogroup", listdir], check=True)

    alias_line = '%s: "|/usr/bin/mlmmj-receive -L %s", nobody' % (listname, listdir)
    aliases = "/etc/aliases"
    with open(aliases) as fh:
        existing = fh.read()
    if "%s:" % listname not in existing:
        with open(aliases, "a") as fh:
            fh.write(alias_line + "\n")
    subprocess.run(["newaliases"], check=True, capture_output=True)
    subprocess.run(["postfix", "reload"], capture_output=True)

    os.makedirs(MARKER_DIR, exist_ok=True)
    with open(os.path.join(MARKER_DIR, "mail_%s.ok" % listname), "w") as fh:
        fh.write("list %s up\n" % listname)
    print("MAIL list %s up" % listname)


# ---------------------------------------------------------------- run-all (visible bundle)
def run_all():
    # compile the MPI program if not already built
    if not os.path.exists("/app/mpi_agg"):
        subprocess.run(["mpicc", "-O2", "/app/mpi_main.c", "-o", "/app/mpi_agg"], check=True)
    # MPI: serial==parallel on the sample
    for n in (1, 4):
        out = "/app/out/ser" if n == 1 else "/app/out/par"
        subprocess.run(["mkdir", "-p", out], check=True)
        subprocess.run(["mpirun", "--allow-run-as-root", "--oversubscribe", "-np", str(n),
                        "/app/mpi_agg", "/app/sample/telemetry/fragments.txt", out], check=True)
    # gloo on the sample world
    gloo_spawn(4)
    # netflow of sample flows
    netflow_sub("/app/sample/telemetry/flows.txt", "/app/out/flows.bin")
    # protocol fetch from a locally-started rendezvous server
    srv = subprocess.Popen(["/app/protocol_server", "9107",
                            "/app/sample/telemetry/flows.txt"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(1)
        fetch_sub(9107, "/app/out/fetched.txt")
    finally:
        srv.terminate()
    # S3 bucket in the visible scenario
    bucket_sub("meridian-exports", 5660)
    # mailing list in the visible scenario
    mail_init("wardroom")


def build_env():
    """Compile helper binaries the cluster needs (protocol server, MPI program)."""
    if not os.path.exists("/app/protocol_server"):
        subprocess.run(["gcc", "/app/protocol/server.c", "-o", "/app/protocol_server",
                        "-lssl", "-lcrypto"], check=True)
    if not os.path.exists("/app/mpi_agg"):
        subprocess.run(["mpicc", "-O2", "/app/mpi_main.c", "-o", "/app/mpi_agg"], check=True)


def main(argv):
    ap = argparse.ArgumentParser(prog="serve.py")
    sub = ap.add_subparsers(dest="cmd")
    p = sub.add_parser("train-gloo")
    p.add_argument("--world", type=int, required=True)
    p = sub.add_parser("export-netflow")
    p.add_argument("--in", dest="inp", required=True)
    p.add_argument("--out", required=True)
    p = sub.add_parser("fetch-flows")
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--out", required=True)
    p = sub.add_parser("make-bucket")
    p.add_argument("--name", required=True)
    p.add_argument("--port", type=int, default=5660)
    p = sub.add_parser("mail-init")
    p.add_argument("--list", dest="lname", required=True)
    p = sub.add_parser("run-all")
    p = sub.add_parser("build-env")
    args = ap.parse_args(argv[1:])
    if args.cmd == "train-gloo":
        return gloo_spawn(args.world)
    if args.cmd == "export-netflow":
        netflow_sub(args.inp, args.out)
        return 0
    if args.cmd == "fetch-flows":
        fetch_sub(args.port, args.out)
        return 0
    if args.cmd == "make-bucket":
        bucket_sub(args.name, args.port)
        return 0
    if args.cmd == "mail-init":
        mail_init(args.lname)
        return 0
    if args.cmd == "run-all":
        build_env()
        run_all()
        return 0
    if args.cmd == "build-env":
        build_env()
        return 0
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
