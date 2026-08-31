#!/usr/bin/env bash

mechos_is_live() {
  [[ -e /run/archiso/bootmnt || -d /run/archiso/bootmnt ]] && return 0
  grep -Eq '(^|[[:space:]])(archiso|archisobasedir=)' /proc/cmdline 2>/dev/null
}
