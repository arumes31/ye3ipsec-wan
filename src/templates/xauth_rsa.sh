#!/bin/bash
# shellcheck disable=SC2154,SC1091,SC2034,SC2148,SC2086,SC1083,SC2001,SC2076,SC2005,SC1090,SC2053,SC2153,SC2046
cat <<EOL
connections {
    conn-xauth_rsa : template-conn {
	
		aggressive = $Y_XAUTH_RSA_AGGRESSIVE
		version = 1

		local-rsa : template-local {
		}
		remote-rsa {
			auth = pubkey
			# uncomment these 2 following lines if you want to attach a specific certificate to this connection
			# certs = clientCert.pem
			# id = "$Y_CERT_REMOTE_ID"
		}
		remote-xauth {
			auth = $Y_XAUTH_RSA_REMOTE_AUTH
		}
		children {
			child-xauth_rsa : template-child {
			}
		}
	}
}

secrets {
	xauth-xauth_rsa1 {
		id = $Y_XAUTH_RSA_USERNAME
		secret = $Y_XAUTH_RSA_PASSWORD
	}
}
EOL
