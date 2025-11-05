#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
HASH_ALGO="$1" sha1base64 "${@:2}"; exit $?
