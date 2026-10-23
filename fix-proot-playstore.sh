#!/data/data/com.termux/files/usr/bin/bash
# fix-proot-playstore.sh — make proot / proot-distro work on the Play Store
# Termux build.
#
# Root cause: the Play Store build is targetSdk 37, and Android 10+ blocks
# execve() of files labeled app_data_file for such apps. proot replaces the
# guest executable with its own loader at $PREFIX/libexec/proot/loader, which
# lives in app data — so the kernel returns EACCES. termux-exec cannot help:
# it only rewrites execs that pass through libc, and proot substitutes its
# loader after that hook. The Play Store APK ships a working loader copy at
# /data/data/com.termux/files/applib/libproot-loader.so (apk_data_file —
# executable). This script points proot's loader at that copy via symlink.
#
# Usage:
#   bash fix-proot-playstore.sh            apply the fix (idempotent)
#   bash fix-proot-playstore.sh --revert   restore the original loader
set -eu

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOADER_DIR="$PREFIX/libexec/proot"
LOADER="$LOADER_DIR/loader"
BACKUP="$LOADER_DIR/loader.orig-appdata"
APK_LOADER="/data/data/com.termux/files/applib/libproot-loader.so"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

if [ "${1:-}" = "--revert" ]; then
  [ -L "$LOADER" ] || die "$LOADER is not a symlink; nothing to revert."
  [ -e "$BACKUP" ] || die "backup not found ($BACKUP). Restore the original with: pkg reinstall proot"
  rm "$LOADER"
  mv "$BACKUP" "$LOADER"
  info "Reverted: original app-data loader restored from backup."
  exit 0
fi

command -v proot >/dev/null 2>&1 || die "proot is not installed. Run: pkg install proot"
[ -e "$APK_LOADER" ] || die "APK-bundled loader not found at $APK_LOADER — this fix only applies to the Play Store Termux build. F-Droid/GitHub builds do not need it."
[ -d "$LOADER_DIR" ] || die "proot loader directory missing: $LOADER_DIR"

if [ -L "$LOADER" ] && [ "$(readlink "$LOADER")" = "$APK_LOADER" ]; then
  info "Already fixed: $LOADER -> $APK_LOADER"
else
  if [ -f "$LOADER" ] && [ ! -e "$BACKUP" ]; then
    mv "$LOADER" "$BACKUP"
    info "Original loader backed up to $BACKUP"
  fi
  ln -sfn "$APK_LOADER" "$LOADER"
  info "Loader replaced: $LOADER -> $APK_LOADER"
fi

info "Verifying..."
out="$(proot -0 /system/bin/toybox echo PROOT-FIX-OK 2>&1)" || die "proot still failing: $out"
[ "$out" = "PROOT-FIX-OK" ] || die "unexpected proot output: $out"
echo "proot (toybox): OK"
proot -0 "$PREFIX/bin/sh" -c 'echo "proot (termux sh, uid $(id -u)): OK"'
if command -v termux-chroot >/dev/null 2>&1; then
  termux-chroot echo "termux-chroot: OK" || echo "termux-chroot: still failing (not fatal)"
fi

echo
echo "Done. Remember:"
echo "- 'pkg upgrade proot' undoes this fix — just re-run this script afterwards."
echo "- 32-bit guests are NOT fixed (loader32 has no APK copy); aarch64 guests work."
echo "- Revert anytime: bash fix-proot-playstore.sh --revert"
