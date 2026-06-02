#!/bin/bash
# shellcheck disable=SC2154,SC1091,SC2034,SC2148,SC2086,SC1083
cat <<EOL
connections {
	conn-cert : template-conn {
		
		local : template-local {
		}
		
		remote {
			auth = pubkey
			# uncomment these 2 following lines if you want to attach a specific certificate to this connection
			# certs = clientCert.pem
			# id = "$Y_CERT_REMOTE_ID"
		}
		
		children {
			child-cert : template-child {
			}
		}
	}
}
EOL
