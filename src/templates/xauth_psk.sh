#!/bin/bash
# shellcheck disable=SC1091,SC2034,SC2148,SC1083,SC2001,SC2076,SC2005,SC1090,SC2053,SC2153,SC2046
cat <<EOL
connections {
    conn-xauth_psk : template-conn {
	
		aggressive = $Y_XAUTH_PSK_AGGRESSIVE
		version = 1

		local-psk : template-local {
			auth = psk
			id = $Y_XAUTH_PSK_LOCAL_ID
		}
		remote-psk {
			auth = psk
			# uncomment this following line if you want to attach a specific id to this connection
			# id = $Y_XAUTH_PSK_REMOTE_ID

		}
		remote-xauth {
			auth = $Y_XAUTH_PSK_REMOTE_AUTH
			# uncomment this following line if you want to attach a specific xauth id to this connection
			# xauth_id = $Y_XAUTH_PSK_USERNAME
		}
		children {
			child-xauth_psk : template-child {
			}
		}
	}
}

secrets {
	ike-xauth_psk1 {
		secret = $Y_XAUTH_PSK_SECRET
        id-0 = $Y_XAUTH_PSK_LOCAL_ID
        id-1 = $Y_XAUTH_PSK_REMOTE_ID
	}
	xauth-xauth_psk1 {
		id = $Y_XAUTH_PSK_USERNAME
		secret = $Y_XAUTH_PSK_PASSWORD
	}
}
EOL
