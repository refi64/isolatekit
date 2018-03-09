#!/bin/sh

set -e

PREFIX="$1"
cd "`dirname "$0"`"

inst() {
  case "$1" in
  exec) mode=755 ;;
  data) mode=644 ;;
  esac

  if [ -n "$3" ]; then
    target="$PREFIX/$3/`basename $2`"
  else
    target="$PREFIX/$2"
  fi
  echo "  inst ($mode) $2 -> $target"
  install -Dm $mode "$2" "$target"
}

if touch "$PREFIX" >/dev/null 2>&1; then
  inst exec bin/ik
  inst exec misc/ik-update-version bin
  inst data misc/isolatekit-tmpfiles.conf lib/tmpfiles.d
  inst data misc/com.refi64.isolatekit.policy share/polkit-1/actions
  for dir in share/isolatekit/*; do
    for file in $dir/*; do
      if [ "$dir" = "share/isolatekit/bin" ]; then
        inst exec $file
      else
        inst data $file
      fi
    done
  done
else
  exec pkexec sh "`realpath "$0"`" "$out"
fi
