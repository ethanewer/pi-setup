// Authored hidden case (cistern-bight), guard direction: for arguments whose
// possible-values list is NOT hidden, the possible-values-with-help trigger
// must keep working exactly as before. A fix that merely deleted the
// possible-value/long-help conditions from the should-long decision would
// make the hidden-possible-values tests pass but would also collapse these
// visible arguments back to the short layout, so these assertions lock the
// trigger side in place, for both a positional argument and a named option.
use super::utils;

use clap::{builder::PossibleValue, Arg, ArgAction, Command};

static POS_VALS_LONG_HELP: &str = "\
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
fn visible_pos_vals_help_still_long() {
    let app = Command::new("ptest").arg(
        Arg::new("pos")
            .value_parser([
                PossibleValue::new("fast"),
                PossibleValue::new("slow").help("not as fast"),
            ])
            .action(ArgAction::Set),
    );
    utils::assert_output(app, "ptest --help", POS_VALS_LONG_HELP, false);
}

static OPT_VALS_LONG_HELP: &str = "\
Usage: ptest [OPTIONS]

Options:
      --speed <SPEED>
          Possible values:
          - fast
          - slow: not as fast

  -h, --help
          Print help (see a summary with '-h')
";

#[test]
fn visible_opt_vals_help_still_long() {
    let app = Command::new("ptest").arg(
        Arg::new("speed")
            .long("speed")
            .value_name("SPEED")
            .value_parser([
                PossibleValue::new("fast"),
                PossibleValue::new("slow").help("not as fast"),
            ])
            .action(ArgAction::Set),
    );
    utils::assert_output(app, "ptest --help", OPT_VALS_LONG_HELP, false);
}