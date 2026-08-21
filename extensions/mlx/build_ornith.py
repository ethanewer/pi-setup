#!/usr/bin/env python3
"""Install the calibrated Ornith-35B trunk with a q4 Qwen3.6 donor MTP head."""

from __future__ import annotations

import gc
import json
from pathlib import Path
import platform
import shutil
import sys

TRUNK_REPO = "mlx-works/Ornith-1.5-35B-A3B-oQ4e-mtp"
DONOR_REPO = "Qwen/Qwen3.6-35B-A3B"
DEST = Path.home() / ".local/share/mlx-models/Ornith-1.5-35B-A3B-oQ4e-qwen36-mtp"
MARKER = ".optimized-ornith.json"


def fail(message: str) -> None:
    raise RuntimeError(message)


def existing_install_is_valid(path: Path) -> bool:
    config_path = path / "config.json"
    index_path = path / "model.safetensors.index.json"
    if not config_path.is_file() or not index_path.is_file():
        return False
    try:
        config = json.loads(config_path.read_text())
        weight_map = json.loads(index_path.read_text())["weight_map"]
    except Exception:
        return False
    mtp_keys = [key for key in weight_map if "mtp." in key]
    if len(mtp_keys) != 42:
        return False
    if any(not (path / relative).exists() for relative in set(weight_map.values())):
        return False
    overrides = [
        value for key, value in (config.get("quantization") or {}).items()
        if key.startswith("language_model.mtp.") and isinstance(value, dict) and "bits" in value
    ]
    return bool(overrides) and all(
        value.get("bits") == 4 and value.get("group_size") == 64 for value in overrides
    )


def main() -> None:
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        fail("The optimized MLX setup requires Apple-silicon macOS.")

    try:
        import mlx.core as mx
        from huggingface_hub import snapshot_download
        from optiq.runtime.mtp_convert import preserve_mtp
    except Exception as exc:
        fail(
            "mlx-optiq and its Python dependencies are required. Install OptiQ first "
            f"and run this script with its Python interpreter: {exc}"
        )

    if existing_install_is_valid(DEST):
        marker = {
            "format": 1,
            "trunk": TRUNK_REPO,
            "mtp_donor": DONOR_REPO,
            "mtp_bits": 4,
            "mtp_group_size": 64,
        }
        (DEST / MARKER).write_text(json.dumps(marker, indent=2) + "\n")
        print(f"Optimized Ornith-35B is already installed at {DEST}")
        return

    free = shutil.disk_usage(DEST.parent if DEST.parent.exists() else Path.home()).free
    if free < 24 * 1024**3:
        fail(
            f"At least 24 GiB of free disk space is required during installation; "
            f"only {free / 1024**3:.1f} GiB is available."
        )

    print(f"[1/5] Downloading calibrated trunk: {TRUNK_REPO}", flush=True)
    trunk = Path(snapshot_download(TRUNK_REPO))
    config_source = trunk / "config.json"
    index_source = trunk / "model.safetensors.index.json"
    if not config_source.is_file() or not index_source.is_file():
        fail("Downloaded trunk is missing config.json or its safetensors index.")

    staging = DEST.with_name(DEST.name + ".partial")
    shutil.rmtree(staging, ignore_errors=True)
    staging.mkdir(parents=True)
    try:
        for source in trunk.iterdir():
            target = staging / source.name
            if source.name == "config.json":
                shutil.copy2(source, target)
            else:
                target.symlink_to(source.resolve(), target_is_directory=source.is_dir())

        print(f"[2/5] Extracting trained MTP donor: {DONOR_REPO}", flush=True)
        if not preserve_mtp(DONOR_REPO, str(staging), bits=4, group_size=64):
            fail("The donor checkpoint did not expose a compatible MTP head.")
        sidecar = staging / "optiq/mtp.safetensors"
        if not sidecar.is_file():
            fail("MTP extraction completed without producing its sidecar.")

        print("[3/5] Converting donor experts to the native MLX q4 layout", flush=True)
        raw = mx.load(str(sidecar))
        donor: dict[str, object] = {}

        def dense(base: str):
            return mx.dequantize(
                raw[base + ".weight"], raw[base + ".scales"], raw[base + ".biases"],
                group_size=64, bits=4,
            )

        for key, value in raw.items():
            if ".mlp.experts." in key or key.startswith("mtp.layers.0.mlp.gate."):
                continue
            donor["language_model." + key] = value
        donor["language_model.mtp.layers.0.mlp.gate.weight"] = dense(
            "mtp.layers.0.mlp.gate"
        )

        gate_up = raw["mtp.layers.0.mlp.experts.gate_up_proj"]
        down = raw["mtp.layers.0.mlp.experts.down_proj"]
        middle = gate_up.shape[-2] // 2
        expert_arrays = {
            "gate_proj": gate_up[..., :middle, :],
            "up_proj": gate_up[..., middle:, :],
            "down_proj": down,
        }
        for name, array in expert_arrays.items():
            weight, scales, biases = mx.quantize(
                array, group_size=64, bits=4, mode="affine"
            )
            base = f"language_model.mtp.layers.0.mlp.switch_mlp.{name}"
            donor[base + ".weight"] = weight
            donor[base + ".scales"] = scales
            donor[base + ".biases"] = biases
        mx.eval(donor)
        if len(donor) != 42:
            fail(f"Expected 42 converted MTP tensors, found {len(donor)}.")

        print("[4/5] Grafting donor tensors into the calibrated checkpoint", flush=True)
        index = json.loads(index_source.read_text())["weight_map"]
        missing = sorted(set(donor) - set(index))
        if missing:
            fail(f"Donor/trunk tensor contract mismatch: {missing[:5]}")
        shards = sorted({index[key] for key in donor})
        for shard in shards:
            path = staging / shard
            weights = mx.load(str(path))
            for key, value in donor.items():
                if index[key] == shard:
                    weights[key] = value
            temp = staging / (shard + ".new.safetensors")
            mx.save_safetensors(str(temp), weights)
            del weights
            gc.collect()
            mx.clear_cache()
            path.unlink()
            temp.replace(path)

        config = json.loads(config_source.read_text())
        quantization = config.get("quantization") or {}
        for key, value in list(quantization.items()):
            if (
                key.startswith("language_model.mtp.")
                and isinstance(value, dict)
                and "bits" in value
            ):
                quantization[key] = {"bits": 4, "group_size": 64, "mode": "affine"}
        (staging / "config.json").write_text(json.dumps(config, indent=2) + "\n")
        shutil.rmtree(staging / "optiq", ignore_errors=True)
        marker = {
            "format": 1,
            "trunk": TRUNK_REPO,
            "mtp_donor": DONOR_REPO,
            "mtp_bits": 4,
            "mtp_group_size": 64,
        }
        (staging / MARKER).write_text(json.dumps(marker, indent=2) + "\n")

        print("[5/5] Publishing optimized local overlay", flush=True)
        backup = DEST.with_name(DEST.name + ".old")
        shutil.rmtree(backup, ignore_errors=True)
        if DEST.exists():
            DEST.replace(backup)
        staging.replace(DEST)
        shutil.rmtree(backup, ignore_errors=True)
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise

    if not existing_install_is_valid(DEST):
        fail("Post-install validation failed.")
    print(f"Optimized Ornith-35B is ready at {DEST}")
    print("Load it with: /mlx load mlx-works/Ornith-1.5-35B-A3B-oQ4e-mtp")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise
