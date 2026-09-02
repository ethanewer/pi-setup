use std::env;
use std::process;

use beaconpack::compress;
use beaconpack::roundtrip_ok;

fn main() {
    let arg = env::args().nth(1);
    let path = match arg {
        Some(p) if !p.starts_with('-') => p,
        _ => {
            eprintln!("usage: probe <file>");
            process::exit(2);
        }
    };
    let data = match std::fs::read(&path) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("cannot read {}: {}", path, e);
            process::exit(2);
        }
    };
    let (clen, ok) = {
        let c = compress(&data);
        let k = roundtrip_ok(&data);
        (c.len(), k)
    };
    println!(
        "{{\"original_len\":{},\"compressed_len\":{},\"roundtrip_ok\":{}}}",
        data.len(),
        clen,
        if ok { "true" } else { "false" }
    );
}