package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strconv"
	"strings"
)

// ---------------------------------------------------------------------------
// culvert: settings-resolution CLI for the mast relay service.
//
// Six settings resolved through  flag > env var > config file > default.
// Three subcommands: resolve, diff, check.  Output modes: json, table.
//
// stdlib only: flag (command line), os (env/files/exit), strconv, strings,
// encoding/json (jsfuscation-free value marshaling), fmt (diagnostics).
// ---------------------------------------------------------------------------

const NKEYS = 6

var KEY_NAMES = []string{ "endpoint", "region", "timeout_ms", "retries", "verbose", "max_batch" }
var KEY_FLAGS = []string{ "endpoint", "region", "timeout-ms", "retries", "verbose", "max-batch" }
var ENV_NAMES = []string{ "CULVERT_ENDPOINT", "CULVERT_REGION", "CULVERT_TIMEOUT_MS", "CULVERT_RETRIES", "CULVERT_VERBOSE", "CULVERT_MAX_BATCH" }
var KEY_DEFAULTS = []string{ "https://relay.example/sink", "us-east", "15000", "3", "false", "500" }
var KEY_KINDS = []string{ "str", "str", "int", "int", "bool", "int" }
var KEY_MINS = []int{ 0, 0, 1000, 0, 0, 1 }
var KEY_MAXS = []int{ 0, 0, 600000, 10, 0, 100000 }

const DEFAULT_CONF = "/app/culvert.conf"

// ---- message templates -----------------------------------------------------

const MSG_NOT_INT = "not an integer"
const MSG_RANGE = "out of range"
const MSG_BOOL = "must be true or false"
const MSG_EMPTY = "must not be empty"
const MSG_PREFIX = "must start with http:// or https://"
const MSG_CTRL = "contains control characters"

// ---- diagnostic writer (stderr) --------------------------------------------

func failMsg(s string) {
	fmt.Fprintln(os.Stderr, s)
}

func usageExit(code int) {
	os.Exit(code)
}

// ---- validation ------------------------------------------------------------

func hasControl(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] < byte(0x20) {
			return true
		}
	}
	return false
}

// validateValue returns "" when raw is a valid, canonicalizable value for
// setting i, otherwise the fixed error template.
func validateValue(i int, raw string) string {
	k := KEY_KINDS[i]
	if k == "int" {
		v, err := strconv.Atoi(raw)
		if err != nil {
			return MSG_NOT_INT
		}
		if v < KEY_MINS[i] || v > KEY_MAXS[i] {
			return MSG_RANGE
		}
		return ""
	}
	if k == "bool" {
		t := strings.ToLower(raw)
		if t == "true" || t == "false" {
			return ""
		}
		return MSG_BOOL
	}
	// string kind
	if len(raw) == 0 {
		return MSG_EMPTY
	}
	if hasControl(raw) {
		return MSG_CTRL
	}
	if i == 0 {
		if !strings.HasPrefix(raw, "http://") && !strings.HasPrefix(raw, "https://") {
			return MSG_PREFIX
		}
	}
	return ""
}

// canonicalValue normalizes a valid raw value to its canonical text form.
func canonicalValue(i int, raw string) string {
	k := KEY_KINDS[i]
	if k == "int" {
		v, _ := strconv.Atoi(raw)
		return strconv.Itoa(v)
	}
	if k == "bool" {
		return strings.ToLower(raw)
	}
	return raw
}

// findIndex locates setting index by its canonical config name.
func findIndex(name string) int {
	for i := 0; i < NKEYS; i++ {
		if KEY_NAMES[i] == name {
			return i
		}
	}
	return -1
}

// findFlagIndex locates setting index by its flag spelling.
func findFlagIndex(name string) int {
	for i := 0; i < NKEYS; i++ {
		if KEY_FLAGS[i] == name {
			return i
		}
	}
	return -1
}

// layer rank for check ordering: flag < env < config
func layerRank(layer string) int {
	if layer == "flag" {
		return 0
	}
	if layer == "env" {
		return 1
	}
	return 2
}

// ---- config file -----------------------------------------------------------

// readConfig parses the file at path.  Returns nil if absent/unreadable,
// otherwise a map of canonical key -> raw value.  A nil map with a non-nil
// error means malformed (exit 3).  Returns (map, errline int).
func readConfig(path string) (map[string]string, int) {
	b, rerr := os.ReadFile(path)
	if rerr != nil {
		return nil, 0
	}
	text := string(b)
	lines := strings.Split(text, "\n")
	m := make(map[string]string, 8)
	for i := 0; i < len(lines); i++ {
		line := strings.Trim(lines[i], " \t\r")
		if len(line) == 0 {
			continue
		}
		if strings.HasPrefix(line, "#") {
			continue
		}
		eq := -1
		for j := 0; j < len(line); j++ {
			if line[j] == byte('=') {
				eq = j
				break
			}
		}
		if eq < 0 {
			return nil, i + 1
		}
		key := strings.Trim(line[0:eq], " \t\r")
		val := strings.Trim(line[eq + 1:], " \t\r")
		if len(key) == 0 {
			return nil, i + 1
		}
		idx := findIndex(key)
		if idx >= 0 {
			m[key] = val
		}
	}
	return m, 0
}

