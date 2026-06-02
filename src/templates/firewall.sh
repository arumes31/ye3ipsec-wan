#!/bin/bash
# shellcheck disable=SC2154,SC1091,SC2034,SC2148,SC2086,SC1083

function f_firewall_delete_all () {

    if command -v nft >/dev/null 2>&1; then
        nft delete table inet ye3ipsec-wan 2>/dev/null
    fi

  	"$1" -t nat -D POSTROUTING -j chain-ye3ipsec-wan-nat
 	"$1" -t mangle -D FORWARD -j chain-ye3ipsec-wan-mangle
	"$1" -D FORWARD -j chain-ye3ipsec-wan-forward
	"$1" -D OUTPUT -j chain-ye3ipsec-wan-output
	"$1" -D INPUT -j chain-ye3ipsec-wan-input
   
 	"$1" -t nat --flush chain-ye3ipsec-wan-nat
 	"$1" -t mangle --flush chain-ye3ipsec-wan-mangle
 	"$1" --flush chain-ye3ipsec-wan-forward
 	"$1" --flush chain-ye3ipsec-wan-output
 	"$1" --flush chain-ye3ipsec-wan-input
 
	"$1" -t nat --delete-chain chain-ye3ipsec-wan-nat
	"$1" -t mangle --delete-chain chain-ye3ipsec-wan-mangle
	"$1" --delete-chain chain-ye3ipsec-wan-forward
	"$1" --delete-chain chain-ye3ipsec-wan-output
	"$1" --delete-chain chain-ye3ipsec-wan-input
}

function f_firewall_nft() {
    # Basic nftables setup
    nft add table inet ye3ipsec-wan
    nft add chain inet ye3ipsec-wan input '{ type filter hook input priority 0 ; }'
    nft add chain inet ye3ipsec-wan forward '{ type filter hook forward priority 0 ; }'
    nft add chain inet ye3ipsec-wan output '{ type filter hook output priority 0 ; }'
    nft add chain inet ye3ipsec-wan postrouting '{ type nat hook postrouting priority 100 ; }'

    # IPSec ports
    if [[ $Y_FIREWALL_IPSEC_PORT == "yes" ]]; then
        nft add rule inet ye3ipsec-wan input udp dport "{ $Y_PORT_IKE, $Y_PORT_NAT }" accept
        nft add rule inet ye3ipsec-wan input ip protocol esp accept
        nft add rule inet ye3ipsec-wan input ip6 nexthdr esp accept
    fi

    # NAT/Masquerade
    if [[ $Y_FIREWALL_NAT == "yes" ]]; then
        # Pool NAT
        nft add rule inet ye3ipsec-wan postrouting ip saddr "$1" oifname "$2" masquerade
        # S2S NAT
        if [[ $Y_FIREWALL_S2S_NAT == "yes" ]]; then
            # (Simplification: loop would be needed for multiple subnets)
            for sub in $(echo "$Y_S2S_PSK_REMOTE_TS" | tr ',' ' '); do
                [[ $sub != *:* ]] && nft add rule inet ye3ipsec-wan postrouting ip saddr "$sub" oifname "$2" masquerade
            done
        fi
    fi
}

