use clap::{Arg, ArgSettings, Command};
use std::ffi::OsStr;

#[test]
fn dunnage_hidden_multi_conditions() {
    let cmd = Command::new("my_cargo")
        .arg(
            Arg::new("flag")
                .long("flag")
                .allow_invalid_utf8(true)
                .takes_value(true),
        )
        .arg(
            Arg::new("mode")
                .long("mode")
                .takes_value(true),
        )
        .arg(
            Arg::new("other")
                .long("other")
                .allow_invalid_utf8(true)
                .default_value_ifs_os(&[
                    (
                        "flag",
                        Some("标记2").map(OsStr::new),
                        Some("flag=标记2").map(OsStr::new),
                    ),
                    (
                        "flag",
                        Some("v2").map(OsStr::new),
                        Some("flag=v2").map(OsStr::new),
                    ),
                    (
                        "mode",
                        Some("x").map(OsStr::new),
                        Some("mode=x").map(OsStr::new),
                    ),
                ]),
        );

    let result = cmd.clone().try_get_matches_from([
        OsStr::new("my_cargo"),
        OsStr::new("--flag"),
        OsStr::new("标记2"),
    ]);
    assert!(result.is_ok());
    match result {
        Ok(arg_matches) => {
            assert_eq!(
                arg_matches.value_of_os("flag"),
                Some(OsStr::new("标记2")),
            );
            assert_eq!(
                arg_matches.value_of_os("other"),
                Some(OsStr::new("flag=标记2")),
            );
        }
        Err(e) => {
            println!("{}", e.to_string());
        }
    }

    let result = cmd.clone().try_get_matches_from([
        OsStr::new("my_cargo"),
        OsStr::new("--flag"),
        OsStr::new("v2"),
    ]);
    assert!(result.is_ok());
    match result {
        Ok(arg_matches) => {
            assert_eq!(
                arg_matches.value_of_os("other"),
                Some(OsStr::new("flag=v2")),
            );
        }
        Err(e) => println!("{}", e.to_string()),
    }

    let result = cmd.clone().try_get_matches_from([
        OsStr::new("my_cargo"),
        OsStr::new("--mode"),
        OsStr::new("x"),
    ]);
    assert!(result.is_ok());
    match result {
        Ok(arg_matches) => {
            assert_eq!(
                arg_matches.value_of_os("other"),
                Some(OsStr::new("mode=x")),
            );
        }
        Err(e) => println!("{}", e.to_string()),
    }

    // Two conditions fire at once; the earliest triple in the list wins.
    let result = cmd.clone().try_get_matches_from([
        OsStr::new("my_cargo"),
        OsStr::new("--flag"),
        OsStr::new("标记2"),
        OsStr::new("--mode"),
        OsStr::new("x"),
    ]);
    assert!(result.is_ok());
    match result {
        Ok(arg_matches) => {
            assert_eq!(
                arg_matches.value_of_os("other"),
                Some(OsStr::new("flag=标记2")),
            );
        }
        Err(e) => println!("{}", e.to_string()),
    }

    let result = cmd.clone().try_get_matches_from([
        OsStr::new("my_cargo"),
        OsStr::new("--flag"),
        OsStr::new("zzz"),
    ]);
    assert!(result.is_ok());
    match result {
        Ok(arg_matches) => {
            assert!(
                arg_matches.value_of_os("other").is_none(),
                "{:#?}",
                arg_matches.value_of_os("other"),
            );
        }
        Err(e) => println!("{}", e.to_string()),
    }
}