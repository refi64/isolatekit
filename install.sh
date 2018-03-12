#!/bin/sh

set -e

PREFIX="$1"
cd "`dirname "$0"`"

inst() {
  case "$1" in
  exec) local mode=755 ;;
  data) local mode=644 ;;
  *) echo "Invalid mode: $mode"; exit 1 ;;
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
  inst exec misc/ik-update-release bin
  inst data misc/isolatekit-tmpfiles.conf lib/tmpfiles.d
  inst data misc/com.refi64.isolatekit.policy share/polkit-1/actions
  for dir in share/isolatekit/*; do
    base=`basename $dir`
    if [ "$base" = "bin" ] || [ "$base" = "sbin" ]; then
      mode=exec
    else
      mode=data
    fi

    for file in $dir/*; do
      inst $mode $file
    done
  done

  if [ -d man/out ]; then
    for file in man/out/*; do
      sect=`echo $file | sed 's/.*\.//'`
      inst data $file share/man/man$sect
    done
  fi
else
  exec pkexec sh "`realpath "$0"`" "$PREFIX"
fi
