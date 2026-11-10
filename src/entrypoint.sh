#!/bin/bash
# shellcheck disable=SC1091,SC2034,SC2148,SC1083,SC2001,SC2076,SC2005,SC1090,SC2053,SC2153,SC2046,SC2154

# Entrypoint for the container

# change timezone
cp "/usr/share/zoneinfo/$TZ" /etc/localtime
echo "$TZ" > /etc/timezone

# generated secrets, keys and configs must only be readable by root
umask 077

# ============ [ global variable ] ============

# date
vg_date=$(date "+$Y_DATE_FORMAT")

# base directory, without ending slash
vg_dir_swanctl="/etc/swanctl"

# the scripts in this directory (persistent volume) are sourced as root : they must be owned by root
# and must not be writable by group or others, otherwise another principal could run code as root
vg_dir_scripts=$vg_dir_swanctl/ye3ipsec-wan
chmod go-w "$vg_dir_swanctl" "$vg_dir_scripts" "$vg_dir_scripts"/*.sh 2>/dev/null
for vl_path in "$vg_dir_swanctl" "$vg_dir_scripts" "$vg_dir_scripts"/*.sh; do
	if [[ -e $vl_path ]] && { [[ $(stat -c %u "$vl_path") != 0 ]] || [[ -n $(find "$vl_path" -maxdepth 0 -perm /022) ]]; }; then
		echo "ERROR : $vl_path must be owned by root and not writable by group or others (run : chown root:root $vl_path ; chmod go-w $vl_path), refusing to start" >&2
		exit 1
	fi
done

# to load other env var
if [[ -f $vg_dir_swanctl/ye3ipsec-wan/bypass_container_env.sh ]] ; then

	# create/update symbolic link for bypass_container_env.sh
	ln -sfn $vg_dir_swanctl/ye3ipsec-wan/bypass_container_env.sh /etc/profile.d/bypass_container_env.sh
	
	# source
	source /etc/profile.d/bypass_container_env.sh > /dev/null 2>&1		
fi

# default language
vg_default_language="en_US"

# script name
vg_name=ye3ipsec-wan

# get default interface
vg_interface=$(route | awk '/^default/{print $NF}')
vg_interface_ip=$(ip addr show dev "$vg_interface" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)

# get external ip, only keep a valid ipv4 address
vg_ip=$(curl -m "$Y_URL_IP_CHECK_TIMEOUT" -s "$Y_URL_IP_CHECK" | tr -d '[:space:]')
if [[ ! $vg_ip =~ ^(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}$ ]]; then
	vg_ip=""
fi

# credential directory, without ending slash
vg_dir_credential=$vg_dir_swanctl/ye3ipsec-wan/credential
if [[ ! -d $vg_dir_credential ]]; then
    mkdir -p $vg_dir_credential
fi

# restrict access to directories holding secrets and private keys (also for existing volumes)
if [[ $Y_IGNORE_CONFIG == "no" ]]; then
	for vl_dir in "$vg_dir_scripts" "$vg_dir_credential" $vg_dir_swanctl/private $vg_dir_swanctl/pkcs12 $vg_dir_swanctl/conf.d; do
		if [[ -d $vl_dir ]]; then
			chmod 700 "$vl_dir"
			chmod -R go-rwx "$vl_dir" 2>/dev/null
		fi
	done
fi

# id and password parameters
vg_users_separator=":"
vg_username_char="a-z"
vg_username_length=12
vg_password_char="A-Za-z0-9"
vg_password_length=32

# ca certificate
vg_file_ca_key=$vg_dir_swanctl/private/caKey.pem
vg_file_ca_cert=$vg_dir_swanctl/x509ca/caCert.pem

# server certificate
vg_file_server_key=$vg_dir_swanctl/private/serverKey.pem
vg_file_server_cert=$vg_dir_swanctl/x509/serverCert.pem

# default client certificate
vg_file_client_key=$vg_dir_swanctl/private/clientKey.pem
vg_file_client_cert=$vg_dir_swanctl/x509/clientCert.pem
vg_file_client_p12=$vg_dir_swanctl/pkcs12/clientCert

# external certificate, lets encrypt for example
vg_file_external_key=$vg_dir_swanctl/private/privkey.pem
vg_file_external_cert=$vg_dir_swanctl/x509/cert.pem

# firewall function
vg_file_firewall=$vg_dir_swanctl/ye3ipsec-wan/firewall.sh

# certificate revocation list of the container CA
vg_file_crl=$vg_dir_swanctl/x509crl/ye3ipsec-wan.crl

# ============ [ function ] ============

# echo information for logs
function f_log(){

	# extra info in logs, if debug on
	vl_log=""
	if [[ $Y_DEBUG == "yes" ]]; then
		vl_log="$(date '+%Y-%m-%d %H:%M:%S') $(hostname) $vg_name:"
	fi

	echo -e "$vl_log $*"
}

# create random credential
function f_credential(){
	
	vl_cred_var=$1
	vl_cred_value=${!vl_cred_var}
	
	if [[ -z $3 ]]; then
		vl_persistent="yes"
	else
		vl_persistent=$3
	fi
	
	# if env credentials not exist : generate and make persistent to survive a container restart
	
	if [[ -z $vl_cred_value ]] ; then
		
		# verify if already exist
		if [[ -f $vg_dir_credential/$vl_cred_var ]] && [[ $vl_persistent == "yes" ]] ; then
			vl_result=$(cat $vg_dir_credential/"$vl_cred_var")
		else
			# generate
			if [[ $2 == "username" ]]; then
				vl_char=$vg_username_char
				vl_size=$vg_username_length
			else
				vl_char=$vg_password_char
				vl_size=$vg_password_length
			fi
			vl_result=$(tr -dc $vl_char </dev/urandom | head -c $vl_size)
			# never use or persist an empty credential
			if [[ ${#vl_result} -ne $vl_size ]]; then
				echo "ERROR : unable to generate $vl_cred_var" >&2
				exit 1
			fi
			# make persistent
			if [[ $vl_persistent == "yes" ]]; then
				echo "$vl_result" > $vg_dir_credential/"$vl_cred_var"
			fi
		fi
		echo "$vl_result"
	else
		# keep the stored value in sync with the environment, so that a rotated secret does not
		# silently fall back to an older stored value once the variable is removed
		if [[ $vl_persistent == "yes" ]] && [[ $(cat $vg_dir_credential/"$vl_cred_var" 2>/dev/null) != "$vl_cred_value" ]]; then
			echo "$vl_cred_value" > $vg_dir_credential/"$vl_cred_var"
		fi
		echo "$vl_cred_value"
	fi
	
}

# show client credential in log
function f_show_cred(){

	vl_cred_var=$1
	vl_cred_value=${!vl_cred_var}

	if [[ ! -z "$vl_cred_value" ]]; then
		f_log "    CRED_$vl_cred_var : $vl_cred_value"
	fi
}

# create random client certificate
function f_certificate(){

	local vl_cn=$1 vl_password=$2 vl_file vl_file_client_key vl_file_client_cert

	if [[ $3 == "default" ]]; then
		vl_file=""
	else
		vl_file=$3
	fi

	# client certificate
	vl_file_client_key="$vg_dir_swanctl/private/clientKey${vl_file}.pem"
	vl_file_client_cert="$vg_dir_swanctl/x509/clientCert${vl_file}.pem"

	pki --gen --outform pem > "$vl_file_client_key"
	pki --issue --outform pem --type priv --lifetime "$Y_CERT_DAYS" --in "$vl_file_client_key" --cacert $vg_file_ca_cert --cakey $vg_file_ca_key --dn "CN=$vl_cn" --san "$vl_cn" --flag clientAuth > "$vl_file_client_cert"

	f_export_p12 "$vl_password" "$vl_file"
}

# export a client certificate and its key to the pkcs12 files
function f_export_p12(){

	# the password goes through the environment, not the command line (visible in /proc/<pid>/cmdline)
	local -x vl_p12_password=$1
	local vl_file_client_key="$vg_dir_swanctl/private/clientKey${2}.pem"
	local vl_file_client_cert="$vg_dir_swanctl/x509/clientCert${2}.pem"
	local vl_file_client_p12="$vg_dir_swanctl/pkcs12/clientCert${2}"

	# export to p12
	openssl pkcs12 -in "$vl_file_client_cert" -inkey "$vl_file_client_key" -certfile $vg_file_ca_cert -export -out "$vl_file_client_p12".p12 -passout env:vl_p12_password

	# export to p12 pem
	openssl base64 -in "$vl_file_client_p12".p12 -out "$vl_file_client_p12".pem.p12

	if [[ $Y_CERT_P12_EXTRA == "yes" ]]; then

		# export to p12 legacy
		openssl pkcs12 -legacy -in "$vl_file_client_cert" -inkey "$vl_file_client_key" -certfile $vg_file_ca_cert -export -out "$vl_file_client_p12".legacy.p12 -passout env:vl_p12_password

		# export to p12 legacy no ca
		openssl pkcs12 -legacy -in "$vl_file_client_cert" -inkey "$vl_file_client_key" -export -out "$vl_file_client_p12".legacy.noca.p12 -passout env:vl_p12_password

		# export to p12 legacy pem
		openssl base64 -in "$vl_file_client_p12".legacy.p12 -out "$vl_file_client_p12".legacy.pem.p12

	fi
}

# revoke client certificates : add them to the CRL of the container CA (x509crl/, loaded by swanctl and
# checked by the revocation plugin), then delete their certificate, key and pkcs12 files
# $@ : certificate file suffixes (_<id>)
function f_revoke_certificates(){

	local vl_suffix vl_ext vl_args=()

	for vl_suffix in "$@"; do
		if [[ -s $vg_dir_swanctl/x509/clientCert${vl_suffix}.pem ]]; then
			vl_args+=(--cert "$vg_dir_swanctl/x509/clientCert${vl_suffix}.pem")
		fi
	done

	if [[ ${#vl_args[@]} -gt 0 ]]; then
		mkdir -p "$vg_dir_swanctl/x509crl"
		# keep the previous revocations, unless the CRL was signed by another (rotated) CA
		if [[ -s $vg_file_crl ]] && openssl crl -in "$vg_file_crl" -CAfile "$vg_file_ca_cert" -noout 2>&1 | grep -q "verify OK"; then
			vl_args+=(--lastcrl "$vg_file_crl")
		fi
		if ! pki --signcrl --cacert "$vg_file_ca_cert" --cakey "$vg_file_ca_key" --lifetime "$Y_SERVER_CERT_DAYS" "${vl_args[@]}" --outform pem > "$vg_file_crl.tmp"; then
			rm -f "$vg_file_crl.tmp"
			f_log "ERROR : unable to update the CRL $vg_file_crl, refusing to start while removed client certificates are still valid"
			exit 1
		fi
		mv -f "$vg_file_crl.tmp" "$vg_file_crl"
	fi

	for vl_suffix in "$@"; do
		f_log "$i_remove : client certificate ${vl_suffix#_} (revoked)"
		rm -f "$vg_dir_swanctl/x509/clientCert${vl_suffix}.pem" "$vg_dir_swanctl/private/clientKey${vl_suffix}.pem"
		# exact names written by f_export_p12 (a glob would also match the files of id "<id>.<suffix>")
		for vl_ext in p12 pem.p12 legacy.p12 legacy.noca.p12 legacy.pem.p12; do
			rm -f "$vg_dir_swanctl/pkcs12/clientCert${vl_suffix}.${vl_ext}"
		done
	done
}

# ---- user lists ----
# The user lists are declarative : the file generated from a list is rebuilt whenever the list changes,
# and removed when the list is emptied, so that a removed user or a rotated secret no longer authenticates.
# The sha256 of the last applied list is stored in the credential directory.

# true if every entry of the list $1 matches the regex $2
function f_list_matches(){
	local vl_user
	for vl_user in $1; do
		[[ $vl_user =~ $2 ]] || return 1
	done
	return 0
}

# decide what to do with the file $4 generated from the list $2 named $1
# $3 : regex every entry must match for the file to be rebuilt without losing generated credentials,
#      used when the file was generated by an older version (no stored list hash)
# return 0 : rebuild, 1 : keep, 2 : the list was emptied, remove the generated users
# after a successful rebuild or removal, the caller records the list with f_list_commit, so that
# an interrupted or failed synchronisation is retried on the next start
function f_list_state(){

	local vl_state=$vg_dir_credential/.$1.sha256 vl_hash vl_had_state=no

	[[ -f $vl_state ]] && vl_had_state=yes
	vg_list_hash=

	if [[ -z $2 ]]; then
		if [[ -e $4 ]]; then
			if [[ $vl_had_state == "yes" ]]; then
				return 2
			fi
			f_log "WARNING : $4 exists but $1 is empty, it was not generated by this version and is kept. Delete it if these users must be removed"
		fi
		rm -f "$vl_state"
		return 1
	fi

	vl_hash=$(printf '%s' "$2" | sha256sum | cut -d ' ' -f1)
	if [[ -e $4 ]] && [[ $vl_had_state == "yes" ]] && [[ $(cat "$vl_state") == "$vl_hash" ]]; then
		return 1
	fi

	if [[ -e $4 ]] && [[ $vl_had_state == "no" ]] && ! f_list_matches "$2" "$3"; then
		f_log "WARNING : $4 was generated by an older version from a list with generated credentials, it is kept as is. Delete it and restart to rebuild it from the list"
		echo "$vl_hash" > "$vl_state"
		return 1
	fi
	vg_list_hash=$vl_hash
	return 0
}

# record the list $1 decided by the last f_list_state as applied
function f_list_commit(){
	if [[ -n $vg_list_hash ]]; then
		echo "$vg_list_hash" > "$vg_dir_credential/.$1.sha256"
	else
		rm -f "$vg_dir_credential/.$1.sha256"
	fi
}

# synchronise a secrets file with its user list
# $1 name (conf.d/<name>.conf), $2 list, $3 regex (see f_list_state), $4 generator, $5 optional companion file name
function f_sync_users(){

	local vl_conf=$vg_dir_swanctl/conf.d/$1.conf

	f_list_state "$1" "$2" "$3" "$vl_conf"
	case $? in
		0)
			f_log "$1 : generated from the list"
			$4 "$2" && f_list_commit "$1"
			;;
		2)
			f_log "$i_remove : $1 (list is empty)"
			mv -f "$vl_conf" "$vg_dir_swanctl/conf.d/$1-$vg_date.dis"
			if [[ -n $5 ]]; then
				mv -f "$vg_dir_swanctl/conf.d/$5.conf" "$vg_dir_swanctl/conf.d/$5-$vg_date.dis" 2>/dev/null
			fi
			f_list_commit "$1"
			;;
	esac
}

# synchronise a random users secrets file with its count : existing entries are kept, entries are
# removed from the end when the count decreases and appended when it increases
# $1 name (conf.d/<name>.conf), $2 count, $3 entry name prefix, $4 function printing the entry number $1
function f_sync_random_users(){

	local vl_conf=$vg_dir_swanctl/conf.d/$1.conf vl_count=${2:-0} vl_current=0 i

	if [[ ! $vl_count =~ ^[0-9]+$ ]]; then
		f_log "ERROR : invalid number of random users for $1 : $vl_count"
		exit 1
	fi

	if [[ $vl_count -eq 0 ]]; then
		if [[ -f $vl_conf ]]; then
			f_log "$i_remove : $1 (count is empty)"
			mv -f "$vl_conf" "$vg_dir_swanctl/conf.d/$1-$vg_date.dis"
		fi
		return
	fi

	if [[ -f $vl_conf ]]; then
		vl_current=$(grep -c "^  $3[0-9][0-9]* " "$vl_conf")
	fi
	if [[ $vl_current -eq $vl_count ]]; then
		return
	fi
	f_log "$1 : $vl_current -> $vl_count"

	{
		echo "secrets {"
		if [[ -f $vl_conf ]]; then
			awk -v p="  $3" -v n="$vl_count" 'index($0, p) == 1 { keep = (substr($0, length(p) + 1) + 0 <= n) } keep { print } /^  }/ { keep = 0 }' "$vl_conf"
		fi
		i=$((vl_current + 1))
		while [[ $i -le $vl_count ]]; do
			$4 "$i"
			i=$((i + 1))
		done
		echo "}"
	} > "$vl_conf.tmp"
	mv -f "$vl_conf.tmp" "$vl_conf"
}

# get and create EAP username and password from Y_EAP_USERS
function f_eap_users(){

	local vl_users=$1 vl_iteration=1 vl_user vl_id vl_secret

	echo "secrets {"  > $vg_dir_swanctl/conf.d/eap_users.conf

	for vl_user in $vl_users; do
		vl_iteration=$((vl_iteration+1))
		vl_id=
		vl_secret=
		if [[ $vl_user == "$vg_users_separator"* ]]; then
			vl_id=$(f_credential vl_id username no)
		else
			vl_id=$(echo "$vl_user" | sed "s/$vg_users_separator.*//")
		fi

		if [[ $vl_user == *"$vg_users_separator" ]] || [[ ! $vl_user =~ "$vg_users_separator" ]]; then
			vl_secret=$(f_credential vl_secret password no)
		else
			vl_secret=$(echo "$vl_user" | sed "s/[^$vg_users_separator]*$vg_users_separator//")
		fi

		echo -e "  eap-eap$vl_iteration { \n    id = $vl_id \n    secret = $vl_secret \n  }" >> $vg_dir_swanctl/conf.d/eap_users.conf
	done

	echo "}" >> $vg_dir_swanctl/conf.d/eap_users.conf
}

