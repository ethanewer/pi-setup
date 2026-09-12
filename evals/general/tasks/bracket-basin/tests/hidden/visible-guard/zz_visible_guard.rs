// Authored hidden case (bracket-basin), guard direction: for arguments that
// are NOT hidden, the existing long-help triggers must keep working exactly as
// before. A fix that merely deleted the possible-value / long-help conditions
// from the should-long decision would make the hidden-argument tests pass but
// would also collapse these visible arguments back to the short layout, so
// these two assertions lock the trigger side in place.
use super::utils;

use clap::{builder::PossibleValue, Arg, ArgAction, Command};

static VISIBLE_PV_LONG_HELP: &str = "\
Usage: ptest [pos]

Arguments:
  [pos]
          Possible values:
          - fast
          - slow: not as fast

Options:
  -h, --help
          Print help (see a summary with '-h')
";

#[test]
fn visible_possible_value_help_still_long() {
    let app = Command::new("ptest").arg(
        Arg::new("pos")
            .value_parser([
                PossibleValue::new("fast"),
                PossibleValue::new("slow").help("not as fast"),
            ])
            .action(ArgAction::Set),
    );
    utils::assert_output(app, "ptest --help", VISIBLE_PV_LONG_HELP, false);
}

static VISIBLE_LONG_HELP: &str = "\
Usage: ptest [OPTIONS]

Options:
      --config
          very long help text about the config option

  -h, --help
          Print help (see a summary with '-h')
";

#[test]
fn visible_long_help_still_long() {
    let app = Command::new("ptest").arg(
        Arg::new("cfg")
            .long("config")
            .long_help("very long help text about the config option")
            .action(ArgAction::SetTrue),
    );
    utils::assert_output(app, "ptest --help", VISIBLE_LONG_HELP, false);
}