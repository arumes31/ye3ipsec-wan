#!/bin/bash
# shellcheck disable=SC1091,SC2034,SC2148,SC1083,SC2001,SC2076,SC2005,SC1090,SC2053,SC2153,SC2046

source ye3ipsec_patch/functions.sh

# Fix build with musl C library : https://github.com/strongswan/strongswan/issues/2195
source ye3ipsec_patch/before_build/all/pf_handler.c.sh
source ye3ipsec_patch/before_build/all/farp_spoofer.c.sh
