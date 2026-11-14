# Tiny assertion helpers for POSIX sh tests. Source this file.

PASS=0
FAIL=0

check() {   # check NAME GOT WANT
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"
  else
    FAIL=$((FAIL + 1)); printf 'FAIL %s\n  got:  %s\n  want: %s\n' "$1" "$2" "$3"
  fi
}

check_contains() {   # check_contains NAME HAYSTACK NEEDLE
  case $2 in
    *"$3"*) PASS=$((PASS + 1)); printf 'ok   %s\n' "$1" ;;
    *) FAIL=$((FAIL + 1)); printf 'FAIL %s\n  got:      %s\n  expected: ...%s...\n' "$1" "$2" "$3" ;;
  esac
}

check_true() {   # check_true NAME COMMAND...
  name=$1; shift
  if "$@"; then PASS=$((PASS + 1)); printf 'ok   %s\n' "$name"
  else FAIL=$((FAIL + 1)); printf 'FAIL %s\n  command failed: %s\n' "$name" "$*"; fi
}

finish() {
  printf '%s: %d passed, %d failed\n' "${0##*/}" "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}
