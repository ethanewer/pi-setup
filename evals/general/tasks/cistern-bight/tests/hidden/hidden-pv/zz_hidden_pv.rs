// Authored hidden case (cistern-bight): a NAMED OPTION whose possible-values
// list is hidden (hide_possible_values(true)) while its possible values carry
// help texts must NOT influence the help layout. The command also has a
// visible option, so we additionally prove that the visible part renders
// normally in the short (compact) layout, on BOTH help flags. Exercises the
// same code path as the upstream regression test (hidden_possible_vals) but
// with a short+long named option, a value name, both possible values helped,
// a mixed visible+hidden command, and both -h and --help.
use super::utils;

use clap::{builder::PossibleValue, Arg, ArgAction, Command};

static COMPACT_HELP: &str = "\
Usage: ptest [OPTIONS]

Options:
      --visible        a visible option
  -s, --speed <SPEED>  choose a speed
  -h, --help           Print help
";

fn cmd() -> Command {
    Command::new("ptest")
        .arg(Arg::new("vis").long("visible").action(ArgAction::SetTrue).help("a visible option"))
        .arg(
            Arg::new("speed")
                .short('s')
                .long("speed")
                .value_name("SPEED")
                .hide_possible_values(true)
                .value_parser([
                    PossibleValue::new("fast").help("the fast one"),
                    PossibleValue::new("slow").help("not as fast"),
                ])
                .help("choose a speed")
                .action(ArgAction::Set),
        )
}

#[test]
fn hidden_pv_named_opt_short_flag() {
    utils::assert_output(cmd(), "ptest -h", COMPACT_HELP, false);
}

#[test]
fn hidden_pv_named_opt_long_flag() {
    utils::assert_output(cmd(), "ptest --help", COMPACT_HELP, false);
}