# print the random EAP user number $1
function f_eap_user_random(){

	local vl_id='' vl_secret=''

	vl_id=$(f_credential vl_id username no)
	vl_secret=$(f_credential vl_secret password no)

	echo -e "  eap-eaprandom$1 { \n    id = $vl_id \n    secret = $vl_secret \n  }"
}

# get and create PSK and ids from Y_PSK_USERS
function f_psk_users(){

	local vl_users=$1 vl_iteration=1 vl_user vl_user_id vl_secret vl_id0 vl_id1

	echo "secrets {"  > $vg_dir_swanctl/conf.d/psk_users.conf

	for vl_user in $vl_users; do
		vl_iteration=$((vl_iteration+1))
		vl_secret=
		vl_id0=
		vl_id1=

		if [[ $vl_user == "$vg_users_separator"* ]]; then
			vl_secret=$(f_credential vl_secret password no)
		else
			vl_secret=$(echo "$vl_user" | sed "s/$vg_users_separator.*//")
		fi

		vl_user_id=$(echo "$vl_user" | sed "s/[^$vg_users_separator]*$vg_users_separator//")
		if [[ $vl_user_id == "$vg_users_separator"* ]] || [[ -z $vl_user_id ]] || [[ ! $vl_user =~ "$vg_users_separator" ]]; then
			vl_id0=$(f_credential vl_id0 username no)
		else
			vl_id0=$(echo "$vl_user_id" | sed "s/$vg_users_separator.*//")
		fi
		if [[ $vl_user_id == *"$vg_users_separator" ]] || [[ ! $vl_user_id =~ "$vg_users_separator" ]]; then
			vl_id1=$(f_credential vl_id1 username no)
		else
			vl_id1=$(echo "$vl_user_id" | sed "s/[^$vg_users_separator]*$vg_users_separator//")
		fi

		echo -e "  ike-psk$vl_iteration { \n    secret = $vl_secret \n    id-0 = $vl_id0 \n    id-1 = $vl_id1 \n  }" >> $vg_dir_swanctl/conf.d/psk_users.conf
	done

	echo "}" >> $vg_dir_swanctl/conf.d/psk_users.conf
}

