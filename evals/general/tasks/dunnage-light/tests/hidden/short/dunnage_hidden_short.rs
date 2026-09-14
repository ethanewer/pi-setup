use clap::{Arg, ArgSettings, Command};
use std::ffi::OsStr;

#[test]
fn dunnage_hidden_short_condition() {
    let cmd = Command::new("my_cargo")
        .arg(
            Arg::new("s")
                .long("s")
                .short('s')
                .takes_value(true),
        )
        .arg(
            Arg::new("other")
                .long("other")
                .allow_invalid_utf8(true)
                .default_value_ifs_os(&[(
                    "s",
                    Some("bound").map(OsStr::new),
                    Some("short=bound").map(OsStr::new),
                )]),
        );

    let result = cmd.clone().try_get_matches_from([
        OsStr::new("my_cargo"),
        OsStr::new("-s"),
        OsStr::new("bound"),
    ]);
    assert!(result.is_ok());
    match result {
        Ok(arg_matches) => {
            assert_eq!(
                arg_matches.value_of_os("other"),
                Some(OsStr::new("short=bound")),
            );
        }
        Err(e) => {
            println!("{}", e.to_string());
        }
    }

    let result = cmd.clone().try_get_matches_from([
        OsStr::new("my_cargo"),
        OsStr::new("-s"),
        OsStr::new("other"),
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