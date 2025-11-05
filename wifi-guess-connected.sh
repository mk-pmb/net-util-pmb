#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
LANG=C iwconfig 2>/dev/null | grep -qPie '^\s+link '
