#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
source "$REPO_ROOT/lib/sched-compat.sh"
TEST_TMPDIR="$(mktemp -d --tmpdir kernelforge-scheduler-test.XXXXXX)"
trap 'rm -rf -- "$TEST_TMPDIR"' EXIT
TREE="$TEST_TMPDIR/tree with spaces"
SRC="$TREE/kernel/sched/fair.c"
mkdir -p "$TREE/kernel/sched"
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
expect_fail() { if ( "$@" ) >/dev/null 2>&1; then fail "Unexpected success: $*"; fi; }

write_buggy_source() {
    cat >"$SRC" <<'SRCFILE'
#ifdef CONFIG_SCHED_BORE
__read_mostly uint sysctl_sched_base_slice = nsecs_per_tick;
#else
unsigned int sysctl_sched_base_slice = 700000ULL;
static unsigned int normalized_sysctl_sched_base_slice = 700000ULL;
#endif
static inline void update_protect_slice(struct cfs_rq *cfs_rq, struct sched_entity *se)
{
    u64 slice = normalized_sysctl_sched_base_slice;
    u64 vprot = se->deadline;
}
SRCFILE
}
write_buggy_source
printf 'CONFIG_SCHED_BORE=y\n' > "$TREE/.config"
kernelforge_apply_sched_compat "$TREE" >/dev/null
[[ $(grep -Fc '/* KernelForge: CachyOS 7.3 BORE slice compatibility. */' "$SRC") == 1 ]] || fail 'Guarded workaround missing.'
grep -Fq 'u64 slice = sysctl_sched_base_slice;' "$SRC" || fail 'Missing BORE fallback.'
grep -Fq 'u64 slice = normalized_sysctl_sched_base_slice;' "$SRC" || fail 'Non-BORE behavior was removed.'
cp "$SRC" "$TEST_TMPDIR/patched"
kernelforge_apply_sched_compat "$TREE" >/dev/null
cmp "$TEST_TMPDIR/patched" "$SRC" || fail 'Second invocation was not idempotent.'

write_buggy_source
cp "$SRC" "$TEST_TMPDIR/unmodified"
printf '# CONFIG_SCHED_BORE is not set\n' > "$TREE/.config"
kernelforge_apply_sched_compat "$TREE" >/dev/null
cmp "$SRC" "$TEST_TMPDIR/unmodified" || fail 'Non-BORE source was modified.'

printf 'CONFIG_SCHED_BORE=y\n' > "$TREE/.config"
sed -i 's/u64 slice = normalized_sysctl_sched_base_slice;/u64 slice = sysctl_sched_base_slice;/' "$SRC"
cp "$SRC" "$TEST_TMPDIR/upstream-fixed"
kernelforge_apply_sched_compat "$TREE" >/dev/null
cmp "$SRC" "$TEST_TMPDIR/upstream-fixed" || fail 'Upstream-fixed source was modified.'

write_buggy_source
sed -i 's/u64 slice = normalized_sysctl_sched_base_slice;/u64 slice = strange_variable;/' "$SRC"
cp "$SRC" "$TEST_TMPDIR/unrecognized"
expect_fail kernelforge_apply_sched_compat "$TREE"
cmp "$SRC" "$TEST_TMPDIR/unrecognized" || fail 'Unknown source was altered.'

rm "$SRC"
expect_fail kernelforge_apply_sched_compat "$TREE"

write_buggy_source
make() { printf '%s\n' "$*" >> "$TEST_TMPDIR/make-args"; }
: > "$TEST_TMPDIR/make-args"
kernelforge_sched_smoke_test "$TREE" "$TEST_TMPDIR/smoke.log" >/dev/null
grep -Fq -- '-j1 kernel/sched/fair.o' "$TEST_TMPDIR/make-args" || fail 'Missing scheduler smoke-test target.'
: > "$TEST_TMPDIR/make-args"
printf '# CONFIG_SCHED_BORE is not set\n' > "$TREE/.config"
kernelforge_sched_smoke_test "$TREE" "$TEST_TMPDIR/smoke.log" >/dev/null
[[ ! -s "$TEST_TMPDIR/make-args" ]] || fail 'Non-BORE kernel unexpectedly ran smoke test.'

printf 'Scheduler compatibility/preflight tests passed.\n'
