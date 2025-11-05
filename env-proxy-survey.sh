#!/bin/sh
# -*- coding: utf-8, tab-width: 2 -*-
grep -aoPhie '\b\w+_proxy=[ -~]+' -- /proc/[0-9]*/environ 2>/dev/null |
  sed -re 's~^[A-Za-z_]+~\L&\E~;/^no_proxy=/d' |
  LANG=C sort -V | uniq -c | sort -g
