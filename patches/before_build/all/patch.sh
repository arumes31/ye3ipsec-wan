#!/bin/bash
# shellcheck disable=SC2154,SC1091,SC2034,SC2148,SC2086,SC1083

source ye3ipsec_patch/functions.sh

# Fix build with musl C library : https://github.com/strongswan/strongswan/issues/2195
source ye3ipsec_patch/before_build/all/pf_handler.c.sh
source ye3ipsec_patch/before_build/all/farp_spoofer.c.sh
