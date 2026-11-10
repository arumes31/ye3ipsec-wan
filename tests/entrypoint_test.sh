#!/bin/bash
# shellcheck disable=SC2016,SC2034  # f_check evaluates its single-quoted assertions later
# Integration test of the entrypoint : user lists are reconciled with the environment on every start,
# removed client certificates are revoked, and scripts sourced from the volume must be owned by root.
#
# usage : tests/entrypoint_test.sh [image]   (requires docker, the image defaults to ye3ipsec-wan:test)

set -uo pipefail

vg_image=${1:-ye3ipsec-wan:test}
vg_volume=ye3ipsec-test-$$
vg_name=ye3ipsec-test-$$
vg_failed=0

function f_cleanup(){
	docker rm -f "$vg_name" > /dev/null 2>&1
	docker volume rm -f "$vg_volume" > /dev/null 2>&1
}
trap f_cleanup EXIT

function f_check(){
	if eval "$2"; then
		echo "ok   - $1"
	else
		echo "FAIL - $1"
		vg_failed=1
	fi
}

# run a shell command against the volume
function f_vol(){
	docker run --rm -v "$vg_volume:/etc/swanctl" --entrypoint sh "$vg_image" -c "$1"
}

# start the container with the given extra docker arguments and wait until it is ready
function f_start(){
	docker rm -f "$vg_name" > /dev/null 2>&1
	docker run -d --name "$vg_name" --cap-add NET_ADMIN -v "$vg_volume:/etc/swanctl" \
		-e Y_SERVER_CERT_CN=vpn.test -e Y_URL_IP_CHECK=https://127.0.0.1:1 -e Y_URL_IP_CHECK_TIMEOUT=1 \
		"$@" "$vg_image" > /dev/null
	for _ in $(seq 1 90); do
		if docker logs "$vg_name" 2>&1 | grep -q ':: ready ::'; then
			return 0
		fi
		if [[ $(docker inspect -f '{{.State.Running}}' "$vg_name") != "true" ]]; then
			break
		fi
		sleep 1
	done
	echo "container did not become ready :"
	docker logs "$vg_name" 2>&1 | tail -n 50
	return 1
}

function f_stop(){
	docker stop -t 5 "$vg_name" > /dev/null
}

function f_serial(){
	f_vol "openssl x509 -in /etc/swanctl/x509/clientCert_$1.pem -noout -serial | cut -d= -f2"
}

function f_revoked(){
	local vl_crl
	vl_crl=$(f_vol "openssl crl -in /etc/swanctl/x509crl/ye3ipsec-wan.crl -noout -text 2>/dev/null")
	[[ $vl_crl == *"Serial Number: $1"* ]]
}

echo "# first start"
f_start -e Y_EAP_USERS="alice:pw1 bob:pw2" -e Y_EAP_USERS_RANDOM=3 \
	-e Y_PSK_USERS="secret1:a1:b1 secret2:a2:b2" \
	-e Y_CERT_USERS="carol:pc dave:pd dave.x:pdx" -e Y_CERT_USERS_RANDOM=2 \
	-e Y_PSK_SECRET=firstsecret || exit 1
f_stop

f_check "eap user bob generated" 'f_vol "grep -q \"id = bob \" /etc/swanctl/conf.d/eap_users.conf"'
f_check "3 random eap users" '[[ $(f_vol "grep -c \"^  eap-eaprandom\" /etc/swanctl/conf.d/eap_users_random.conf") == 3 ]]'
f_check "psk user a2 generated" 'f_vol "grep -q \"id-0 = a2 \" /etc/swanctl/conf.d/psk_users.conf"'

vg_carol=$(f_serial carol)
vg_dave=$(f_serial dave)
vg_random_eap=$(f_vol "sed -n 's/^    id = \(.*\) \$/\1/p' /etc/swanctl/conf.d/eap_users_random.conf | head -n 1")
mapfile -t vg_random_certs < <(f_vol "sed -n 's|^# cat \"/etc/swanctl/pkcs12/clientCert_\(.*\)\.pem\.p12\".*|\1|p' /etc/swanctl/conf.d/cert_users_random.txt")
f_check "2 random certificate users" '[[ ${#vg_random_certs[@]} -eq 2 ]]'
vg_random_cert_kept=$(f_serial "${vg_random_certs[0]}")
vg_random_cert_removed=$(f_serial "${vg_random_certs[1]}")

