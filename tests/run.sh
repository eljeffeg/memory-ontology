#!/usr/bin/env bash
# Validates every fixture under tests/ against the temporal and memory shapes,
# loaded together as the README says.
#
#   tests/valid/*.ttl    must conform.
#   tests/invalid/*.ttl  must not conform, and the set of result messages must
#                        equal the fixture's "# expect: <message>" lines, so a
#                        fixture fails for the reason it names and no other.
#
#   tests/vectors/       bitemporal cases with expected answers, checked by
#                        running held.rq (see tests/vectors/README.md).
#
# Needs Apache Jena's `riot`, `shacl` and `arq` on PATH, from a release that reads RDF
# 1.2 triple terms (tested with Jena 6.3.0 on Java 21). Set JENA_HOME to use
# bin/ from a Jena download.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(dirname "$here")"
if [[ -n "${JENA_HOME:-}" ]]; then PATH="$JENA_HOME/bin:$PATH"; fi
command -v shacl >/dev/null && command -v riot >/dev/null && command -v arq >/dev/null || {
  echo "riot, shacl and arq (Apache Jena) must be on PATH, or set JENA_HOME" >&2; exit 2; }

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

# Bitemporal cases: tests/vectors/held.rq is run over records.ttl and cases.ttl,
# and its answer for each case must equal what the case expects.
vec="$here/vectors"
tsv() { sed -e 1d -e 's/<https:\/\/example.org\/vectors#\([^>]*\)>/\1/g' \
            -e 's/<https:\/\/example.org\/\([^>]*\)>/\1/g' -e 's/"\^\^<[^>]*>//g' -e 's/"//g'; }
ask() { arq --data "$vec/records.ttl" --data "$vec/cases.ttl" --query "$1" --results=TSV 2>/dev/null | tsv; }
# Prints the cases whose answer differs from the expectation, one per line.
differing() {
  local held="$1" c
  for c in $(cut -f1 "$work/expected.tsv" | sort -u); do
    local want got ok=1 rec end
    want="$(awk -F'\t' -v c="$c" '$1==c && $3=="holds" {print $4}' "$work/expected.tsv" | sort | paste -sd' ' -)"
    got="$(awk -F'\t' -v c="$c" '$1==c {print $2}' "$held" | sort | paste -sd' ' -)"
    [[ "$want" == "$got" ]] || ok=0
    while IFS=$'\t' read -r rec end; do
      [[ -z "$rec" ]] && continue
      [[ "$(awk -F'\t' -v c="$c" -v r="$rec" '$1==c && $2==r {print $3}' "$held")" == "$end" ]] || ok=0
    done < <(awk -F'\t' -v c="$c" '$1==c && ($3=="end" || $3=="no-end") {print $4 "\t" $5}' "$work/expected.tsv")
    [[ $ok -eq 1 ]] || printf '%s\t%s\t%s\n' "$c" "$want" "$got"
  done
}

out="$(report "$vec/records.ttl")"
if [[ "$out" == *"Conforms"* ]]; then
  pass=$((pass+1)); echo "ok    vectors/records.ttl conforms"
else
  fail=$((fail+1)); echo "FAIL  vectors/records.ttl should conform:"; echo "$out" | sed 's/^/      /'
fi

ask "$vec/expected.rq" > "$work/expected.tsv"
ask "$vec/held.rq" > "$work/held.tsv"
differing "$work/held.tsv" > "$work/differing.tsv"
for c in $(cut -f1 "$work/expected.tsv" | sort -u); do
  label="$(awk -F'\t' -v c="$c" '$1==c {print $2; exit}' "$work/expected.tsv")"
  if line="$(grep -P "^$c\t" "$work/differing.tsv")"; then
    fail=$((fail+1)); echo "FAIL  vectors/$c $label"
    echo "      expected: $(printf '%s' "$line" | cut -f2)"
    echo "      got:      $(printf '%s' "$line" | cut -f3)"
  else
    pass=$((pass+1)); echo "ok    vectors/$c $label"
  fi
done

# Control: the same query with the two "the cut sees the closing record" filters
# removed reads a close as soon as it exists, whenever it was recorded. That is
# the defect the closing record's own recorded time removes, so the cases must
# catch it. A run where this control agrees with every case proves nothing.
grep -v '# the cut sees the closing record' "$vec/held.rq" > "$work/control.rq"
ask "$work/control.rq" > "$work/control.tsv"
caught="$(differing "$work/control.tsv" | wc -l | tr -d ' ')"
if [[ "$caught" -gt 0 ]]; then
  pass=$((pass+1)); echo "ok    vectors/control: ignoring when a close was recorded changes $caught cases"
else
  fail=$((fail+1)); echo "FAIL  vectors/control: a query that ignores when a close was recorded passed every case"
fi

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
