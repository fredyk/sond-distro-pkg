# Battery for the Sond integration run. Each non-comment line is typed, in
# order, into the guest shell over the serial console (run-qemu.sh --cmd); the
# transcript keeps the prompt, the echoed keystrokes and every evidence line.
# POSIX sh / mksh only. Package binaries live in /bin (PATH=/bin in the init).
#
# `ok <name> <rc>` prints the VERIFY-OK evidence line and counts pass/fail.
# The toybox package freezes exactly ten applets (contract 02 section C), so
# `readlink` is deliberately absent from the guest: the link targets are shown
# with `ls -l`, which is the evidence the delivery quotes.
P=0; F=0
ok() { echo "VERIFY-OK: $1 :: rc=$2"; [ "$2" = 0 ] && P=$((P+1)) || F=$((F+1)); }

/bin/echo BATTERY-BEGIN

# --- the twelve mandated utilities ---------------------------------------
/bin/ls / ; ok ls $?
/bin/ps -A ; ok ps $?
/bin/echo sond-echo-payload ; ok echo $?
/bin/mkdir -p /tmp/sond-verify ; ok mkdir $?
/bin/echo sond-marker-2026-11-18 > /tmp/sond-verify/marker.txt
/bin/cat /tmp/sond-verify/marker.txt ; ok cat $?
/bin/grep -c sond /tmp/sond-verify/marker.txt ; ok grep $?
/bin/cp /tmp/sond-verify/marker.txt /tmp/sond-verify/copied.txt ; ok cp $?
/bin/ls -l /tmp/sond-verify/copied.txt
/bin/mv /tmp/sond-verify/copied.txt /tmp/sond-verify/moved.txt ; ok mv $?
/bin/ls /tmp/sond-verify
/bin/rm /tmp/sond-verify/moved.txt ; ok rm $?
/bin/ls -A /tmp/sond-verify
/bin/mount ; ok mount $?
/bin/mkdir -p /tmp/sond-mnt ; /bin/mount -t tmpfs none /tmp/sond-mnt
/bin/mount | /bin/grep -c sond-mnt ; ok mount-tmpfs $?
/bin/sh -c '/bin/echo sh-from-mksh' ; ok sh $?
/bin/sh -c 'cd /tmp && pwd' ; ok cd $?

# --- symlink targets, the readlink substitute ----------------------------
/bin/ls -l /bin/ls ; ok symlink-ls $?
/bin/ls -l /bin/sh ; ok symlink-sh $?

# --- the frozen toybox applet list ---------------------------------------
/bin/toybox ; ok toybox-applets $?

# --- licences inside the guest -------------------------------------------
/bin/ls /share/licenses/toybox-static /share/licenses/mksh-static ; ok licences $?
/bin/grep -c 'Rich Felker' /share/licenses/toybox-static/musl-COPYRIGHT ; ok licences-musl-in-toybox $?
/bin/grep -c 'Rich Felker' /share/licenses/mksh-static/musl-COPYRIGHT ; ok licences-musl-in-mksh $?
/bin/grep -c mirabilos /share/licenses/mksh-static/LICENCE-MirOS.txt ; ok licences-mksh $?
/bin/grep -c Unicode /share/licenses/mksh-static/UNICODE-NOTICE ; ok licence-unicode $?

/bin/echo "BATTERY ok=$P fail=$F"
[ "$F" -eq 0 ] && /bin/echo "RESULT: PASS" || /bin/echo "RESULT: FAIL"
/bin/echo BATTERY-DONE
