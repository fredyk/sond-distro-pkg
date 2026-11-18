#!/bin/sh
# Sond utilities battery, run inside the booted guest (PATH=/bin, package
# binaries only). POSIX sh: no bashisms; works under busybox ash or mksh.
# One line per utility: "ok: <name> -> <first output line>" or
# "fail: <name> -> <reason>", then a summary and RESULT: PASS|FAIL.
# There are no silent greens: a missing utility fails (rc != 0).

total=0
oks=0
fails=0
NL='
'

check() {
  # $1 label, $2 command line (evaluated with sh -c), $3 first-line glob
  # (empty string: exit code 0 is the assertion, e.g. mkdir/cp/mv/rm).
  total=$((total + 1))
  out=$(sh -c "$2" 2>&1)
  rc=$?
  first=$out
  case $out in
    *"$NL"*) first=${out%%"$NL"*} ;;
  esac

  matched=0
  if [ -n "$3" ]; then
    case $first in $3) matched=1 ;; esac
  elif [ "$rc" -eq 0 ]; then
    matched=1
  fi

  if [ "$rc" -eq 0 ] && [ "$matched" -eq 1 ]; then
    oks=$((oks + 1))
    if [ -n "$first" ]; then
      echo "ok: $1 -> $first"
    else
      echo "ok: $1 -> rc=0"
    fi
  else
    fails=$((fails + 1))
    if [ "$rc" -ne 0 ]; then
      echo "fail: $1 -> rc=$rc: ${first:-<no output>}"
    elif [ -z "$first" ]; then
      echo "fail: $1 -> empty output, expected match: $3"
    else
      echo "fail: $1 -> unexpected output: $first"
    fi
  fi
}

check "ls"            "ls -l /"                       "total *"
check "ps"            "ps"                            "*PID*"
check "cat"           "cat /etc/hostname"             "?*"
check "grep -c"       "grep -c . /etc/hostname"       "[1-9]*"
check "echo"          "echo hola"                     "hola"
check "mkdir"         "mkdir /tmp/d"                  ""
check "cp"            "cp /etc/hostname /tmp/d/h"     ""
check "mv"            "mv /tmp/d/h /tmp/d/h2"         ""
check "cat /tmp/d/h2" "cat /tmp/d/h2"                 "?*"
check "rm -r"         "rm -r /tmp/d"                  ""
check "mount tmpfs"   "mount -t tmpfs none /mnt && grep ' /mnt ' /proc/mounts" "none /mnt tmpfs *"
check "cd + pwd"      "cd /tmp && pwd"                "/tmp"
check "sh -c"         "sh -c 'echo desde-sh'"         "desde-sh"
check "readlink"      "readlink /bin/ls"              "?*"

echo "battery: $oks/$total utilities ok ($fails failed)"
if [ "$fails" -eq 0 ]; then
  echo "RESULT: PASS"
  exit 0
fi
echo "RESULT: FAIL"
exit 1