# print the random psk user number $1
function f_psk_user_random(){

	local vl_id0='' vl_id1='' vl_secret=''

	vl_id0=$(f_credential vl_id0 username no)
	vl_id1=$(f_credential vl_id1 username no)
	vl_secret=$(f_credential vl_secret password no)

	echo -e "  ike-pskrandom$1 { \n    secret = $vl_secret \n    id-0 = $vl_id0 \n    id-1 = $vl_id1 \n  }"
}

# print "<id> <password>" for each client certificate recorded in the file $1
function f_cert_users_list(){
	if [[ -f $1 ]]; then
		sed -n 's|^# cat "/etc/swanctl/pkcs12/clientCert_\(.*\)\.pem\.p12" password: \(.*\) $|\1 \2|p' "$1"
	fi
}

# record a client certificate in the file $3
function f_cert_users_record(){
	echo -e "# cat \"/etc/swanctl/pkcs12/clientCert_${1}.pem.p12\" password: $2 \n" >> "$3"
}

# synchronise the client certificates with Y_CERT_USERS : issue the new ids, keep the existing
# certificates and revoke the ids removed from the list
function f_sync_cert_users(){

	local vl_txt=$vg_dir_swanctl/conf.d/cert_users.txt vl_state vl_user vl_id vl_secret vl_given vl_revoke=()
	local -A vl_old=() vl_new=()

	# certificates are kept by id across rebuilds, so only the entries with a generated id are lossy
	f_list_state cert_users "$1" "^[^${vg_users_separator}]" "$vl_txt"
	vl_state=$?
	if [[ $vl_state -eq 1 ]]; then
		return
	fi

	while read -r vl_id vl_secret; do
		vl_old[$vl_id]=$vl_secret
	done < <(f_cert_users_list "$vl_txt")

	: > "$vl_txt.tmp"
	if [[ $vl_state -eq 0 ]]; then
		f_log "cert_users : generated from the list"
		for vl_user in $1; do
			vl_id=
			vl_secret=
			vl_given=yes
			if [[ $vl_user == "$vg_users_separator"* ]]; then
				vl_id=$(f_credential vl_id username no)
			else
				vl_id=$(echo "$vl_user" | sed "s/$vg_users_separator.*//")
			fi

			if [[ $vl_user == *"$vg_users_separator" ]] || [[ ! $vl_user =~ "$vg_users_separator" ]]; then
				vl_given=no
				vl_secret=$(f_credential vl_secret password no)
			else
				vl_secret=$(echo "$vl_user" | sed "s/[^$vg_users_separator]*$vg_users_separator//")
			fi

			# duplicated id
			if [[ -n ${vl_new[$vl_id]+x} ]]; then
				continue
			fi

			if [[ -n ${vl_old[$vl_id]+x} ]] && [[ -s $vg_dir_swanctl/x509/clientCert_${vl_id}.pem ]]; then
				# keep the issued certificate, update the pkcs12 password if a new one is given
				if [[ $vl_given == "no" ]]; then
					vl_secret=${vl_old[$vl_id]}
				elif [[ $vl_secret != "${vl_old[$vl_id]}" ]]; then
					f_export_p12 "$vl_secret" "_$vl_id"
				fi
			else
				f_certificate "$vl_id" "$vl_secret" "_$vl_id"
			fi

			vl_new[$vl_id]=$vl_secret
			f_cert_users_record "$vl_id" "$vl_secret" "$vl_txt.tmp"
		done
	fi

	for vl_id in "${!vl_old[@]}"; do
		if [[ -z ${vl_new[$vl_id]+x} ]]; then
			vl_revoke+=("_$vl_id")
		fi
	done
	f_revoke_certificates "${vl_revoke[@]}"

	if [[ $vl_state -eq 2 ]]; then
		rm -f "$vl_txt.tmp"
		mv -f "$vl_txt" "$vg_dir_swanctl/conf.d/cert_users-$vg_date.dis"
	else
		mv -f "$vl_txt.tmp" "$vl_txt"
	fi
	f_list_commit cert_users
}

