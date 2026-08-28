#!/bin/bash
# shellcheck disable=SC1091,SC2034 # The sourced helper consumes test globals.
set -euo pipefail

vg_test_root=$(mktemp -d)
trap 'rm -rf "$vg_test_root"' EXIT

vg_dir_credential="$vg_test_root/credential"
mkdir -m 700 "$vg_dir_credential"
vg_username_char='a-z'
vg_username_length=12
vg_password_char='A-Za-z0-9'
vg_password_length=32
vg_log_file="$vg_test_root/output.log"

function f_log() {
	printf '%s\n' "$*" >> "$vg_log_file"
}

# shellcheck source=../src/credential-utils.sh
source "$(dirname "$0")/../src/credential-utils.sh"

Y_TEST_SECRET='do-not-print-this-value'
[[ $(f_credential Y_TEST_SECRET password) == "$Y_TEST_SECRET" ]]
f_show_cred Y_TEST_SECRET
grep -q 'CRED_Y_TEST_SECRET : \[redacted\]' "$vg_log_file"
if grep -q "$Y_TEST_SECRET" "$vg_log_file"; then
	printf 'credential value leaked to logs\n' >&2
	exit 1
fi

if f_credential 'Y_TEST_SECRET;id' password >/dev/null 2>&1; then
	printf 'unsafe variable name was accepted\n' >&2
	exit 1
fi

unset Y_GENERATED_SECRET
vg_first=$(f_credential Y_GENERATED_SECRET password)
vg_second=$(f_credential Y_GENERATED_SECRET password)
[[ $vg_first == "$vg_second" ]]
[[ ${#vg_first} -eq $vg_password_length ]]

if [[ $(stat -c '%a' "$vg_dir_credential/Y_GENERATED_SECRET") != 600 ]]; then
	printf 'credential file mode is not 600\n' >&2
	exit 1
fi

ln -s "$vg_test_root/missing" "$vg_dir_credential/Y_SYMLINK_SECRET"
if f_credential Y_SYMLINK_SECRET password >/dev/null 2>&1; then
	printf 'credential symlink was accepted\n' >&2
	exit 1
fi

printf 'credential security tests passed\n'
