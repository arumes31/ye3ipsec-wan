#!/bin/bash
# shellcheck disable=SC1091,SC2034,SC2148,SC1083,SC2001,SC2076,SC2005,SC1090,SC2053,SC2153,SC2046
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