// ---- resolution ------------------------------------------------------------

type LayerInfo struct {
	Layer   string // "flag", "env", "config", "default"
	Value   string // canonical value
	Ok      bool   // true when the winning value validated
	Problem string // non-empty when Ok == false
}

// layerValue computes the winning layer canonical value for setting i.
func layerValue(i int, fs *flag.FlagSet, conf map[string]string, setFlags []string) LayerInfo {
	// flag layer
	if containsStr(setFlags, KEY_FLAGS[i]) {
		raw := flagString(fs, KEY_FLAGS[i])
		prob := validateValue(i, raw)
		if prob != "" {
			return LayerInfo{ "flag", raw, false, prob }
		}
		return LayerInfo{ "flag", canonicalValue(i, raw), true, "" }
	}
	// env layer
	ev, present := os.LookupEnv(ENV_NAMES[i])
	if present {
		raw := strings.Trim(ev, " \t\r")
		prob := validateValue(i, raw)
		if prob != "" {
			return LayerInfo{ "env", raw, false, prob }
		}
		return LayerInfo{ "env", canonicalValue(i, raw), true, "" }
	}
	// config layer
	key := KEY_NAMES[i]
	raw, confOk := conf[key]
	if confOk {
		prob := validateValue(i, raw)
		if prob != "" {
			return LayerInfo{ "config", raw, false, prob }
		}
		return LayerInfo{ "config", canonicalValue(i, raw), true, "" }
	}
	return LayerInfo{ "default", KEY_DEFAULTS[i], true, "" }
}

func containsStr(hay []string, needle string) bool {
	for i := 0; i < len(hay); i++ {
		if hay[i] == needle {
			return true
		}
	}
	return false
}

func flagString(fs *flag.FlagSet, name string) string {
	return fs.Lookup(name).Value.String()
}

// ---- config view (for diff) ------------------------------------------------

// configView returns the value the config file alone would contribute:
// the file's canonical value when present, else the default.
func configViewOf(i int, conf map[string]string) (string, bool) {
	key := KEY_NAMES[i]
	_, confOk := conf[key]
	if confOk {
		return canonicalValue(i, conf[key]), true
	}
	return KEY_DEFAULTS[i], false
}

// ---- json helpers ----------------------------------------------------------

// jsValue renders the canonical value of setting i as JSON bytes.
func jsValue(i int, canonical string) string {
	if KEY_KINDS[i] == "str" {
		b, _ := json.Marshal(canonical)
		return string(b)
	}
	return canonical
}

func jsStr(s string) string {
	b, _ := json.Marshal(s)
	return string(b)
}

// ---- output modes ----------------------------------------------------------

func pad(s string, width int) string {
	out := s
	for i := len(s); i < width; i++ {
		out += " "
	}
	return out
}

// ---- resolve output ---------------------------------------------------------

func emitResolve(fs *flag.FlagSet, conf map[string]string, setFlags []string, format string) {
	var vals []string
	var srcs []string
	for i := 0; i < NKEYS; i++ {
		li := layerValue(i, fs, conf, setFlags)
		if !li.Ok {
			failMsg("culvert: " + KEY_NAMES[i] + " (" + li.Layer + "): " + li.Problem)
			usageExit(2)
		}
		vals = append(vals, li.Value)
		srcs = append(srcs, li.Layer)
	}
	if format == "json" {
		out := "{"
		for i := 0; i < NKEYS; i++ {
			if i > 0 {
				out += ","
			}
			out += "\"" + KEY_NAMES[i] + "\":" + jsValue(i, vals[i])
		}
		out += "}\n"
		os.Stdout.Write([]byte(out))
	} else {
		out := ""
		for i := 0; i < NKEYS; i++ {
			out += pad(KEY_NAMES[i], 10) + " " + vals[i] + "\n"
		}
		os.Stdout.Write([]byte(out))
	}
}

// ---- diff output -----------------------------------------------------------

func emitDiff(fs *flag.FlagSet, conf map[string]string, setFlags []string, format string) {
	var keys []string
	var vals []string
	var srcs []string
	for i := 0; i < NKEYS; i++ {
		li := layerValue(i, fs, conf, setFlags)
		if !li.Ok {
			failMsg("culvert: " + KEY_NAMES[i] + " (" + li.Layer + "): " + li.Problem)
			usageExit(2)
		}
		cv, _ := configViewOf(i, conf)
		if li.Value != cv {
			keys = append(keys, KEY_NAMES[i])
			vals = append(vals, li.Value)
			srcs = append(srcs, li.Layer)
		}
	}
	if format == "json" {
		out := "{"
		for r := 0; r < len(keys); r++ {
			if r > 0 {
				out += ","
			}
			idx := findIndex(keys[r])
			out += jsStr(keys[r]) + ":{\"value\":" + jsValue(idx, vals[r]) + ",\"source\":" + jsStr(srcs[r]) + "}"
		}
		out += "}\n"
		os.Stdout.Write([]byte(out))
	} else {
		kw := 1
		vw := 1
		for r := 0; r < len(keys); r++ {
			if len(keys[r]) > kw {
				kw = len(keys[r])
			}
			if len(vals[r]) > vw {
				vw = len(vals[r])
			}
		}
		out := ""
		for r := 0; r < len(keys); r++ {
			out += pad(keys[r], kw) + " " + pad(vals[r], vw) + " " + srcs[r] + "\n"
		}
		os.Stdout.Write([]byte(out))
	}
	if len(keys) > 0 {
		usageExit(1)
	}
	usageExit(0)
}

