#!/usr/bin/env bash
# Validates every fixture under tests/ against the temporal and memory shapes,
# loaded together as the README says.
#
#   tests/valid/*.ttl    must conform.
#   tests/invalid/*.ttl  must not conform, and the set of result messages must
#                        equal the fixture's "# expect: <message>" lines, so a
#                        fixture fails for the reason it names and no other.
#
# Needs Apache Jena's `riot` and `shacl` on PATH, from a release that reads RDF
# 1.2 triple terms (tested with Jena 6.3.0 on Java 21). Set JENA_HOME to use
# bin/ from a Jena download.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(dirname "$here")"
if [[ -n "${JENA_HOME:-}" ]]; then PATH="$JENA_HOME/bin:$PATH"; fi
command -v shacl >/dev/null && command -v riot >/dev/null || {
  echo "riot and shacl (Apache Jena) must be on PATH, or set JENA_HOME" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
shapes="$work/shapes.ttl"
riot --quiet --output=turtle \
  "$root/ontologies/temporal-shapes.shacl.ttl" \
  "$root/ontologies/memory-shapes.shacl.ttl" > "$shapes"

pass=0; fail=0
report() { shacl validate --text --shapes "$shapes" --data "$1" 2>&1; }
messages() { sed -n 's/^ *Message: //p' | sort -u; }

for f in "$here"/valid/*.ttl; do
  out="$(report "$f")"
  if [[ "$out" == *"Conforms"* ]]; then
    pass=$((pass+1)); echo "ok    valid/$(basename "$f")"
  else
    fail=$((fail+1)); echo "FAIL  valid/$(basename "$f") should conform:"; echo "$out" | sed 's/^/      /'
  fi
done

for f in "$here"/invalid/*.ttl; do
  want="$(sed -n 's/^# expect: //p' "$f" | sort -u)"
  if [[ -z "$want" ]]; then
    fail=$((fail+1)); echo "FAIL  invalid/$(basename "$f") has no '# expect:' line"; continue
  fi
  out="$(report "$f")"
  got="$(printf '%s\n' "$out" | messages)"
  if [[ "$out" != *"Conforms"* && "$got" == "$want" ]]; then
    pass=$((pass+1)); echo "ok    invalid/$(basename "$f")"
  else
    fail=$((fail+1)); echo "FAIL  invalid/$(basename "$f")"
    echo "      expected: $(echo "$want" | paste -sd'|' -)"
    echo "      got:      $(echo "$got" | paste -sd'|' -)"
  fi
done

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