echo "# second start, with shorter lists"
f_start -e Y_EAP_USERS="alice:pw1" -e Y_EAP_USERS_RANDOM=1 \
	-e Y_PSK_USERS="secret1:a1:b1" \
	-e Y_CERT_USERS="carol:pc dave.x:pdx" -e Y_CERT_USERS_RANDOM=1 || exit 1
vg_creds=$(docker exec "$vg_name" swanctl --load-creds --noprompt 2>&1)
f_check "CRL loaded by swanctl" '[[ $vg_creds == *"ye3ipsec-wan.crl"* ]]'
f_stop

f_check "removed eap user bob is gone" '! f_vol "grep -q \"id = bob \" /etc/swanctl/conf.d/eap_users.conf"'
f_check "kept eap user alice is present" 'f_vol "grep -q \"id = alice \" /etc/swanctl/conf.d/eap_users.conf"'
f_check "1 random eap user left, the first one" '[[ $(f_vol "grep -c \"^  eap-eaprandom\" /etc/swanctl/conf.d/eap_users_random.conf") == 1 ]] && f_vol "grep -q \"id = $vg_random_eap \" /etc/swanctl/conf.d/eap_users_random.conf"'
f_check "removed psk user a2 is gone" '! f_vol "grep -q \"id-0 = a2 \" /etc/swanctl/conf.d/psk_users.conf"'
f_check "kept certificate of carol is unchanged" '[[ $(f_serial carol) == "$vg_carol" ]]'
f_check "certificate of carol is not revoked" '! f_revoked "$vg_carol"'
f_check "certificate of dave is revoked" 'f_revoked "$vg_dave"'
f_check "certificate files of dave are deleted" '! f_vol "ls /etc/swanctl/x509/clientCert_dave.pem /etc/swanctl/pkcs12/clientCert_dave.p12" > /dev/null 2>&1'
f_check "pkcs12 files of dave.x are kept when dave is removed" 'f_vol "test -s /etc/swanctl/pkcs12/clientCert_dave.x.p12 && test -s /etc/swanctl/pkcs12/clientCert_dave.x.pem.p12"'
f_check "first random certificate is kept" '[[ $(f_serial "${vg_random_certs[0]}") == "$vg_random_cert_kept" ]] && ! f_revoked "$vg_random_cert_kept"'
f_check "second random certificate is revoked" 'f_revoked "$vg_random_cert_removed"'
f_check "env secret persisted, no fallback to an older value" '[[ $(f_vol "cat /etc/swanctl/ye3ipsec-wan/credential/Y_PSK_SECRET") == firstsecret ]]'

echo "# third start, with empty lists"
f_start || exit 1
f_stop

f_check "emptied eap list removes the users" '! f_vol "test -e /etc/swanctl/conf.d/eap_users.conf"'
f_check "emptied random eap count removes the users" '! f_vol "test -e /etc/swanctl/conf.d/eap_users_random.conf"'
f_check "emptied psk list removes the users" '! f_vol "test -e /etc/swanctl/conf.d/psk_users.conf"'
f_check "emptied certificate list revokes carol" 'f_revoked "$vg_carol"'
f_check "emptied random certificate count revokes the last one" 'f_revoked "$vg_random_cert_kept"'
f_check "dave stays revoked" 'f_revoked "$vg_dave"'

echo "# scripts on the volume not owned by root"
f_vol "chown 1000 /etc/swanctl/ye3ipsec-wan/firewall.sh"
vg_output=$(timeout 60 docker run --rm --cap-add NET_ADMIN -v "$vg_volume:/etc/swanctl" "$vg_image" 2>&1)
vg_status=$?
f_check "refuses to start" '[[ $vg_status -eq 1 ]] && [[ $vg_output == *"must be owned by root"* ]]'

if [[ $vg_failed -ne 0 ]]; then
	echo "some tests failed"
	exit 1
fi
echo "all tests passed"
