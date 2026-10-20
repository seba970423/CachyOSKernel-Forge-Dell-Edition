#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
source "$REPO_ROOT/lib/pgp.sh"
source "$REPO_ROOT/lib/build.sh"
TEST_TMPDIR="$(mktemp -d --tmpdir kernelforge-pgp-test.XXXXXX)"
trap 'rm -rf -- "$TEST_TMPDIR"' EXIT
KEY_A=E18447AC260021D31F3FF6C4C8A2A4774B8B63C4
KEY_B=E8B9AA39F054E30E8290D492C3C4820857F654FE
KEY_OTHER=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
PACKAGE_DIR="$TEST_TMPDIR/upstream/linux-cachyos"
SRCINFO="$TEST_TMPDIR/srcinfo"
GPG_CALLS="$TEST_TMPDIR/gpg-calls"
PREP_CALLS="$TEST_TMPDIR/prepare-calls"
KEYRING="$TEST_TMPDIR/keyring"
OUTPUT="$TEST_TMPDIR/output"
LOG="$TEST_TMPDIR/log"
mkdir -p "$PACKAGE_DIR"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
expect_failure() {
    if ( "$@" ) >"$OUTPUT" 2>"$LOG"; then
        fail "Unexpected success: $*"
    fi
}
reset_fixture() {
    rm -rf -- "$KEYRING"
    mkdir -p "$KEYRING"
    : >"$GPG_CALLS"
    : >"$PREP_CALLS"
    printf 'pkgbase = linux-cachyos\n\tvalidpgpkeys = %s\n\tvalidpgpkeys = %s\n\tvalidpgpkeys = %s\n' \
        "${KEY_A,,}" "$KEY_A" "$KEY_B" >"$SRCINFO"
}
# Mock only external makepkg/GnuPG commands. No network or user keyring access.
makepkg() {
    if [[ "${1:-}" == --printsrcinfo ]]; then
        [[ "${SRCINFO_FAIL:-no}" != yes ]] || return 2
        cat "$SRCINFO"
    else
        printf '%s\n' "$*" >>"$PREP_CALLS"
    fi
}
gpg() {
    local fingerprint="${!#}" state validity returned
    [[ " $* " == *" --batch "* ]] || fail 'GnuPG was not called in batch mode.'
    case " $* " in
        *" --recv-keys "*)
            printf '%s\n' "$*" >>"$GPG_CALLS"
            [[ "${FAIL_BOTH:-no}" != yes ]] || return 2
            if [[ "${FAIL_FIRST:-no}" == yes &&
                  " $* " == *" hkps://keyserver.ubuntu.com "* ]]; then
                return 2
            fi
            if [[ "${STAY_EXPIRED:-no}" == yes ]]; then
                printf 'expired\n' >"$KEYRING/$fingerprint"
            else
                printf 'present\n' >"$KEYRING/$fingerprint"
            fi
            ;;
        *" --list-keys "*)
            [[ -f "$KEYRING/$fingerprint" ]] || return 2
            state="$(< "$KEYRING/$fingerprint")"
            validity=-
            [[ "$state" != expired ]] || validity=e
            printf 'pub:%s:::::::::\nfpr:::::::::%s:\n' "$validity" "$fingerprint"
            ;;
        *" --fingerprint "*)
            returned="$fingerprint"
            [[ "${MISMATCH:-no}" != yes ]] || returned="$KEY_OTHER"
            printf 'fpr:::::::::%s:\n' "$returned"
            ;;
        *) fail "Unexpected GnuPG call: $*" ;;
    esac
}
check_count() {
    local actual
    actual="$(wc -l <"$GPG_CALLS")"
    [[ "$actual" -eq "$1" ]] || fail "Expected $1 imports, found $actual."
}
ensure_keys() {
    ensure_upstream_pgp_keys "$PACKAGE_DIR" >"$OUTPUT" 2>"$LOG"
}

