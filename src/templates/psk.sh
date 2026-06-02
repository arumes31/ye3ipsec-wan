#!/bin/bash
# shellcheck disable=SC2154,SC1091,SC2034,SC2148,SC2086,SC1083,SC2001,SC2076,SC2005,SC1090,SC2053,SC2153,SC2046
cat <<EOL
connections {
	conn-psk : template-conn {
		
		local : template-local {
			auth = psk
			# uncomment this following line if you want to attach a specific id to this connection
			# id = $Y_PSK_LOCAL_ID
		}
		
		remote {
			auth = psk
			# uncomment this following line if you want to attach a specific id to this connection
			# id = $Y_PSK_REMOTE_ID
		}
		
		children {
			child-psk : template-child {
			}
		}
	}
}

secrets {
	ike-psk1 {
		secret = $Y_PSK_SECRET
		id-0 = $Y_PSK_LOCAL_ID
		id-1 = $Y_PSK_REMOTE_ID
	}
}
EOL