function f_firewall () {

	# create chain
 	"$1" -t nat -N chain-ye3ipsec-wan-nat
 	"$1" -t mangle -N chain-ye3ipsec-wan-mangle
 	"$1" -N chain-ye3ipsec-wan-forward
 	"$1" -N chain-ye3ipsec-wan-output
 	"$1" -N chain-ye3ipsec-wan-input
  
	# IPSec connections : ESP, AH, IKE, NAT-T
	if [[ $Y_FIREWALL_IPSEC_PORT == "yes" ]]; then
		"$1" -A chain-ye3ipsec-wan-input -p udp -m multiport --dports "$Y_PORT_IKE,$Y_PORT_NAT" -j ACCEPT -m comment --comment "${Y_FIREWALL_COMMENT_PREFIX}_ipsec_port"
		"$1" -A chain-ye3ipsec-wan-output -p udp -m multiport --sports "$Y_PORT_IKE,$Y_PORT_NAT" -j ACCEPT -m comment --comment "${Y_FIREWALL_COMMENT_PREFIX}_ipsec_port"
		
		"$1" -A chain-ye3ipsec-wan-input -p "$Y_PROTO_ESP" -j ACCEPT -m comment --comment "${Y_FIREWALL_COMMENT_PREFIX}_ipsec_port"
		"$1" -A chain-ye3ipsec-wan-output -p "$Y_PROTO_ESP" -j ACCEPT -m comment --comment "${Y_FIREWALL_COMMENT_PREFIX}_ipsec_port"
			
		if [[ $1 == "iptables" ]]; then
			"$1" -A chain-ye3ipsec-wan-input -p "$Y_PROTO_AH" -j ACCEPT -m comment --comment "${Y_FIREWALL_COMMENT_PREFIX}_ipsec_port"
			"$1" -A chain-ye3ipsec-wan-output -p "$Y_PROTO_AH" -j ACCEPT -m comment --comment "${Y_FIREWALL_COMMENT_PREFIX}_ipsec_port"
		else
			"$1" -A chain-ye3ipsec-wan-input -m "$Y_PROTO_AH" -j ACCEPT -m comment --comment "${Y_FIREWALL_COMMENT_PREFIX}_ipsec_port"
			"$1" -A chain-ye3ipsec-wan-output -m "$Y_PROTO_AH" -j ACCEPT -m comment --comment "${Y_FIREWALL_COMMENT_PREFIX}_ipsec_port"
		fi
	fi
	
	# Allow server to reach remote dns, crl and ocsp
	if [[ $Y_FIREWALL_REVOCATION == "yes" ]]; then
		"$1" -A chain-ye3ipsec-wan-output -p tcp -m multiport --dports "$Y_FIREWALL_REVOCATION_PORT" -j ACCEPT -m comment --comment "${Y_FIREWALL_COMMENT_PREFIX}_revocation"
		"$1" -A chain-ye3ipsec-wan-output -p udp --dport 53 -j ACCEPT -m comment --comment "${Y_FIREWALL_COMMENT_PREFIX}_revocation"
		"$1" -A chain-ye3ipsec-wan-output -p tcp --dport 53 -j ACCEPT -m comment --comment "${Y_FIREWALL_COMMENT_PREFIX}_revocation"
	fi
	
	# local variables
	
	if [[ $1 == "iptables" ]]; then
		vl_private="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
	else
		vl_private="fc00::/7"
	fi
	
	if [[ $Y_FIREWALL_INTERCLIENT == "yes" ]]; then
		vl_interclient="ACCEPT"
	else
		vl_interclient="DROP"
	fi
	
	if [[ $Y_FIREWALL_LAN == "yes" ]]; then
		vl_lan="ACCEPT"
	else
		vl_lan="DROP"
	fi
	
	if [[ $Y_FIREWALL_INTERNET == "yes" ]]; then
		vl_internet="ACCEPT"
	else
		vl_internet="DROP"
	fi
	
	# List of subnets to process (Pool)
	vl_subnets="$2"
	
	# Optional: Include S2S subnets if enabled
	if [[ $Y_FIREWALL_S2S_NAT == "yes" ]]; then
		if [[ $Y_S2S_PSK_ENABLE == "yes" ]]; then vl_subnets="$vl_subnets,$Y_S2S_PSK_REMOTE_TS"; fi
		if [[ $Y_S2S_RSA_ENABLE == "yes" ]]; then vl_subnets="$vl_subnets,$Y_S2S_RSA_REMOTE_TS"; fi
	fi

	for vl_subnet in $(echo "$vl_subnets" | tr ',' ' '); do
		if [[ -z "$vl_subnet" ]] || [[ "$vl_subnet" == "dynamic" ]]; then continue; fi
		
		# Skip if subnet version doesn't match tool
		if [[ $1 == "iptables" ]]; then
			if [[ "$vl_subnet" == *":"* ]]; then continue; fi
		else
			if [[ "$vl_subnet" != *":"* ]]; then continue; fi
		fi

		# Act as a gateway, Masquerade subnet
		if [[ $Y_FIREWALL_NAT == "yes" ]]; then
			"$1" -t nat -A chain-ye3ipsec-wan-nat -s "$vl_subnet" -o "$3" -m policy --pol ipsec --dir out -j ACCEPT -m comment --comment "${Y_FIREWALL_COMMENT_PREFIX}_nat"
			"$1" -t nat -A chain-ye3ipsec-wan-nat -s "$vl_subnet" -o "$3" -j MASQUERADE -m comment --comment "${Y_FIREWALL_COMMENT_PREFIX}_nat"
		fi

		# Prevent IP packet fragmentation
		if [[ $Y_FIREWALL_MANGLE == "yes" ]]; then
			"$1" -t mangle -A chain-ye3ipsec-wan-mangle --match policy --pol ipsec --dir in -s "$vl_subnet" -o "$3" -p tcp -m tcp --tcp-flags SYN,RST SYN -m tcpmss --mss 1361:1536 -j TCPMSS --set-mss 1360 -m comment --comment "${Y_FIREWALL_COMMENT_PREFIX}_mangle"
		fi

		# forward block : most specific on top, and the less specific is following
		
		# Forward ESP : Inter client communication (Pool <-> Subnet)
		"$1" -A chain-ye3ipsec-wan-forward --match policy --pol ipsec --dir in --proto esp -s "$vl_subnet" -d "$2" -j "$vl_interclient" -m comment --comment "${Y_FIREWALL_COMMENT_PREFIX}_esp_interclient"
		"$1" -A chain-ye3ipsec-wan-forward --match policy --pol ipsec --dir out --proto esp -d "$vl_subnet" -s "$2" -j "$vl_interclient" -m comment --comment "${Y_FIREWALL_COMMENT_PREFIX}_esp_interclient"

		# Forward ESP : Private IPv4 addresses
		"$1" -A chain-ye3ipsec-wan-forward --match policy --pol ipsec --dir in --proto esp -s "$vl_subnet" -d "$vl_private" -j "$vl_lan" -m comment --comment "${Y_FIREWALL_COMMENT_PREFIX}_esp_lan"
		"$1" -A chain-ye3ipsec-wan-forward --match policy --pol ipsec --dir out --proto esp -d "$vl_subnet" -s "$vl_private" -j "$vl_lan" -m comment --comment "${Y_FIREWALL_COMMENT_PREFIX}_esp_lan"

		# Forward ESP : Other addresses, internet
		"$1" -A chain-ye3ipsec-wan-forward --match policy --pol ipsec --dir in --proto esp -s "$vl_subnet" -j "$vl_internet" -m comment --comment "${Y_FIREWALL_COMMENT_PREFIX}_esp_internet"
		"$1" -A chain-ye3ipsec-wan-forward --match policy --pol ipsec --dir out --proto esp -d "$vl_subnet" -j "$vl_internet" -m comment --comment "${Y_FIREWALL_COMMENT_PREFIX}_esp_internet"
	done

 	# chain injection
  	"$1" -I INPUT 1 -j chain-ye3ipsec-wan-input
	"$1" -I OUTPUT 1 -j chain-ye3ipsec-wan-output
	"$1" -I FORWARD 1 -j chain-ye3ipsec-wan-forward
 	"$1" -t mangle -I FORWARD 1 -j chain-ye3ipsec-wan-mangle
  	"$1" -t nat -I POSTROUTING 1 -j chain-ye3ipsec-wan-nat
	
}