# synchronise the random client certificates with Y_CERT_USERS_RANDOM : existing certificates are kept,
# certificates are revoked from the end when the count decreases and issued when it increases
function f_sync_cert_users_random(){

	local vl_txt=$vg_dir_swanctl/conf.d/cert_users_random.txt vl_count=${1:-0} vl_current=0 vl_id vl_secret vl_revoke=() i

	if [[ ! $vl_count =~ ^[0-9]+$ ]]; then
		f_log "ERROR : invalid number of random certificate users : $vl_count"
		exit 1
	fi
	if [[ ! -f $vl_txt ]] && [[ $vl_count -eq 0 ]]; then
		return
	fi

	: > "$vl_txt.tmp"
	while read -r vl_id vl_secret; do
		vl_current=$((vl_current + 1))
		if [[ $vl_current -le $vl_count ]]; then
			f_cert_users_record "$vl_id" "$vl_secret" "$vl_txt.tmp"
		else
			vl_revoke+=("_$vl_id")
		fi
	done < <(f_cert_users_list "$vl_txt")

	i=$((vl_current + 1))
	while [[ $i -le $vl_count ]]; do
		vl_id=
		vl_secret=
		vl_id=$(f_credential vl_id username no)
		vl_secret=$(f_credential vl_secret password no)
		f_certificate "$vl_id" "$vl_secret" "_$vl_id"
		f_cert_users_record "$vl_id" "$vl_secret" "$vl_txt.tmp"
		i=$((i + 1))
	done

	f_revoke_certificates "${vl_revoke[@]}"

	if [[ $vl_count -eq 0 ]]; then
		rm -f "$vl_txt.tmp"
		mv -f "$vl_txt" "$vg_dir_swanctl/conf.d/cert_users_random-$vg_date.dis"
	else
		mv -f "$vl_txt.tmp" "$vl_txt"
	fi
}

# get and create PSK and ids from Y_S2S_PSK_USERS
function f_s2s_psk_users(){

	local vl_users=$1 vl_iteration=1 vl_user vl_secret vl_local_id vl_remote_id vl_local_ts vl_remote_ts vl_remote_addr

	echo "connections {"  > $vg_dir_swanctl/conf.d/s2s_psk_users.conf
	echo "secrets {" > $vg_dir_swanctl/conf.d/s2s_psk_secrets.conf

	for vl_user in $vl_users; do
		vl_iteration=$((vl_iteration+1))

		# format: secret:local_id:remote_id:local_ts:remote_ts:remote_addr
		vl_secret=$(echo "$vl_user" | cut -d: -f1)
		vl_local_id=$(echo "$vl_user" | cut -d: -f2)
		vl_remote_id=$(echo "$vl_user" | cut -d: -f3)
		vl_local_ts=$(echo "$vl_user" | cut -d: -f4)
		vl_remote_ts=$(echo "$vl_user" | cut -d: -f5)
		vl_remote_addr=$(echo "$vl_user" | cut -d: -f6)

		echo -e "  conn-s2s_psk_$vl_iteration : template-conn { \n    local_addrs = %any \n    remote_addrs = $vl_remote_addr \n    local : template-local { \n      auth = psk \n      id = $vl_local_id \n    } \n    remote { \n      auth = psk \n      id = $vl_remote_id \n    } \n    children { \n      child-s2s_psk_$vl_iteration : template-child { \n        local_ts = $vl_local_ts \n        remote_ts = $vl_remote_ts \n        start_action = trap \n      } \n    } \n  }" >> $vg_dir_swanctl/conf.d/s2s_psk_users.conf
		echo -e "  ike-s2s_psk_$vl_iteration { \n    secret = $vl_secret \n    id-0 = $vl_local_id \n    id-1 = $vl_remote_id \n  }" >> $vg_dir_swanctl/conf.d/s2s_psk_secrets.conf

		# Add to firewall subnets if NAT enabled
		if [[ $Y_FIREWALL_S2S_NAT == "yes" ]]; then
			Y_S2S_PSK_REMOTE_TS="$Y_S2S_PSK_REMOTE_TS,$vl_remote_ts"
		fi
	done

	echo "}" >> $vg_dir_swanctl/conf.d/s2s_psk_users.conf
	echo "}" >> $vg_dir_swanctl/conf.d/s2s_psk_secrets.conf
}

