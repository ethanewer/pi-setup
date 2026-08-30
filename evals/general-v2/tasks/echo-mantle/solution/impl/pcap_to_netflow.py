#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pcap_to_netflow.py

Parse a libpcap capture and aggregate the IPv4 packets it contains into
network-flow records (the classic IP 5-tuple: src IP, src port, dst IP,
dst port, transport protocol).  Each distinct flow is condensed into a single
JSON record carrying packet count, total byte count, and the first/last
observed timestamps.

Usage:
    python3 pcap_to_netflow.py <input.pcap> <output.json>

Exit codes:
    0  success
    1  the input is not a valid/parseable pcap capture
    2  wrong arguments

The flow records are written to <output.json> as a JSON array, sorted by
(first_ts, src, sport, dst, dport, proto).  Non-IPv4 frames (ARP, IPv6,
misc) are ignored; truncated frames with a complete record header are still
counted using the bytes that are present.
"""
import json
import struct
import sys


def flows_from_pcap(data: bytes):
    """Parse raw pcap bytes and return a sorted list of flow records.

    Raises ValueError for inputs that are structurally not a pcap capture.
    """
    if len(data) < 24:
        raise ValueError("input is shorter than a pcap global header")

    magic = data[0:4]
    if magic == b"\xa1\xb2\xc3\xd4":      # big-endian capture
        endian = ">"
    elif magic == b"\xd4\xc3\xb2\xa1":    # little-endian capture
        endian = "<"
    else:
        raise ValueError("not a pcap capture (unrecognized magic bytes)")

    ver_maj, ver_min, _tz, _sig, snaplen, network = struct.unpack_from(
        endian + "HHIIII", data, 4)
    if network != 1:
        raise ValueError(
            "unsupported pcap link type %d (only Ethernet/1 is supported)" % network)

    pos = 24
    total = len(data)
    flows = {}

    while pos + 16 <= total:
        ts_sec, ts_usec, incl_len, _orig_len = struct.unpack_from(
            endian + "IIII", data, pos)
        pos += 16
        if pos + incl_len > total:
            raise ValueError("malformed capture: truncated packet record (%d bytes "
                             "claimed, %d remain)" % (incl_len, total - pos))
        record = data[pos:pos + incl_len]
        pos += incl_len

        timestamp = ts_sec + ts_usec / 1000000.0

        # --- Ethernet frame ---
        if len(record) < 14:
            continue
        ethertype = struct.unpack_from(">H", record, 12)[0]
        if ethertype != 0x0800:
            # Not IPv4 (ARP, IPv6, VLAN-tagged handled only if 0x0800/IPv4).
            continue

        ip = record[14:]
        if len(ip) < 20:
            continue
        ihl = (ip[0] & 0x0F) * 4
        if len(ip) < ihl:
            continue

        proto = ip[9]
        if proto not in (6, 17):          # TCP and UDP only
            continue

        total_len = struct.unpack_from(">H", ip, 2)[0]
        src_ip = ".".join(str(b) for b in ip[12:16])
        dst_ip = ".".join(str(b) for b in ip[16:20])

        if len(ip) < ihl + 4:
            continue
        sport, dport = struct.unpack_from(">HH", ip, ihl)
        name = "TCP" if proto == 6 else "UDP"

        key = (src_ip, sport, dst_ip, dport, name)
        if key not in flows:
            flows[key] = [timestamp, timestamp, 1, total_len]
        else:
            f = flows[key]
            if timestamp < f[0]:
                f[0] = timestamp
            if timestamp > f[1]:
                f[1] = timestamp
            f[2] += 1
            f[3] += total_len

    result = []
    for (src_ip, sport, dst_ip, dport, name), f in flows.items():
        result.append({
            "src_ip": src_ip,
            "sport": sport,
            "dst_ip": dst_ip,
            "dport": dport,
            "proto": name,
            "packets": f[2],
            "bytes": f[3],
            "first_ts": round(f[0], 4),
            "last_ts": round(f[1], 4),
        })

    result.sort(key=lambda r: (r["first_ts"], r["src_ip"], r["sport"],
                               r["dst_ip"], r["dport"], r["proto"]))
    return result


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: pcap_to_netflow.py <input.pcap> <output.json>\n")
        return 2
    try:
        with open(argv[0], "rb") as handle:
            data = handle.read()
        flows = flows_from_pcap(data)
    except (ValueError, OSError) as exc:
        sys.stderr.write("error: %s\n" % exc)
        return 1
    with open(argv[1], "w") as handle:
        json.dump(flows, handle, sort_keys=True)
    sys.stdout.write("wrote %d flow record(s) to %s\n" % (len(flows), argv[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))