#!/bin/bash
# shellcheck disable=SC2154,SC1091,SC2034,SC2148,SC2086,SC1083

# https://github.com/strongswan/strongswan/commit/f5b1ca4ef60bc4fca91f0d1e852ef8447d23c99a

f_replace "xxd" "src/libcharon/network/pf_handler.c" "ye3ipsec_patch/before_build/all/pf_handler.c_search.txt" "ye3ipsec_patch/before_build/all/pf_handler.c_replacement.txt"