function f_certificate_cn() {
    openssl x509 -in "$1" -noout -subject -nameopt RFC2253 | sed -n 's/.*CN=\([^,]*\).*/\1/p'
}

# create firewall rules
if [[ -f $vg_file_firewall ]] ; then
	source $vg_file_firewall
fi

# to do before container exit
function f_pre_exit(){
	f_log "$i_exiting_in_progress"
	if [[ $Y_IGNORE_CONFIG == "no" ]] && [[ $Y_FIREWALL_ENABLE == "yes" ]]; then
		f_log "$i_remove : $i_ipv4_firewall_rules"
		f_firewall_delete_all iptables &> /dev/null
		f_log "$i_remove : $i_ipv6_firewall_rules"
		f_firewall_delete_all ip6tables &> /dev/null
	fi
 	kill -TERM "$child" 2>/dev/null
}

# ============ [ timestamp ] ============

echo "$vg_date"

# ============ [ internationalisation ] ============

# load default language
source /i18n/$vg_default_language.sh

# override with choosen language
if [[ $Y_LANGUAGE != $vg_default_language ]] && [[ -f /i18n/$Y_LANGUAGE.sh ]] ; then
	source /i18n/"$Y_LANGUAGE".sh
fi

f_log "i18n : $Y_LANGUAGE"

# ============ [ unnecessary config ] ============

