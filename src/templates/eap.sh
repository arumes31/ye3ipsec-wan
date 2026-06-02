#!/bin/bash
# shellcheck disable=SC1091,SC2034,SC2148,SC1083,SC2001,SC2076,SC2005,SC1090,SC2053,SC2153,SC2046
cat <<EOL
connections {
	conn-eap : template-conn {
		
		local : template-local {
		}
		
		remote {
			auth = $Y_EAP_REMOTE_AUTH
			# uncomment this following lines if you want to attach a specific eap id to this connection
			# eap_id = $Y_EAP_REMOTE_EAP_ID
		}
		
		children {
			child-eap : template-child {
			}
		}
	}
}

secrets {
    eap-eap1 {
        id = $Y_EAP_USERNAME
        secret = $Y_EAP_PASSWORD
    }
}
EOL
