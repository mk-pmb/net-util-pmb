#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
iwconfig 2>/dev/null | tr '\n' '\r' | sed -re '
  s~^~\r~
  s~$~\r~
  s~\t~ ~g
  s~\s*\r +~\t~g
  s~\r~\n~g
  ' | sed -nre '
  /\t[Ll]ink /{
    s~^([A-Za-z0-9_:-]+) .* ESSID: *"([^\t"]*)"\s*(\t.*|)$~\1\t\2~p
  }'
