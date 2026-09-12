// Authored hidden case (cistern-bight), fix-boundary guard: the fix only
// silences the possible-values-with-help trigger for arguments whose value
// list is hidden; a LONG HELP text must keep forcing the long layout on
// --help even when hide_possible_values(true) is set, and the -h short help
// must keep its compact-one-line form with the "see more with '--help'"
// hint. An over-fix that wrapped the whole long/short decision (including
// the long-help branch) in "is the value list hidden" would collapse this
// output, so these two assertions lock the fix's boundary in place.
use super::utils;

use clap::{builder::PossibleValue, Arg, ArgAction, Command};

static LONG_FLAG_HELP: &str = "\
Usage: ptest [OPTIONS]

Options:
      --config <CONFIG>
          very long help text about the config option

  -h, --help
          Print help (see a summary with '-h')
";

static SHORT_FLAG_HELP: &str = "\
Usage: ptest [OPTIONS]

Options:
      --config <CONFIG>  very long help text about the config option
  -h, --help             Print help (see more with '--help')
";

fn cmd() -> Command {
    Command::new("ptest").arg(
        Arg::new("cfg")
            .long("config")
            .value_name("CONFIG")
            .long_help("very long help text about the config option")
            .hide_possible_values(true)
            .value_parser([
                PossibleValue::new("fast"),
                PossibleValue::new("slow").help("not as fast"),
            ])
            .action(ArgAction::Set),
    )
}

#[test]
fn hidden_pv_long_help_long_flag() {
    utils::assert_output(cmd(), "ptest --help", LONG_FLAG_HELP, false);
}

#[test]
fn hidden_pv_long_help_short_flag() {
    utils::assert_output(cmd(), "ptest -h", SHORT_FLAG_HELP, false);
}