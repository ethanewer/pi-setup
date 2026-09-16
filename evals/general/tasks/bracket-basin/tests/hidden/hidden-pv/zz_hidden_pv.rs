// Authored hidden case (bracket-basin): a fully hidden positional argument
// whose possible values ALL carry help texts must not influence the help
// layout. The command also has a visible option, so we additionally prove
// that the visible part renders normally in the short (compact) layout.
// Exercises the same code path as the upstream regression test
// (hidden_arg_with_possible_value_with_help) but with both possible values
// helped, a mixed visible+hidden command, and BOTH help flags checked.
use super::utils;

use clap::{builder::PossibleValue, Arg, ArgAction, Command};

static PLAIN_SHORT_HELP: &str = "\
Usage: ptest [OPTIONS]

Options:
      --visible  a visible option
  -h, --help     Print help
";

fn cmd() -> Command {
    Command::new("ptest")
        .arg(Arg::new("vis").long("visible").action(ArgAction::SetTrue).help("a visible option"))
        .arg(
            Arg::new("pos")
                .hide(true)
                .value_parser([
                    PossibleValue::new("fast").help("the fast one"),
                    PossibleValue::new("slow").help("not as fast"),
                ])
                .action(ArgAction::Set),
        )
}

#[test]
fn hidden_possible_values_both_help_short_flag() {
    utils::assert_output(cmd(), "ptest -h", PLAIN_SHORT_HELP, false);
}

#[test]
fn hidden_possible_values_both_help_long_flag() {
    utils::assert_output(cmd(), "ptest --help", PLAIN_SHORT_HELP, false);
}