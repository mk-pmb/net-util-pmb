#!/bin/sh
# -*- coding: utf-8, tab-width: 2 -*-
#
# Motivation: My bash-completion doesn't suggest subdirectories
#   of the current directory after `fusermount -u `.
while [ "$#" -ge 1 ]; do
  echo -n "$1: "
  fusermount -uz "$1" && echo unmounted.
  shift
done
