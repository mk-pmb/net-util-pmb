#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
#
# For HTTPS connect:  proxy-connect-netcat proxy.test:3128      example.net 22
# For SOCKS v5:       proxy-connect-netcat proxy.test:3128 -X 5 example.net 22
#
exec -a {proxy-connect-,}netcat -X connect -x "$@"; exit $?
