#!/usr/bin/env python3
"""bracket-cable oracle: apply the Context.Copy() errors/accepted fix.

Patches context.go so that Context.Copy() duplicates the recorded Errors
array and the negotiated Accepted array into the snapshot, preserving order
and depth-of-copy semantics (later array-level mutations on either side do
not affect the other). Fails loudly if the tree no longer matches the
pinned parent version of Copy().
"""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "context.go"
s = open(path, encoding="utf-8").read()

old = """	cParams := c.Params
	cp.Params = make([]Param, len(cParams))
	copy(cp.Params, cParams)

	return &cp
}"""
new = """	cParams := c.Params
	cp.Params = make([]Param, len(cParams))
	copy(cp.Params, cParams)

	if c.Errors != nil {
		cp.Errors = make(errorMsgs, len(c.Errors))
		copy(cp.Errors, c.Errors)
	}

	if c.Accepted != nil {
		cp.Accepted = make([]string, len(c.Accepted))
		copy(cp.Accepted, c.Accepted)
	}

	return &cp
}"""

if old not in s:
    sys.exit("context.go no longer matches the pinned parent version of "
             "Context.Copy(); fix not applied (tree modified?)")

s = s.replace(old, new, 1)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(s)
print("context.go: Context.Copy() now copies Errors and Accepted")