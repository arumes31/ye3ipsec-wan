# Modularized logic from entrypoint.sh

# Move credentials generation and cert handling here
# (Example structure)

function f_init_credentials() {
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
}

# (More functions could be moved here)