// ---- check output ----------------------------------------------------------

type Problem struct {
	Setting string
	Layer   string
	Error   string
}

func emitCheck(fs *flag.FlagSet, conf map[string]string, setFlags []string, format string) {
	var probs []Problem
	for i := 0; i < NKEYS; i++ {
		// flag layer
		if containsStr(setFlags, KEY_FLAGS[i]) {
			prob := validateValue(i, flagString(fs, KEY_FLAGS[i]))
			if prob != "" {
				probs = append(probs, Problem{ KEY_NAMES[i], "flag", prob })
			}
		}
		// env layer
		ev, present := os.LookupEnv(ENV_NAMES[i])
		if present {
			prob := validateValue(i, strings.Trim(ev, " \t\r"))
			if prob != "" {
				probs = append(probs, Problem{ KEY_NAMES[i], "env", prob })
			}
		}
		// config layer
		key := KEY_NAMES[i]
		_, confOk := conf[key]
		if confOk {
			prob := validateValue(i, conf[key])
			if prob != "" {
				probs = append(probs, Problem{ KEY_NAMES[i], "config", prob })
			}
		}
	}
	ok := len(probs) == 0
	if format == "json" {
		okText := "false"
		if ok {
			okText = "true"
		}
		out := "{\"ok\":" + okText + ",\"problems\":["
		for r := 0; r < len(probs); r++ {
			if r > 0 {
				out += ","
			}
			out += "{\"setting\":" + jsStr(probs[r].Setting) + ",\"layer\":" + jsStr(probs[r].Layer) + ",\"error\":" + jsStr(probs[r].Error) + "}"
		}
		out += "]}\n"
		os.Stdout.Write([]byte(out))
	} else {
		if ok {
			os.Stdout.Write([]byte("all ok\n"))
		} else {
			kw := 1
			sw := 1
			for r := 0; r < len(probs); r++ {
				if len(probs[r].Setting) > kw {
					kw = len(probs[r].Setting)
				}
				if len(probs[r].Layer) > sw {
					sw = len(probs[r].Layer)
				}
			}
			out := ""
			for r := 0; r < len(probs); r++ {
				out += pad(probs[r].Setting, kw) + " " + pad(probs[r].Layer, sw) + " " + probs[r].Error + "\n"
			}
			os.Stdout.Write([]byte(out))
		}
	}
	if ok {
		usageExit(0)
	}
	usageExit(1)
}

// ---- main ------------------------------------------------------------------

func main() {
	flag.Parse()
	if flag.NArg() < 1 {
		failMsg("culvert: missing subcommand (resolve|diff|check)")
		usageExit(2)
	}
	sub := flag.Arg(0)
	if sub != "resolve" && sub != "diff" && sub != "check" {
		failMsg("culvert: unknown subcommand: " + sub)
		usageExit(2)
	}

	var fs *flag.FlagSet
	fs = flag.NewFlagSet("culvert " + sub, flag.ExitOnError)
	fs.String("format", "json", "output format: json or table")
	fs.String("config", DEFAULT_CONF, "path of the config file")
	fs.String("endpoint", "https://relay.example/sink", "relay endpoint")
	fs.String("region", "us-east", "deployment region")
	fs.Int("timeout-ms", 15000, "connection timeout in ms")
	fs.Int("retries", 3, "max retries")
	fs.Bool("verbose", false, "verbose mode")
	fs.Int("max-batch", 500, "max batch size")

	err := fs.Parse(flag.Args()[1:])
	if err != nil {
		usageExit(2)
	}
	if fs.NArg() > 0 {
		failMsg("culvert: unexpected argument: " + fs.Arg(0))
		usageExit(2)
	}

	format := fs.Lookup("format").Value.String()
	if format != "json" && format != "table" {
		failMsg("culvert: invalid --format: " + format)
		usageExit(2)
	}

	var setFlags []string
	fs.Visit(func(f *flag.Flag) {
		setFlags = append(setFlags, f.Name)
	})

	conf, badLine := readConfig(fs.Lookup("config").Value.String())
	if badLine > 0 {
		failMsg("culvert: config error: line " + strconv.Itoa(badLine))
		usageExit(3)
	}

	if sub == "resolve" {
		emitResolve(fs, conf, setFlags, format)
	} else if sub == "diff" {
		emitDiff(fs, conf, setFlags, format)
	} else {
		emitCheck(fs, conf, setFlags, format)
	}
}
