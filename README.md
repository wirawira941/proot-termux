# proot-termux — fix proot / proot-distro on Play Store Termux

One-command fix that makes `proot`, `proot-distro`, and `termux-chroot` work
again on the **Play Store build of Termux** (`googleplay.2026.10.09`,
targetSdk 37). The `proot` binary itself is not modified.

## Install

In Termux:

```bash
pkg install -y proot
curl -fsLO https://raw.githubusercontent.com/wirawira941/proot-termux/main/fix-proot-playstore.sh
bash fix-proot-playstore.sh
```

The script is idempotent: re-run it any time (for example after a
`pkg upgrade proot`, which undoes the fix — see caveats).

## What was actually wrong

Not a package-version regression — the downgrade advice in
termux-packages issue #338 is a red herring.

- This Termux build is targetSdk 37.
- Android 10+ blocks `execve()` of files labeled `app_data_file` for such
  apps.
- proot replaces the guest executable with its own loader at
  `$PREFIX/libexec/proot/loader` — which lives in app data and is labeled
  `app_data_file`.
- `termux-exec` only rewrites execs that pass through libc before the
  syscall. proot substitutes its loader *after* that hook, so the kernel
  sees a direct exec of an app-data file and returns `EACCES`.

The Play Store build ships a working copy of the loader inside the APK,
exposed at:

```
/data/data/com.termux/files/applib/libproot-loader.so
```

That resolves to the APK native library directory and is labeled
`apk_data_file`, which is executable.

## What the fix does

Replaces the broken loader with a symlink to the APK-bundled one:

```
$PREFIX/libexec/proot/loader
  -> /data/data/com.termux/files/applib/libproot-loader.so
```

A backup of the original loader is kept at:

```
$PREFIX/libexec/proot/loader.orig-appdata
```

## Verified

```
proot -0 /system/bin/toybox echo FINAL-PROOT-OK
FINAL-PROOT-OK

proot -0 /data/data/com.termux/files/usr/bin/sh -c 'echo OK; id -u'
OK
0

proot-distro login alpine -- /bin/sh -c 'cat /etc/alpine-release'
3.24.2

termux-chroot echo CHROOT-OK
CHROOT-OK
```

Also tested from a fresh login shell with no `PROOT_LOADER` environment
variable set.

## Caveats

1. **Upgrading proot undoes the fix.** `pkg upgrade proot` replaces the
   symlink with the app-data loader. Re-apply with:

   ```bash
   ln -sfn /data/data/com.termux/files/applib/libproot-loader.so \
     "$PREFIX/libexec/proot/loader"
   ```

   …or simply re-run `fix-proot-playstore.sh`.
2. **Apt source mismatch.** If your apt source is the F-Droid repo
   (packages.termux.dev/apt/termux-main), note the Play Store build's native
   repo is https://termux.net, whose proot package is already built to use
   the APK loader. While termux.net is unreachable from your device, the
   symlink is the practical workaround.
3. **32-bit guests are still broken.** The APK only bundles the 64-bit
   loader (`libproot-loader.so`); `loader32` remains an app-data file.
   aarch64 guests work.
4. `dpkg -V proot` will report the loader as modified — expected.

## Revert

```bash
bash fix-proot-playstore.sh --revert
```

(equivalent to removing the symlink and moving `loader.orig-appdata` back
into place.)

## Long-term

For a fully supported setup without workarounds, use the F-Droid/GitHub
Termux build (targetSdk 28) — but that requires uninstalling the Play Store
build and restoring your home directory.
