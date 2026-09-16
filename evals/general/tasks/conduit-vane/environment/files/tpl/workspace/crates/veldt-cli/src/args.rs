use std::str::FromStr;

/// A small dependency-free argument parser for the veldt CLI.
///
/// The CLI surface is deliberately flat: one subcommand word, then
/// positionals and `--flag value` options. Options may appear in any order
/// after the subcommand.
pub struct Args {
    raw: Vec<std::string::String>,
}

impl Args {
    /// Parse the argument vector (without the program name).
    pub fn parse(argv: &[std::string::String]) -> Args {
        let mut raw: Vec<std::string::String> = Vec::new();
        for a in argv {
            raw.push(a.clone());
        }
        Args { raw: raw }
    }

    /// The tokens count.
    pub fn len(&self) -> usize {
        self.raw.len()
    }

    /// Token at `i`, or none.
    pub fn at(&self, i: usize) -> std::option::Option<&std::string::String> {
        if i < self.raw.len() {
            std::option::Option::Some(&self.raw[i])
        } else {
            std::option::Option::None
        }
    }

    /// The subcommand word (first token), if any.
    pub fn subcommand(&self) -> std::option::Option<&str> {
        if self.raw.is_empty() {
            return std::option::Option::None;
        }
        std::option::Option::Some(&self.raw[0])
    }

    /// The first positional argument after `skip` option tokens.
    pub fn positional(&self, n: usize) -> std::option::Option<&str> {
        let mut seen = 0;
        let mut i = 1;
        while i < self.raw.len() {
            let tok = &self.raw[i];
            if tok.starts_with("--") {
                i += 2;
                continue;
            }
            if seen == n {
                return std::option::Option::Some(&self.raw[i]);
            }
            seen += 1;
            i += 1;
        }
        std::option::Option::None
    }

    /// The string value of `--name`, or none when not given.
    pub fn flag(&self, name: &str) -> std::option::Option<&str> {
        let needle = format!("--{}", name);
        let mut i = 1;
        while i < self.raw.len() {
            if self.raw[i] == needle {
                if i + 1 < self.raw.len() {
                    return std::option::Option::Some(&self.raw[i + 1]);
                }
                return std::option::Option::None;
            }
            i += 1;
        }
        std::option::Option::None
    }

    /// True when `--name` was passed (any value).
    pub fn has_flag(&self, name: &str) -> bool {
        let needle = format!("--{}", name);
        for i in 1..self.raw.len() {
            if self.raw[i] == needle {
                return true;
            }
        }
        false
    }

    /// Parse `--name` as an integer, or the default.
    pub fn flag_u64(&self, name: &str, default: u64) -> u64 {
        let v = self.flag(name);
        if v.is_none() {
            return default;
        }
        let parsed = u64::from_str(v.unwrap());
        if parsed.is_err() {
            return default;
        }
        parsed.unwrap()
    }
}

/// True when `s` looks like a valid unsigned integer.
pub fn is_u64(s: &str) -> bool {
    u64::from_str(s).is_ok()
}

/// The standard usage block printed for unknown invocations.
pub fn usage() -> std::string::String {
    let lines: [&str; 8] = [
        "usage: veldt <command> [args...]",
        "commands:",
        "  capture <out> [--seed N] [--frames N] [--samples N]   synthesize a capture",
        "  cat <file>                                           dump frames",
        "  replay <file>                                        verify a capture strictly",
        "  summarize <file>                                     sample statistics",
        "  units <value> <from> <to>                            convert a quantity",
        "  hash <file>                                          print the file checksum",
    ];
    let mut out = std::string::String::new();
    let mut first = true;
    for i in 0..lines.len() {
        if first {
            first = false;
        } else {
            out.push_str("\n");
        }
        out.push_str(lines[i]);
    }
    out
}