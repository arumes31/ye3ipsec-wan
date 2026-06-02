#!/bin/bash
# shellcheck disable=SC1091,SC2034,SC2148,SC1083,SC2001,SC2076,SC2005,SC1090,SC2053,SC2153,SC2046

# https://github.com/strongswan/strongswan/commit/f5b1ca4ef60bc4fca91f0d1e852ef8447d23c99a

f_replace "xxd" "src/libcharon/network/pf_handler.c" "ye3ipsec_patch/before_build/all/pf_handler.c_search.txt" "ye3ipsec_patch/before_build/all/pf_handler.c_replacement.txt"