# Missing keys import once per pinned fingerprint, normalize case, and never
# consume stdin or contaminate the source-tree path printed on stdout.
reset_fixture
printf 'sentinel\n' >"$TEST_TMPDIR/input"
exec 3<"$TEST_TMPDIR/input"
ensure_keys <&3
read -r remaining <&3
exec 3<&-
[[ "$remaining" == sentinel ]] || fail 'Automatic key import consumed an answer.'
[[ ! -s "$OUTPUT" ]] || fail 'Key setup wrote to stdout.'
check_count 2
grep -Fq "$KEY_A" "$GPG_CALLS" || fail 'First pinned key was not imported.'
grep -Fq "$KEY_B" "$GPG_CALLS" || fail 'Second pinned key was not imported.'
! grep -q 'Import/refresh.*\[Y/n\]' "$LOG" || fail 'Import prompt remains.'

# Existing keys are left alone, and noninteractive input also succeeds.
: >"$GPG_CALLS"
ensure_keys </dev/null
check_count 0
printf 'expired\n' >"$KEYRING/$KEY_A"
ensure_keys </dev/null
check_count 1
[[ "$(pgp_key_state "$KEY_A")" == present ]] || fail 'Expired key was not refreshed.'

# First-server failure falls back, still using the exact full fingerprint.
reset_fixture
printf 'present\n' >"$KEYRING/$KEY_B"
FAIL_FIRST=yes ensure_keys </dev/null
check_count 2
grep -q 'hkps://keys.openpgp.org' "$GPG_CALLS" || fail 'Keyserver fallback was not used.'

reset_fixture
FAIL_BOTH=yes expect_failure ensure_keys
check_count 2
reset_fixture
MISMATCH=yes expect_failure ensure_keys
grep -q 'fingerprint did not match' "$LOG" || fail 'Mismatched fingerprint was accepted.'
reset_fixture
STAY_EXPIRED=yes expect_failure ensure_keys
grep -q 'still expired' "$LOG" || fail 'Unusable refreshed key was accepted.'

# No signing keys is valid; a failed metadata query is a different result.
reset_fixture
printf 'pkgbase = unsigned-fixture\n' >"$SRCINFO"
ensure_keys </dev/null
check_count 0
reset_fixture
SRCINFO_FAIL=yes expect_failure ensure_keys
check_count 0
grep -q 'Could not read signing-key fingerprints' "$LOG" || fail 'Metadata failure was hidden.'
printf '\tvalidpgpkeys = 4B8B63C4\n' >"$SRCINFO"
expect_failure ensure_keys
check_count 0

# Failure propagates through the real preparation function, including command
# substitution (where errexit alone cannot be relied upon).
reset_fixture
if tree="$(SRCINFO_FAIL=yes prepare_upstream_source "$TEST_TMPDIR/upstream" linux-cachyos 2>"$LOG")"; then
    fail 'Source preparation continued after key metadata failure.'
fi
[[ ! -s "$PREP_CALLS" && -z "$tree" ]] || fail 'Failed key setup started source preparation.'
reset_fixture
if tree="$(FAIL_BOTH=yes prepare_upstream_source "$TEST_TMPDIR/upstream" linux-cachyos 2>"$LOG")"; then
    fail 'Source preparation continued after key retrieval failure.'
fi
[[ ! -s "$PREP_CALLS" && -z "$tree" ]] || fail 'Failed retrieval started source preparation.'

# Successful preparation retains the normal verified makepkg invocation.
reset_fixture
mkdir -p "$PACKAGE_DIR/src/linux/scripts"
printf '#!/bin/sh\n' >"$PACKAGE_DIR/src/linux/scripts/config"
chmod +x "$PACKAGE_DIR/src/linux/scripts/config"
tree="$(prepare_upstream_source "$TEST_TMPDIR/upstream" linux-cachyos 2>"$LOG")"
[[ "$tree" == "$PACKAGE_DIR/src/linux" ]] || fail 'Source-tree stdout was corrupted.'
grep -qx -- '-s -o' "$PREP_CALLS" || fail 'Unexpected source preparation invocation.'

printf 'Automatic signing-key tests passed.\n'
