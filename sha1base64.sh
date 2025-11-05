#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
#
# Calculate the SHA-1 hash of arguments or input and print them
# in base64 encoding. Example for Apache SHA passwords:
# echo "username:{SHA}$(sha1base64 'password')" >>.htpasswd
# (Observe that there's no "1" in "{SHA}".)

function sha1base64 () {
  if [ "$#" == 0 ]; then
    echo -ne "$("${HASH_ALGO:-sha1}sum" --binary |
      sed -re 's~[0-9a-f]{2}~\\x&~g; s~[ *-]+$~~')" | base64
  else
    while [ "$#" -ge 1 ]; do
      echo -n "$1" | "$FUNCNAME"
      shift
    done
  fi
}

sha1base64 "$@"; exit $?
