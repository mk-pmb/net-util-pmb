#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
exec serialport-socat --device='/dev/ttyUSB0' "$@"; exit $?
