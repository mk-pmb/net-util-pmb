#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
#
# Purpose: Enumerate ~/net/* sshfs mounts without risking the I/O block
# for stat() that could occurr when naively using a ~/net/*/ glob.
#
mount | grep -Fe " on $(readlink -m "$HOME")/net/" |
  grep -oPe ' on \S*/net/\S+(?= type fuse\.sshfs )' | cut -c 5-; exit $?
