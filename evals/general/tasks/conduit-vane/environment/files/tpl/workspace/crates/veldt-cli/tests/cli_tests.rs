use veldt_cli::args::{Args, is_u64};

#[test]
fn parses_subcommand_and_positionals() {
    let argv = owned_args(["capture", "out.bin", "--seed", "42",
                            "--frames", "8"].to_vec());
    let args = Args::parse(argv.as_slice());
    assert!(args.len() == 6);
    assert!(args.subcommand().unwrap() == "capture");
    assert!(args.positional(0).unwrap() == "out.bin");
    assert!(args.positional(1).is_none());
    assert!(args.flag("seed").unwrap() == "42");
    assert!(args.flag("frames").unwrap() == "8");
    assert!(args.flag_u64("frames", 1) == 8);
    assert!(args.flag_u64("missing", 7) == 7);
    assert!(args.has_flag("seed"));
    assert!(!args.has_flag("nope"));
}

#[test]
fn flags_after_positionals_work() {
    let argv = owned_args(["replay", "cap.bin", "--verbose"].to_vec());
    let args = Args::parse(argv.as_slice());
    assert!(args.subcommand().unwrap() == "replay");
    assert!(args.positional(0).unwrap() == "cap.bin");
    assert!(args.has_flag("verbose"));
}

#[test]
fn u64_validation() {
    assert!(is_u64("0"));
    assert!(is_u64("18446744073709551615"));
    assert!(!is_u64(""));
    assert!(!is_u64("-1"));
    assert!(!is_u64("abc"));
    assert!(!is_u64("18446744073709551616"));
}

fn owned_args(words: Vec<&str>) -> Vec<std::string::String> {
    let mut out: Vec<std::string::String> = Vec::new();
    for w in words {
        out.push(std::string::String::from_utf8(
            w.as_bytes().to_vec()).unwrap());
    }
    out
}

#[test]
fn empty_command_line() {
    let argv: Vec<std::string::String> = Vec::new();
    let args = Args::parse(argv.as_slice());
    assert!(args.subcommand().is_none());
    assert!(args.len() == 0);
}