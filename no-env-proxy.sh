#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
for no_proxy in {http,no}{s,}_proxy; do
  unset "${no_proxy^^}" "$no_proxy"
done
exec "$@"; exit $?