if [[ $Y_IGNORE_CONFIG == "no" ]]; then

	f_log "$i_apply_configuration"

	# security warnings
	if [[ $Y_URL_IP_CHECK == "http://"* ]]; then
		f_log "WARNING : Y_URL_IP_CHECK uses plain http, the public ip (server certificate CN) can be spoofed. Use https or set Y_SERVER_CERT_CN"
	fi
	if [[ $Y_SHOW_CRED == "yes" ]]; then
		f_log "WARNING : Y_SHOW_CRED=yes, VPN secrets are written to the container logs. Set Y_SHOW_CRED=no once the clients are configured"
	fi
	if [[ $Y_PSK_ENABLE == "yes" ]]; then
		f_log "WARNING : Y_PSK_ENABLE=yes, any holder of the group PSK can impersonate the gateway to other PSK users. Prefer certificates or EAP, or set Y_PSK_ENABLE=no"
	fi
	if [[ $Y_EAP_ENABLE == "yes" ]] && [[ $Y_EAP_REMOTE_AUTH == *"mschapv2"* ]]; then
		f_log "WARNING : Y_EAP_REMOTE_AUTH=$Y_EAP_REMOTE_AUTH, clients must validate the server certificate (mschapv2 is crackable offline by a rogue server). Consider Y_EAP_REMOTE_AUTH=eap-tls"
	fi
	if [[ $Y_XAUTH_PSK_ENABLE == "yes" ]] && [[ $Y_XAUTH_PSK_AGGRESSIVE == "yes" ]]; then
		f_log "WARNING : Y_XAUTH_PSK_AGGRESSIVE=yes, IKEv1 aggressive mode exposes a hash of the PSK to offline cracking"
	fi

	# filelog symlink
	ln -sfn "$Y_FILELOG_PATH" /var/log/charon.log > /dev/null 2>&1

	# update ca certificates
	update-ca-certificates > /dev/null 2>&1
	
	# add some ca certificates to x509ca folder
	ln -sfn /etc/ssl/certs/ca-cert-ISRG_Root_X1.pem /etc/swanctl/x509ca/ca-cert-ISRG_Root_X1.pem > /dev/null 2>&1
	ln -sfn /etc/ssl/certs/ca-cert-ISRG_Root_X2.pem /etc/swanctl/x509ca/ca-cert-ISRG_Root_X2.pem > /dev/null 2>&1
	
	# generate strongswan.conf and symbolic link to /etc/strongswan.conf
	
	# only needed by IKEv1 PSK in aggressive mode
	if [[ $Y_XAUTH_PSK_ENABLE == "yes" ]] && [[ $Y_XAUTH_PSK_AGGRESSIVE == "yes" ]] ; then
		vg_aggressive=yes
	else 
		vg_aggressive=no
	fi
	
	source $vg_dir_swanctl/ye3ipsec-wan/strongswan.sh > $vg_dir_swanctl/ye3ipsec-wan/strongswan.conf
	ln -sfn $vg_dir_swanctl/ye3ipsec-wan/strongswan.conf /etc/strongswan.conf
	
	# credentials 
	
	# cert
	Y_CERT_CN=$(f_credential Y_CERT_CN username)
	Y_CERT_PASSWORD=$(f_credential Y_CERT_PASSWORD password)
	# eap
	Y_EAP_USERNAME=$(f_credential Y_EAP_USERNAME username)
	Y_EAP_PASSWORD=$(f_credential Y_EAP_PASSWORD password)
	# psk
	Y_PSK_LOCAL_ID=$(f_credential Y_PSK_LOCAL_ID username)
	Y_PSK_REMOTE_ID=$(f_credential Y_PSK_REMOTE_ID username)
	Y_PSK_SECRET=$(f_credential Y_PSK_SECRET password)
	# xauth psk
	Y_XAUTH_PSK_LOCAL_ID=$(f_credential Y_XAUTH_PSK_LOCAL_ID username)
	Y_XAUTH_PSK_REMOTE_ID=$(f_credential Y_XAUTH_PSK_REMOTE_ID username)
	Y_XAUTH_PSK_SECRET=$(f_credential Y_XAUTH_PSK_SECRET password)
	Y_XAUTH_PSK_USERNAME=$(f_credential Y_XAUTH_PSK_USERNAME username)
	Y_XAUTH_PSK_PASSWORD=$(f_credential Y_XAUTH_PSK_PASSWORD password)
	# xauth rsa
	Y_XAUTH_RSA_USERNAME=$(f_credential Y_XAUTH_RSA_USERNAME username)
	Y_XAUTH_RSA_PASSWORD=$(f_credential Y_XAUTH_RSA_PASSWORD password)
	# s2s psk
	Y_S2S_PSK_LOCAL_ID=$(f_credential Y_S2S_PSK_LOCAL_ID username)
	Y_S2S_PSK_REMOTE_ID=$(f_credential Y_S2S_PSK_REMOTE_ID username)
	Y_S2S_PSK_SECRET=$(f_credential Y_S2S_PSK_SECRET password)

	# never start with an empty credential
	for vl_var in Y_CERT_CN Y_CERT_PASSWORD Y_EAP_USERNAME Y_EAP_PASSWORD Y_PSK_LOCAL_ID Y_PSK_REMOTE_ID Y_PSK_SECRET Y_XAUTH_PSK_LOCAL_ID Y_XAUTH_PSK_REMOTE_ID Y_XAUTH_PSK_SECRET Y_XAUTH_PSK_USERNAME Y_XAUTH_PSK_PASSWORD Y_XAUTH_RSA_USERNAME Y_XAUTH_RSA_PASSWORD Y_S2S_PSK_LOCAL_ID Y_S2S_PSK_REMOTE_ID Y_S2S_PSK_SECRET; do
		if [[ -z ${!vl_var} ]]; then
			f_log "ERROR : $vl_var is empty, refusing to start"
			exit 1
		fi
	done

	# if env variable Y_SERVER_CERT_CN doesn't exist, then set to certificate cn, or external ip or default route interface ip or first hostname ip
	
	if [[ -z "$Y_SERVER_CERT_CN" ]]; then

		if [ "$Y_LOCAL_SELFCERT" == "no" ] && [ -f "$vg_file_external_key" ] && [ -f "$vg_file_external_cert" ]; then
			Y_SERVER_CERT_CN="$(f_certificate_cn "$vg_file_external_cert")"
 		elif [[ -f "$vg_file_server_cert" ]] ; then
 			Y_SERVER_CERT_CN="$(f_certificate_cn "$vg_file_server_cert")"
		elif expr "$vg_ip" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null; then
			Y_SERVER_CERT_CN="$vg_ip"
		elif [[ ! -z "$vg_interface_ip" ]]; then
			Y_SERVER_CERT_CN="$vg_interface_ip"
		else
			Y_SERVER_CERT_CN="$(hostname -i | cut -d ' ' -f1)"
		fi
	fi
 
	f_log "Y_SERVER_CERT_CN = $Y_SERVER_CERT_CN"

	# Format DN for pki (comma separated) and ensure it is handled correctly
	vg_dn_pki=$(echo "${Y_SERVER_CERT_DN:-}" | tr '/' ',' | sed 's/,,*/,/g; s/^,//; s/,$//')
	if [[ -n "$vg_dn_pki" ]]; then
		vg_dn_pki="$vg_dn_pki, CN=$Y_SERVER_CERT_CN"
	else
		vg_dn_pki="CN=$Y_SERVER_CERT_CN"
	fi

	# For documentation/future-proofing, also create a slash-separated version (openssl -subj style)
	vg_dn_openssl=$(echo "/$vg_dn_pki" | sed 's/, */\//g; s/\/\//\//g')
	
	# create ca certificate

	if [ ! -f "$vg_file_ca_key" ] || [ ! -f "$vg_file_ca_cert" ] ; then
	
		f_log "$i_create_ca_certificate"
		
		pki --gen --outform pem > "$vg_file_ca_key"
		pki --self --lifetime "$Y_SERVER_CERT_DAYS" --in "$vg_file_ca_key" --dn "$vg_dn_pki" --ca --outform pem > "$vg_file_ca_cert"
	fi
	
	f_log 'caCert : cat /etc/swanctl/x509ca/caCert.pem'

 	# create server certificate
   
	if [ ! -f "$vg_file_server_key" ] || [ ! -f "$vg_file_server_cert" ] ; then
	
		f_log "$i_create_server_certificate"
		
		pki --gen --outform pem > "$vg_file_server_key"
		pki --issue --outform pem --type priv --lifetime "$Y_SERVER_CERT_DAYS" --in "$vg_file_server_key" --cacert "$vg_file_ca_cert" --cakey "$vg_file_ca_key" --dn "$vg_dn_pki" --san "$Y_SERVER_CERT_CN" --flag clientAuth --flag serverAuth --flag ikeIntermediate > "$vg_file_server_cert"

 	fi
	
	# create client certificate
   
	if [ ! -f "$vg_file_client_cert" ] || [ ! -f "$vg_file_client_key" ] ; then
	
		f_log "$i_create_client_certificate"
		
		f_certificate "$Y_CERT_CN" "$Y_CERT_PASSWORD" "default"

	fi

	# activate firewall and generate template
	
	if [ "$Y_CERT_ENABLE" == "yes" ] || [ "$Y_EAP_ENABLE" == "yes" ] || [ "$Y_PSK_ENABLE" == "yes" ] || [ "$Y_XAUTH_PSK_ENABLE" == "yes" ] || [ "$Y_XAUTH_RSA_ENABLE" == "yes" ] || [ "$Y_S2S_PSK_ENABLE" == "yes" ] || [ "$Y_S2S_RSA_ENABLE" == "yes" ] ; then

		if [[ $Y_FIREWALL_ENABLE == "yes" ]]; then
			f_log "$i_enable : $i_firewall"
			f_firewall_delete_all iptables &> /dev/null
    			f_firewall_delete_all ip6tables &> /dev/null
			
			# Use nftables if available
			if command -v nft >/dev/null 2>&1; then
				f_log "Using nftables"
				f_firewall_nft "$Y_POOL_IPV4" "$vg_interface"
			fi

			f_firewall iptables "$Y_POOL_IPV4" "$vg_interface"
			f_firewall ip6tables "$Y_POOL_IPV6" "$vg_interface"
		fi
		
		if [[ -z "$Y_LOCAL_ID" ]]; then
			Y_LOCAL_ID="$Y_SERVER_CERT_CN"
		fi
		f_log "Y_LOCAL_ID = $Y_LOCAL_ID"
		
		if [ "$Y_LOCAL_SELFCERT" == "no" ] && [ -f "$vg_file_external_key" ] && [ -f "$vg_file_external_cert" ]; then
			f_log "$i_use : cert.pem"
			vg_local_cert=cert.pem
		else
			f_log "$i_use : $i_self_cert"
			vg_local_cert=serverCert.pem
		fi
		
		if [[ $Y_POOL_DHCP == "yes" ]]; then
			f_log "$i_use : $i_dhcp_pool"
			vg_pool=dhcp
		else
			f_log "$i_use : $i_internal_pool"
			if [[ $Y_POOL_IPV6_ENABLE == "yes" ]]; then
				f_log "$i_with_ipv6"
				vg_pool=pool-ipv4-1,pool-ipv6-1
			else
				vg_pool=pool-ipv4-1
			fi
		fi
		
		source $vg_dir_swanctl/ye3ipsec-wan/template.sh > $vg_dir_swanctl/conf.d/template.conf
		
	else
		rm $vg_dir_swanctl/conf.d/template.conf 2>/dev/null
	fi
	
	# generate connections conf files
	
	if [[ $Y_CERT_ENABLE == "yes" ]]; then
		f_log "$i_enable : $i_certificate"
		source $vg_dir_swanctl/ye3ipsec-wan/cert.sh > $vg_dir_swanctl/conf.d/cert.conf
		f_sync_cert_users "$Y_CERT_USERS"
		f_sync_cert_users_random "$Y_CERT_USERS_RANDOM"
  		if [[ $Y_SHOW_CRED == "yes" ]]; then
			f_show_cred Y_SERVER_CERT_CN
			f_show_cred Y_CERT_CN
			f_show_cred Y_CERT_PASSWORD
			f_log '    CRED_Y_CERT_ : cat "/etc/swanctl/pkcs12/clientCert.pem.p12"'
			if [[ -f $vg_dir_swanctl/conf.d/cert_users.txt ]]; then
				f_log "    CRED_Y_CERT_USERS : $(cat $vg_dir_swanctl/conf.d/cert_users.txt | grep '# cat ' | tr '\n' ' ' | tr -s ' ')"
			fi
			if [[ -f $vg_dir_swanctl/conf.d/cert_users_random.txt ]]; then
				f_log "    CRED_Y_CERT_USERS_RANDOM : $(cat $vg_dir_swanctl/conf.d/cert_users_random.txt | grep '# cat ' | tr '\n' ' ' | tr -s ' ')"
			fi
   		fi
	else
		mv -f $vg_dir_swanctl/conf.d/cert.conf $vg_dir_swanctl/conf.d/cert-"$vg_date".dis 2>/dev/null
		mv -f $vg_dir_swanctl/conf.d/cert_users.txt $vg_dir_swanctl/conf.d/cert_users-"$vg_date".dis 2>/dev/null
		mv -f $vg_dir_swanctl/conf.d/cert_users_random.txt $vg_dir_swanctl/conf.d/cert_users_random-"$vg_date".dis 2>/dev/null
	fi

	if [[ $Y_EAP_ENABLE == "yes" ]]; then
		f_log "$i_enable : $i_eap"
		source $vg_dir_swanctl/ye3ipsec-wan/eap.sh > $vg_dir_swanctl/conf.d/eap.conf
		f_sync_users eap_users "$Y_EAP_USERS" "^[^${vg_users_separator}]+${vg_users_separator}.+" f_eap_users
		f_sync_random_users eap_users_random "$Y_EAP_USERS_RANDOM" eap-eaprandom f_eap_user_random
  		if [[ $Y_SHOW_CRED == "yes" ]]; then
			f_show_cred Y_EAP_USERNAME
			f_show_cred Y_EAP_PASSWORD
			if [[ -f $vg_dir_swanctl/conf.d/eap_users.conf ]]; then
				f_log "    CRED_Y_EAP_USERS : $(cat $vg_dir_swanctl/conf.d/eap_users.conf | tr '\n' ' ' | tr -s ' ')"
			fi
			if [[ -f $vg_dir_swanctl/conf.d/eap_users_random.conf ]]; then
				f_log "    CRED_Y_EAP_USERS_RANDOM : $(cat $vg_dir_swanctl/conf.d/eap_users_random.conf | tr '\n' ' ' | tr -s ' ')"
			fi
   		fi
	else
		mv -f $vg_dir_swanctl/conf.d/eap.conf $vg_dir_swanctl/conf.d/eap-"$vg_date".dis 2>/dev/null
		mv -f $vg_dir_swanctl/conf.d/eap_users.conf $vg_dir_swanctl/conf.d/eap_users-"$vg_date".dis 2>/dev/null
		mv -f $vg_dir_swanctl/conf.d/eap_users_random.conf $vg_dir_swanctl/conf.d/eap_users_random-"$vg_date".dis 2>/dev/null
	fi

	if [[ $Y_PSK_ENABLE == "yes" ]]; then
		f_log "$i_enable : $i_psk"
		source $vg_dir_swanctl/ye3ipsec-wan/psk.sh > $vg_dir_swanctl/conf.d/psk.conf
		f_sync_users psk_users "$Y_PSK_USERS" "^[^${vg_users_separator}]+${vg_users_separator}[^${vg_users_separator}]+${vg_users_separator}.+" f_psk_users
		f_sync_random_users psk_users_random "$Y_PSK_USERS_RANDOM" ike-pskrandom f_psk_user_random
  		if [[ $Y_SHOW_CRED == "yes" ]]; then
			f_show_cred Y_PSK_SECRET
			f_show_cred Y_PSK_LOCAL_ID
			f_show_cred Y_PSK_REMOTE_ID
			if [[ -f $vg_dir_swanctl/conf.d/psk_users.conf ]]; then
				f_log "    CRED_Y_PSK_USERS : $(cat $vg_dir_swanctl/conf.d/psk_users.conf | tr '\n' ' ' | tr -s ' ')"
			fi
			if [[ -f $vg_dir_swanctl/conf.d/psk_users_random.conf ]]; then
				f_log "    CRED_Y_PSK_USERS_RANDOM : $(cat $vg_dir_swanctl/conf.d/psk_users_random.conf | tr '\n' ' ' | tr -s ' ')"
			fi
   		fi
	else
		mv -f $vg_dir_swanctl/conf.d/psk.conf $vg_dir_swanctl/conf.d/psk-"$vg_date".dis 2>/dev/null
		mv -f $vg_dir_swanctl/conf.d/psk_users.conf $vg_dir_swanctl/conf.d/psk_users-"$vg_date".dis 2>/dev/null
		mv -f $vg_dir_swanctl/conf.d/psk_users_random.conf $vg_dir_swanctl/conf.d/psk_users_random-"$vg_date".dis 2>/dev/null
	fi
	
	if [[ $Y_XAUTH_PSK_ENABLE == "yes" ]]; then
		f_log "$i_enable : xauth psk"
		source $vg_dir_swanctl/ye3ipsec-wan/xauth_psk.sh > $vg_dir_swanctl/conf.d/xauth_psk.conf
  		if [[ $Y_SHOW_CRED == "yes" ]]; then
			f_show_cred Y_XAUTH_PSK_LOCAL_ID
			f_show_cred Y_XAUTH_PSK_REMOTE_ID
			f_show_cred Y_XAUTH_PSK_SECRET
			f_show_cred Y_XAUTH_PSK_USERNAME
			f_show_cred Y_XAUTH_PSK_PASSWORD
   		fi
	else
		mv -f $vg_dir_swanctl/conf.d/xauth_psk.conf $vg_dir_swanctl/conf.d/xauth_psk-"$vg_date".dis 2>/dev/null
	fi
	
	if [[ $Y_XAUTH_RSA_ENABLE == "yes" ]]; then
		f_log "$i_enable : xauth rsa"
		source $vg_dir_swanctl/ye3ipsec-wan/xauth_rsa.sh > $vg_dir_swanctl/conf.d/xauth_rsa.conf
	  	if [[ $Y_SHOW_CRED == "yes" ]]; then
			f_show_cred Y_SERVER_CERT_CN
			f_show_cred Y_CERT_CN
			f_show_cred Y_CERT_PASSWORD
			f_show_cred Y_XAUTH_RSA_USERNAME
			f_show_cred Y_XAUTH_RSA_PASSWORD
   		fi
	else
		mv -f $vg_dir_swanctl/conf.d/xauth_rsa.conf $vg_dir_swanctl/conf.d/xauth_rsa-"$vg_date".dis 2>/dev/null
	fi
	
	if [[ $Y_S2S_PSK_ENABLE == "yes" ]]; then
		f_log "$i_enable : s2s psk"
		source $vg_dir_swanctl/ye3ipsec-wan/s2s_psk.sh > $vg_dir_swanctl/conf.d/s2s_psk.conf
		f_sync_users s2s_psk_users "$Y_S2S_PSK_USERS" "." f_s2s_psk_users s2s_psk_secrets
  		if [[ $Y_SHOW_CRED == "yes" ]]; then
			f_show_cred Y_S2S_PSK_LOCAL_ID
			f_show_cred Y_S2S_PSK_REMOTE_ID
			f_show_cred Y_S2S_PSK_SECRET
			if [[ -f $vg_dir_swanctl/conf.d/s2s_psk_users.conf ]]; then
				f_log "    CRED_Y_S2S_PSK_USERS : $(cat $vg_dir_swanctl/conf.d/s2s_psk_users.conf | tr '\n' ' ' | tr -s ' ')"
			fi
		fi
	else
		mv -f $vg_dir_swanctl/conf.d/s2s_psk.conf $vg_dir_swanctl/conf.d/s2s_psk-"$vg_date".dis 2>/dev/null
		mv -f $vg_dir_swanctl/conf.d/s2s_psk_users.conf $vg_dir_swanctl/conf.d/s2s_psk_users-"$vg_date".dis 2>/dev/null
		mv -f $vg_dir_swanctl/conf.d/s2s_psk_secrets.conf $vg_dir_swanctl/conf.d/s2s_psk_secrets-"$vg_date".dis 2>/dev/null
	fi
	
	if [[ $Y_S2S_RSA_ENABLE == "yes" ]]; then
		f_log "$i_enable : s2s rsa"
		# if local certificate and id are not set, then use selfsigned
		if [[ -z $Y_S2S_RSA_LOCAL_CERTS ]] && [[ -z $Y_S2S_RSA_LOCAL_ID ]] ; then
			Y_S2S_RSA_LOCAL_CERTS=serverCert.pem
			Y_S2S_RSA_LOCAL_ID="$Y_SERVER_CERT_CN"
		fi
		source $vg_dir_swanctl/ye3ipsec-wan/s2s_rsa.sh > $vg_dir_swanctl/conf.d/s2s_rsa.conf
  		if [[ $Y_SHOW_CRED == "yes" ]]; then
			f_show_cred Y_S2S_RSA_LOCAL_ID
			f_show_cred Y_S2S_RSA_LOCAL_CERTS
			f_show_cred Y_S2S_RSA_REMOTE_ID
			f_show_cred Y_S2S_RSA_REMOTE_CERTS
   		fi
	else
		mv -f $vg_dir_swanctl/conf.d/s2s_rsa.conf $vg_dir_swanctl/conf.d/s2s_rsa-"$vg_date".dis 2>/dev/null
	fi

 	if [[ $Y_CLIENT_ENABLE == "yes" ]]; then
		f_log "$i_enable : client"
		source $vg_dir_swanctl/ye3ipsec-wan/client.sh > $vg_dir_swanctl/conf.d/client.conf
 		if [[ $Y_SHOW_CRED == "yes" ]]; then
			f_show_cred Y_CLIENT_REMOTE_ADDRESS
			f_show_cred Y_CLIENT_LOCAL_AUTH
			f_show_cred Y_CLIENT_LOCAL_ID
			f_show_cred Y_CLIENT_REMOTE_AUTH
			f_show_cred Y_CLIENT_REMOTE_ID
	    		f_show_cred Y_CLIENT_EAP_USERNAME
	    		f_show_cred Y_CLIENT_EAP_PASSWORD
	    		f_show_cred Y_CLIENT_PSK_SECRET
	    		f_show_cred Y_CLIENT_PSK_LOCAL_ID
	    		f_show_cred Y_CLIENT_PSK_REMOTE_ID
	    		f_show_cred Y_CLIENT_PKCS12_FILE
	    		f_show_cred Y_CLIENT_PKCS12_SECRET
      		fi
	else
		mv -f $vg_dir_swanctl/conf.d/client.conf $vg_dir_swanctl/conf.d/client-"$vg_date".dis 2>/dev/null
	fi

	if [[ $Y_SHOW_CRED != "yes" ]]; then
		f_log "credentials are not shown in logs (Y_SHOW_CRED=no), read them inside the container :"
		f_log "    generated credentials : ls $vg_dir_credential ; cat $vg_dir_credential/<NAME>"
		f_log "    connection secrets : cat $vg_dir_swanctl/conf.d/<profile>.conf"
		f_log "    client certificates : ls $vg_dir_swanctl/pkcs12 ; cat $vg_dir_swanctl/conf.d/cert_users*.txt"
	fi
	
