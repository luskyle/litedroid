#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
PROJECT="$TMP/project"
BSP="$TMP/vendor bsp"
CONFIG="$TMP/local.conf"
mkdir -p "$PROJECT/scripts" "$PROJECT/android/litedroid" "$BSP/build" "$TMP/bin"
cp "$ROOT/scripts/litedroid" "$PROJECT/scripts/"
cp "$ROOT/android/litedroid/product.mk" "$PROJECT/android/litedroid/"
git -C "$PROJECT" init -q
git -C "$PROJECT" -c user.name=Test -c user.email=test@example.invalid \
    -c commit.gpgsign=false commit -q --allow-empty -m fixture

cat > "$BSP/build/envsetup.sh" <<'EOF'
lunch() {
    [[ "$1" == vendor_test-userdebug ]] || return 1
    [[ "${TEST_LUNCH_FAIL:-0}" != 1 ]] || return 1
}
get_build_var() {
    case "$1" in
        LITEDROID_PROFILE) printf '%s\n' "${TEST_PROFILE:-}" ;;
        PRODUCT_PACKAGES) printf '%s\n' "${TEST_PACKAGES:-Settings SystemUI}" ;;
        PRODUCT_OUT) printf '%s\n' "${TEST_PRODUCT_OUT-out/target/product/test}" ;;
        *) return 1 ;;
    esac
}
EOF
cat > "$BSP/Makefile" <<'EOF'
all:
	@test "$${TEST_BUILD_FAIL:-0}" != 1
	@if test "$${TEST_NO_IMAGES:-0}" != 1; then \
	    mkdir -p out/target/product/test; \
	    printf 'fixture-image\n' > out/target/product/test/system.img; \
	fi
EOF
cat > "$TMP/bin/adb" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == -s && "$2" == fixture-serial ]] || exit 2
shift 2
case "$*" in
    get-state) printf '%s\n' "${TEST_ADB_STATE:-device}" ;;
    "shell getprop "*)
        [[ "${TEST_ADB_FAIL:-0}" != 1 ]] || exit 3
        printf 'fixture-value\r\n'
        ;;
    "shell wm size"|"shell dumpsys meminfo"|"shell cat /proc/uptime"|"shell df -k /data")
        printf 'fixture-evidence\n'
        ;;
    *) exit 4 ;;
esac
EOF
chmod +x "$TMP/bin/adb"
export PATH="$TMP/bin:$PATH"

write_config() {
    printf 'board=test\nbsp_dir=%s\nlunch_target=vendor_test-userdebug\njobs=2\nremove_packages=%s\n' \
        "$BSP" "${1:-}" > "$CONFIG"
}
run_cli() { bash "$PROJECT/scripts/litedroid" "$@"; }
expect_failure() {
    local pattern="$1"
    shift
    if "$@" > "$TMP/failure.log" 2>&1; then
        printf 'FAIL: expected failure: %s\n' "$*" >&2
        exit 1
    fi
    grep -F -- "$pattern" "$TMP/failure.log" >/dev/null || {
        cat "$TMP/failure.log" >&2
        printf 'FAIL: expected error text: %s\n' "$pattern" >&2
        exit 1
    }
    printf 'PASS: %s\n' "$pattern"
}

run_cli --help >/dev/null
expect_failure "CONFIG is required" run_cli doctor
expect_failure "Unknown command" run_cli unknown "$CONFIG"
expect_failure "absolute vendor BSP path" run_cli doctor "$ROOT/configs/rk3566.conf"
expect_failure "absolute vendor BSP path" run_cli doctor "$ROOT/configs/rk3576.conf"
write_config
printf 'unsupported=value\n' >> "$CONFIG"
expect_failure "Unknown config key" run_cli doctor "$CONFIG"
write_config
printf 'board=duplicate\n' >> "$CONFIG"
expect_failure "Duplicate config key" run_cli doctor "$CONFIG"
write_config 'Settings;touch /tmp/litedroid-invalid'
expect_failure "Invalid package list" run_cli doctor "$CONFIG"
write_config '-invalid'
expect_failure "Invalid package name" run_cli doctor "$CONFIG"
write_config
printf 'jobs=0\n' > "$TMP/invalid-jobs.conf"
printf 'board=test\n' >> "$TMP/invalid-jobs.conf"
expect_failure "jobs must be" run_cli doctor "$TMP/invalid-jobs.conf"
run_cli doctor "$CONFIG" > "$TMP/doctor.log"
grep -F "Basic checks passed" "$TMP/doctor.log" >/dev/null
printf 'PASS: configured doctor with a BSP path containing spaces\n'

