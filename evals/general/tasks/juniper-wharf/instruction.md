# Juniper Wharf — infrastructure plumbing for the moorings data API

You are the infrastructure engineer for **Juniper Wharf**, a fictional coastal
telemetry operator. Four pieces of plumbing are needed by the data team: the
API contract, transport security, training-data delivery, and object-store
credential management. You must produce **four** artifacts under `/app`. A
verifier later re-runs each of your programs **fresh** — on new endpoints, new
buckets, new certificates and new credential configurations — so nothing may be
hard-coded to the shipped sample values.

Read the read-only fixtures and the full contract before writing anything.

## Environment & live fixtures (already serving; do NOT modify)

A loopback-only **Revetment object store** is reachable right now:

* **S3-style object endpoint:** `http://127.0.0.1:9000`, bucket **`moorings`**.
  The bucket is **public / anonymously readable** — objects are fetched with an
  anonymous HTTP `GET /moorings/<key>` (no signing). A manifest lives at bucket
  root: `GET /moorings/manifest.json`. It is JSON with:
  * `columns` — the exact, ordered parquet column names for every file;
  * `files` — array of `{key, role, rows, sha256}` where `role` is one of
    `train` / `val` / `test` and `sha256` is the hex digest of that object;
  * `dataset`, `version`.
  Parquet split files live under bucket keys like `train/train_part000.parquet`.
* **Control-plane head:** `http://127.0.0.1:9001` (loopback). It exposes
  `GET /v1/mint`, a credential-minting endpoint.
* **TLS certificate** for the object endpoint: `/app/juniper-tls.pem` (PEM).

You may use `requests`, `boto3` (anonymous signed mode), `pandas`, `pyarrow`,
`grpcio`, `grpc_tools`, `protobuf`, and the Python stdlib.

## Deliverable artifacts (all under /app)

### 1. `/app/service.proto` — the API contract
A valid **proto3** file declaring a gRPC **service named `WharfRegistry`** with
**exactly two RPCs** and the message types they use:
* `rpc Claim(DockRequest) returns (Receipt);`
* `rpc Renew(DockRequest) returns (Renewal);`

Define the three messages (`DockRequest`, `Receipt`, `Renewal`) with sensible
fields (at least one field each). **Only the three message class names must
match exactly**; the field names inside the messages are your choice — any
sensible schema will round-trip. Any proto `package` name is fine.
The file must compile with
`python3 -m grpc_tools.protoc -I/app --python_out=<dir> --grpc_python_out=<dir> /app/service.proto`
and the generated `service_pb2*` modules must import and expose
`WharfRegistryStub` and the three message classes.

### 2. `/app/certcheck.py` — TLS certificate metadata checker
A Python program that loads a PEM certificate and reports its metadata.
* CLI: `python3 /app/certcheck.py [CERT_PATH]` — default `/app/juniper-tls.pem`.
* Load the certificate and print, one line each:
  * `CN=<subject CommonName value>` — if the cert has no CommonName, use the
    first `DNSName` in its Subject Alternative Name.
  * `EXPIRES=<notAfter as UTC ISO-8601 datetime, exactly YYYY-MM-DDTHH:MM:SSZ>`
  * `CHECK_STATUS=<OK>` (the explicit success phrase).
* Exit `0`. On a parse error / missing file / expired certificate, print
  `CHECK_STATUS=<FAIL>` and exit non-zero.

### 3. `/app/download.py` — split dataset fetcher
Fetches the split training set from the object store so it is usable locally.
* CLI:
  `python3 /app/download.py --endpoint http://127.0.0.1:9000 --bucket moorings --out /app/wharf_train`
  (all three flags required).
* Reads `manifest.json` from `GET {endpoint}/{bucket}/manifest.json`.
* For **every** `files` entry, download the parquet object
  `GET {endpoint}/{bucket}/{key}` into `<out>/<key>`, verify its SHA-256 equals
  the manifest value (log loudly on mismatch), and check that
  `pandas.read_parquet` columns equal `manifest["columns"]` (same names in the
  same order).
* Concatenate by role into `<out>/train.parquet`, `<out>/val.parquet`,
  `<out>/test.parquet`. Require **at least one `train` and one `test` split**
  in the manifest (split availability).
* Write `<out>/report.json` with **exactly**:
  ```json
  {
    "dataset": "<name>", "downloaded_files": <int>, "sha_ok": true,
    "total_rows": <int>, "train_rows": <int>, "val_rows": <int>,
    "test_rows": <int>, "columns": [...], "splits_complete": true
  }
  ```
* End (exit 0) by printing one summary
  `DOWNLOAD_OK files=<N> rows=<total> sha_ok=true`, or a clear error and a
  non-zero exit on integrity/schema failure.

### 4. `/app/creds_probe.py` — object-store default-credential probe
An **honest** reachability probe of the control head.
* CLI:
  `python3 /app/creds_probe.py --control http://127.0.0.1:9001 [--access-key A] [--secret-key S]`
  Defaults: `--access-key wharfmaster --secret-key wharfmaster` (the documented
  known-default credential pair for the control head).
* Send `GET {control}/v1/mint` with HTTP **Basic** auth using the supplied pair.
* If it returns `200` (the pair is accepted and valid credentials are minted),
  report reachable and print on standard output:
  ```
  CREDS_REACHABLE=1
  CREDS_ACCESS_KEY=<access_key from response>
  CREDS_SECRET_KEY=<secret_key from response>
  CREDS_ROLE=<role from response>
  ```
  and write **`/app/probe_result.json`**:
  `{"reachable": true, "access_key": <...>, "secret_key": <...>, "role": <...>}`
* If it returns `401` (the default was rotated / rejected), do **not** fabricate
  credentials — report honestly:
  ```
  CREDS_REACHABLE=0
  ```
  and write `/app/probe_result.json` with `{"reachable": false,
  "access_key": null, "secret_key": null, "role": null}`.
* Exit `0` in both cases (probing a sealed control plane is still a successful
  probe). Treat an unreachable end host the same as a rejection (report
  `0`); report reachable only on a real `200`.

## Hard constraints
- Work only under `/app`. Never read `/tests` or `/solution`.
- Do **not** modify `/app/realm/` (the object store's served data),
  `/app/juniper-tls.pem`, `/app/object_server.py` or `/app/control_server.py`.
- All four programs are **general purpose**: the verifier re-runs them on new
  certificates, new S3 endpoints/buckets with different datasets, and new
  credential configurations. Nobody may special-case the shipped names, dates,
  addresses, or keys.
- Be honest: integrity failures and sealed control planes are reported, never
  faked.