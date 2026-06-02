#!/bin/bash
# shellcheck disable=SC2154,SC1091,SC2034,SC2148,SC2086,SC1083,SC2001,SC2076,SC2005,SC1090,SC2053,SC2153,SC2046
cat <<EOL
connections {
    conn-s2s_rsa : template-conn {
	
		pools = 
		local_addrs  = $Y_S2S_RSA_LOCAL_ADDRS
		remote_addrs = $Y_S2S_RSA_REMOTE_ADDRS

		local : template-local {
			certs = $Y_S2S_RSA_LOCAL_CERTS
			id = $Y_S2S_RSA_LOCAL_ID
		}
		remote {
			auth = pubkey
			certs = $Y_S2S_RSA_REMOTE_CERTS
			id = $Y_S2S_RSA_REMOTE_ID
		}
		children {
			child-s2s_rsa : template-child {
				local_ts = $Y_S2S_RSA_LOCAL_TS
				remote_ts = $Y_S2S_RSA_REMOTE_TS
				start_action = $Y_S2S_RSA_START_ACTION
			}
		}
	}
}
EOL
