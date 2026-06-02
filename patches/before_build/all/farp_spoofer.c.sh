#!/bin/bash
# shellcheck disable=SC2154,SC1091,SC2034,SC2148,SC2086,SC1083

# https://github.com/strongswan/strongswan/commit/540881627fe8083207f9a2cfd01b931164c7ef4e

f_replace "xxd" "src/libcharon/plugins/farp/farp_spoofer.c" "ye3ipsec_patch/before_build/all/farp_spoofer.c_search.txt" "ye3ipsec_patch/before_build/all/farp_spoofer.c_replacement.txt"