else

	f_log "$i_ignore_configuration"
	
fi

# ============ [ start service ] ============

f_log "$i_start : charon"
rm /var/run/charon.vici 2>/dev/null
if [[ "$Y_DEBUG" == "yes" ]]; then
	f_log "$i_with_debug_option"
	/libexec/ipsec/charon &
 	child=$! 
else
	/libexec/ipsec/charon > /dev/null 2>&1 &
 	child=$! 
fi

f_log "$i_waiting_for_vici"
while [[ ! -e /var/run/charon.vici ]]; do sleep 1; done

f_log "$i_start : swanctl"
if [[ "$Y_DEBUG" == "yes" ]]; then
	f_log " $i_with_debug_option"
	/sbin/swanctl --load-all --noprompt
	vg_load_status=$?
	/sbin/swanctl --log &
else
	/sbin/swanctl --load-all --noprompt > /dev/null 2>&1
	vg_load_status=$?
fi
if [[ $vg_load_status -ne 0 ]]; then
	f_log "WARNING : swanctl --load-all failed (exit code $vg_load_status), part of the configuration was not loaded. Run : swanctl --load-all"
fi

f_log ":: $i_ready ::"

# catch SIGTERM
trap f_pre_exit SIGINT SIGQUIT SIGTERM

# keep the server running,
if [[ "$Y_DEBUG" == "yes" ]]; then
	# by using tail
	tail -f /dev/null
else
	# by waiting child process 
	wait "$child"
fi

# before final exit
f_pre_exit

f_log ":: $i_finished ::"