expect_failure "Profile must be" run_cli build "$CONFIG" invalid
expect_failure "Run integrate" run_cli build "$CONFIG" product
run_cli build "$CONFIG" baseline > "$TMP/baseline.log"
grep -F "Build passed" "$TMP/baseline.log" >/dev/null
sha256sum -c "$PROJECT"/out/test-build-*/images.sha256 >/dev/null
printf 'PASS: baseline build and image checksum verification\n'
expect_failure "Baseline must use" env TEST_PROFILE=minimal bash "$PROJECT/scripts/litedroid" build "$CONFIG" baseline
expect_failure "Selected product does not include" bash -c \
    'bash "$1" integrate "$2" >/dev/null; bash "$1" build "$2" product' \
    fixture "$PROJECT/scripts/litedroid" "$CONFIG"
run_cli integrate "$CONFIG" > "$TMP/integrate.log"
grep -F "nothing changed" "$TMP/integrate.log" >/dev/null
printf 'PASS: integration is idempotent\n'

write_config 'Calendar Music'
expect_failure "trimming config differs" run_cli integrate "$CONFIG"
printf 'LITEDROID_REMOVE_PACKAGES := Calendar Music\n' > "$BSP/vendor/litedroid/config.mk"
cat > "$BSP/product-test.mk" <<'EOF'
PRODUCT_PACKAGES := Settings Calendar SystemUI Music
include vendor/litedroid/product.mk
.PHONY: print
print:
	@printf '%s\n' "$(LITEDROID_PROFILE)" "$(PRODUCT_PACKAGES)"
EOF
make -s -C "$BSP" -f product-test.mk print > "$TMP/make-product.log"
printf 'minimal\nSettings SystemUI\n' > "$TMP/expected-product.log"
cmp "$TMP/expected-product.log" "$TMP/make-product.log"
printf 'PASS: actual product fragment removes only selected Make packages\n'
printf 'LITEDROID_REMOVE_PACKAGES := \n' > "$BSP/vendor/litedroid/config.mk"
make -s -C "$BSP" -f product-test.mk print > "$TMP/make-product.log"
printf 'minimal\nSettings Calendar SystemUI Music\n' > "$TMP/expected-product.log"
cmp "$TMP/expected-product.log" "$TMP/make-product.log"
printf 'PASS: empty removal list preserves the original product packages\n'
printf 'LITEDROID_REMOVE_PACKAGES := Calendar Music\n' > "$BSP/vendor/litedroid/config.mk"
expect_failure "Package Music is still included" env TEST_PROFILE=minimal \
    TEST_PACKAGES="Settings Music SystemUI" bash "$PROJECT/scripts/litedroid" build "$CONFIG" product
env TEST_PROFILE=minimal bash "$PROJECT/scripts/litedroid" build "$CONFIG" product > "$TMP/product.log"
grep -F "Build passed" "$TMP/product.log" >/dev/null
printf 'PASS: product build checks final package list\n'

expect_failure "Vendor build failed" env TEST_PROFILE=minimal TEST_BUILD_FAIL=1 \
    bash "$PROJECT/scripts/litedroid" build "$CONFIG" product
if grep -F "Build passed" "$TMP/failure.log" >/dev/null; then
    printf 'FAIL: failed build reported success\n' >&2
    exit 1
fi
expect_failure "Selected product does not include" env TEST_LUNCH_FAIL=0 \
    bash "$PROJECT/scripts/litedroid" build "$CONFIG" product
expect_failure "Vendor lunch failed" env TEST_LUNCH_FAIL=1 \
    bash "$PROJECT/scripts/litedroid" build "$CONFIG" baseline
expect_failure "empty PRODUCT_OUT" env TEST_PRODUCT_OUT="" TEST_PROFILE=minimal \
    bash "$PROJECT/scripts/litedroid" build "$CONFIG" product

printf '# unexpected modification\n' >> "$BSP/vendor/litedroid/product.mk"
expect_failure "fragment differs" run_cli integrate "$CONFIG"
cp "$ROOT/android/litedroid/product.mk" "$BSP/vendor/litedroid/product.mk"
rm -- "$BSP/out/target/product/test/system.img"
expect_failure "No .img artifacts" env TEST_PROFILE=minimal TEST_NO_IMAGES=1 \
    bash "$PROJECT/scripts/litedroid" build "$CONFIG" product

expect_failure "explicit adb serial" run_cli report "$CONFIG" ""
expect_failure "not online/authorized" env TEST_ADB_STATE=offline \
    bash "$PROJECT/scripts/litedroid" report "$CONFIG" fixture-serial
expect_failure "adb command failed" env TEST_ADB_FAIL=1 \
    bash "$PROJECT/scripts/litedroid" report "$CONFIG" fixture-serial
run_cli report "$CONFIG" fixture-serial > "$TMP/report.log"
grep -F "Read-only report collected" "$TMP/report.log" >/dev/null
reports=("$PROJECT"/out/test-report-*/device.properties)
complete=0
for report in "${reports[@]}"; do
    if [[ "$(wc -l < "$report")" == 6 ]]; then complete=$((complete + 1)); fi
done
[[ "$complete" == 1 ]] || { printf 'FAIL: expected one complete device report\n' >&2; exit 1; }
printf 'PASS: device evidence and adb failure propagation\n'
printf 'All workflow tests passed.\n'
