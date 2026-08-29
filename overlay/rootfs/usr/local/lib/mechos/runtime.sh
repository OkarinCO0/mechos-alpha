#!/usr/bin/env bash
mechos_is_live() {
  [[ -e /run/initramfs/live || -d /run/initramfs/live ]] && return 0
  grep -Eq '(^|[[:space:]])(rd\.live\.image|root=live:)' /proc/cmdline 2>/dev/null
}
