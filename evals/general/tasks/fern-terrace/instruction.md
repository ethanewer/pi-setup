# Fern Terrace — software-emulated guest runtime

Palmbrae Labs operates a small fleet of "greenhouse" legacy services. Each service runs on a guest Linux that is emulated in software (no hardware virtualization is available on the host: there is no `/dev/kvm`), reached for maintenance over password SSH, and backed by a raw disk slice archived on the host. Your job is to produce a single, re-usable builder that can stand up any one of these guests, keep it running as a background service, recover a marker from its legacy raw disk image, and confirm host→guest password SSH.

## Environment

You are inside a container (Ubuntu 24.04, root) at `/app`. Installed tools:

- `qemu-system-x86_64` (must run with TCG software emulation, `-accel tcg` / `-machine pc,accel=tcg`). There is **no** `/dev/kvm`.
- `/opt/gk/vmlinuz` — a bootable distro kernel for guests.
- `/opt/gk/busybox` — a **static** busybox for building a minimal guest userland.
- `dropbear`, `dropbearkey`, `openssl` — SSH server bits to embed in the guest.
- `genisoimage` — make the guest CD/ISO bundle.
- `e2fsprogs` (`mke2fs`, `debugfs`, `e2fsck`), `dd` — filesystem/disk tools.
- `sshpass`, `openssh-client` — the host-side SSH client.
- `python3`, `cpio`, `gcc`, etc.

You have no internet access at runtime; all packages are already installed.

## Deliverable: `/app/build_guest.sh`

Write `/app/build_guest.sh` — a bash script with this exact contract:

```
bash /app/build_guest.sh <profile.json> <outdir>
```

Given a guest *profile* (a JSON file) it must, **in this order**, produce everything under `<outdir>`:

1. **Stand up the guest and leave it running as a background service.** Build a minimal guest initramfs from `/opt/gk/busybox` (static) + a `dropbear` server. Boot it with `qemu-system-x86_64` under software emulation into a headless serial console, attaching your ISO as the guest's CD-ROM. Use QEMU user-mode networking with a host forward so the **host** can SSH into the guest: `-netdev user,id=n0,hostfwd=tcp:127.0.0.1:<port>-:22 -device virtio-net-pci,netdev=n0`. The guest must bring up `eth0` (static `10.0.2.15/24`, gateway `10.0.2.2`), run `dropbear` (SSH server) on port 22 for **root**, with password authentication. **Leave the emulator process running** when the script exits — it is a background service.
   - The guest `init` must print exactly these lines to the serial console:
     ```
     FERN-BOOT host=<hostname>
     FERN-SERVICE-TOKEN=<service_token>
     FERN-BOOT-READY
     ```
   - Set the guest `/etc/service-token` to the profile's `service_token` and the guest hostname to the profile's `hostname`.
   - Create a dropbear RSA host key inside the initramfs, and set the root account password (SHA-512 crypt, from the profile `password`) so password login works.
   - The guest must remain contactable via password SSH **after** your script returns (verify it yourself before exiting — a spawned emulator must survive).

2. **CD/ISO bundle**: produce `<outdir>/guest.iso` — a valid ISO-9660 image (via `genisoimage`) that bundles the kernel, initrd and profile (a boot/config CD for the VM). Verify it has the `CD001` ISO magic.

3. **Recover a marker from a legacy raw disk image at its partition offset.** The profile may point at a **raw disk image** (a file containing an MBR and a single Linux partition of type `0x83`). Read the disk's partition table to find the partition's start sector (its *offset*), extract the partition's bytes with `dd`, and pull out the file at the marker path with `debugfs`/`e2fsck`. Write the recovered bytes to:
   - `<outdir>/extracted/marker`
   If the profile supplies no `disk`, generate a fresh raw disk yourself (partition at a non-zero offset of your choosing, marker content = `marker_expected`) and then recover the marker from *that* disk. Either way, copy the disk used into `<outdir>/disk.img`.

   The partition's start sector is **not** fixed — it differs per profile and can be any large number. Your code must parse the actual disk, not assume an offset.

### Output summary
For a profile that produces, say, a 6.5 MB raw disk, an example layout is: a 512-byte MBR with one `0x83` partition beginning at some start sector, and the marker file under `media/data/marker`. Your `<outdir>` must contain at minimum:
- `guest.iso`
- `serial.log`   (boot console capture, must contain `FERN-BOOT-READY` and the token)
- `disk.img`
- `extracted/marker`
- `ssh.ready` (write `1` once you have authenticated from the host into the guest via password SSH)
- `initrd.gz`, `kernel`

### Expected profile schema
```json
{
  "hostname": "string",
  "password": "string",
  "port": 2720,
  "service_token": "string",
  "disk": "/abs/path/raw.img",      // optional; "/app//profile.json" may omit
  "marker_path": "/media/data/marker",
  "marker_expected": "string"
}
```

## Your workflow

1. Write `/app/build_guest.sh` (executable, `chmod +x`).
2. Create `/app/profile.json` with these **exact** values and run it:
   ```json
   {
     "hostname": "fringe-north",
     "password": "zephyr-willow-2291",
     "port": 2720,
     "service_token": "fern-terrace-morning-mist-4811",
     "disk": "",
     "marker_path": "/media/data/marker",
     "marker_expected": "wpb-fernterrace-seed-1024"
   }
   ```
   i.e. run `bash /app/build_guest.sh /app/profile.json /app` (outdir is `/app`), producing `/app/guest.iso` and `/app/serial.log` and the other outputs.
3. Confirm that after `build_guest.sh` exits, `qemu` is still running, and that you can SSH in:
   ```
   sshpass -p 'zephyr-willow-2291' ssh -p 2720 root@127.0.0.1 cat /etc/service-token
   ```
   must print `fern-terrace-morning-mist-4811`.
4. Confirm your marker recovery: `<outdir>/extracted/marker` must equal `wpb-fernterrace-seed-1024`.

## Important

- `/app/build_guest.sh` must be fully generic: at validation time it is re-run against **other** profiles that use **different** hostnames, passwords, tokens, ports, partition offsets, and **provided raw disk images** under `tests/hidden/`. Do not hard-code the visible profile's values anywhere except in `/app/profile.json`.
- The emulator you start must **stay alive** (background service). Do `-display none -serial file:<outdir>/serial.log` (not a foreground TTY that dies with the script).
- The verifier checks: ISO validity, `serial.log` markers, the recovered marker (plus an **independent** re-extraction of `<outdir>/disk.img` at its true partition offset), root password SSH into the running guest returning the right token, and that the emulator is still alive afterwards.
- Do not modify `/tests` (it is mounted read-only for you anyway).
- You may use `/app` freely for your outputs.
