// Authored hidden case (bracket-basin): the same should-long decision is also
// influenced by an argument carrying an explicit long help text
// (v.get_long_help()), and there too a fully HIDDEN argument must not be able
// to force the long layout. The upstream regression test only covered the
// possible-values trigger; this exercises the long-help trigger of the same
// decision on a hidden option, for both help flags.
use super::utils;

use clap::{Arg, ArgAction, Command};

static PLAIN_SHORT_HELP: &str = "\
Usage: ptest

Options:
  -h, --help  Print help
";

fn cmd() -> Command {
    Command::new("ptest").arg(
        Arg::new("cfg")
            .long("config")
            .hide(true)
            .long_help("very long help text about the config option")
            .action(ArgAction::SetTrue),
    )
}

#[test]
fn hidden_long_help_long_flag() {
    utils::assert_output(cmd(), "ptest --help", PLAIN_SHORT_HELP, false);
}

#[test]
fn hidden_long_help_short_flag() {
    utils::assert_output(cmd(), "ptest -h", PLAIN_SHORT_HELP, false);
}