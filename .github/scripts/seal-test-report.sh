#!/usr/bin/env bash
# Sealed-build helper: print the test results of a captured mocha/karma run
# (per-suite passing/pending/failing counts), every pending/skipped test with
# its full suite path, and the upstream skip gates in the test sources that
# produce those skips (environment checks: Node-only / browser-only /
# document-only suites, win32-only gates, sync-XHR gates, known upstream bugs).
# Usage: bash .github/scripts/seal-test-report.sh <captured-test-output.log>
set -u
LOG="$1"
CLEAN="$(mktemp)"
# mocha spec / karma-spec-reporter print pending specs in cyan ("ESC[36m- <title>");
# tag those as "@@PENDING@@ <title>" before stripping colours, so plain "- " lines
# (npm/nx project lists) are not mistaken for skipped tests.
sed -e 's/\x1b\[36m\( *\)- /\1@@PENDING@@ /' "$LOG" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\r' > "$CLEAN"

echo "=== test result summary (mocha per-suite counts, karma totals, nx totals) ==="
grep -a -E "[0-9]+ (passing|pending|failing)|Executed [0-9]+ of [0-9]+|Successfully ran target|Ran target" "$CLEAN"
echo "TOTAL mocha passing: $(grep -a -E '^ *[0-9]+ passing' "$CLEAN" | awk '{s+=$1} END {print s+0}')"
echo "TOTAL mocha pending: $(grep -a -E '^ *[0-9]+ pending' "$CLEAN" | awk '{s+=$1} END {print s+0}')"
echo "TOTAL mocha failing: $(grep -a -E '^ *[0-9]+ failing' "$CLEAN" | awk '{s+=$1} END {print s+0}')"
echo "TOTAL karma executed (sum of final 'Executed N of M' lines): $(grep -a -o -E 'TOTAL: [0-9]+ SUCCESS' "$CLEAN" | awk '{s+=$2} END {print s+0}')"

echo
echo "=== every pending/skipped test, with its suite path (Suite > Sub-suite > test) ==="
# pending specs are indented under their suites; rebuild the suite path from
# the indentation (mocha/karma spec reporters indent suites by 2 per level).
awk '
  {
    line = $0
    if (line ~ /^[ \t]*$/) next
    match(line, /^ */); ind = RLENGTH; text = substr(line, ind + 1)
    if (text ~ /^@@PENDING@@ /) {
      path = ""
      for (i = 1; i <= n; i++) if (sind[i] < ind) path = path stxt[i] " > "
      print "SKIPPED: " path substr(text, 13)
      next
    }
    # unindented lines (npm/nx banners, karma "LOG:" console output, warnings),
    # stack-trace frames, webpack notes and coverage-table rows are not suites
    if (ind < 2 || text ~ /^at / || text ~ /^(@ |NX )/ || index(text, "|") > 0) next
    while (n > 0 && sind[n] >= ind) n--
    n++; sind[n] = ind; stxt[n] = text
  }
' "$CLEAN"

echo
echo "=== upstream skip gates in the test sources (condition + comment giving the reason) ==="
grep -rn -B3 -E "this\.skip\(\)|(it|describe)\.skip\(|\bxit\(|\bxdescribe\(" \
  --include='*.ts' --include='*.mjs' --include='*.cjs' --include='*.js' \
  --exclude-dir=node_modules --exclude-dir=build \
  api packages experimental/packages 2>/dev/null | grep '/test/'

echo
echo "=== definitions of the environment-gated describe helpers (describeNode / describeBrowser / describeDocument) ==="
grep -rn -A5 -E "function describe(Browser|Node|Document)|const describe(Browser|Node|Document) *=|const isBrowser *=" \
  --include='*.ts' --exclude-dir=node_modules api packages experimental/packages 2>/dev/null | grep '/test/' | head -80
rm -f "$CLEAN"
