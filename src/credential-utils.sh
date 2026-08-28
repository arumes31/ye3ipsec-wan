#!/bin/bash
# shellcheck disable=SC2154 # Globals are initialized by entrypoint.sh or the test harness.

# Credential helpers are kept separate so their security properties can be
# tested without starting strongSwan or changing the host network.

function f_valid_credential_name() {
	[[ $1 =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

function f_credential() {
	local vl_cred_var=$1
	local vl_cred_kind=$2
	local vl_persistent=${3:-yes}
	local vl_cred_value
	local vl_char
	local vl_size
	local vl_result
	local vl_credential_file
	local vl_temporary_file

	if ! f_valid_credential_name "$vl_cred_var"; then
		printf 'invalid credential variable name: %s\n' "$vl_cred_var" >&2
		return 1
	fi

	# Bash indirect expansion reads the variable without interpreting shell syntax.
	vl_cred_value=${!vl_cred_var-}
	if [[ -n $vl_cred_value ]]; then
		printf '%s\n' "$vl_cred_value"
		return
	fi

	vl_credential_file="$vg_dir_credential/$vl_cred_var"
	if [[ $vl_persistent == yes && ( -e $vl_credential_file || -L $vl_credential_file ) ]]; then
		if [[ ! -f $vl_credential_file || -L $vl_credential_file ]]; then
			printf 'unsafe credential file: %s\n' "$vl_credential_file" >&2
			return 1
		fi
		IFS= read -r vl_result < "$vl_credential_file"
		printf '%s\n' "$vl_result"
		return
	fi

	if [[ $vl_cred_kind == username ]]; then
		vl_char=$vg_username_char
		vl_size=$vg_username_length
	else
		vl_char=$vg_password_char
		vl_size=$vg_password_length
	fi

	vl_result=$(LC_ALL=C tr -dc "$vl_char" </dev/urandom | head -c "$vl_size")
	if [[ ${#vl_result} -ne $vl_size ]]; then
		printf 'credential generation failed for %s\n' "$vl_cred_var" >&2
		return 1
	fi

	if [[ $vl_persistent == yes ]]; then
		vl_temporary_file=$(mktemp "$vg_dir_credential/.${vl_cred_var}.XXXXXX")
		printf '%s\n' "$vl_result" > "$vl_temporary_file"
		chmod 600 "$vl_temporary_file"
		mv -f -- "$vl_temporary_file" "$vl_credential_file"
	fi

	printf '%s\n' "$vl_result"
}

function f_show_cred() {
	local vl_cred_var=$1
	local vl_cred_value

	if ! f_valid_credential_name "$vl_cred_var"; then
		printf 'invalid credential variable name: %s\n' "$vl_cred_var" >&2
		return 1
	fi

	vl_cred_value=${!vl_cred_var-}
	if [[ -n $vl_cred_value ]]; then
		f_log "    CRED_$vl_cred_var : [redacted]"
	fi
}

function f_show_credential_file() {
	local vl_label=$1
	local vl_path=$2

	if [[ -f $vl_path ]]; then
		f_log "    CRED_$vl_label : [redacted; retrieve from $vl_path]"
	fi
}
