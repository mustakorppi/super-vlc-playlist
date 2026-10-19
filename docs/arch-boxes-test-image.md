# Clean Arch Linux test image for Super Playlist and Metadata Pro

This guide follows the [Xubuntu test-image workflow](xubuntu-boxes-test-image.md)
for `super-playlist` and `video-metadata-pro`, using native pacman VLC in GNOME Boxes.
It describes a test procedure, not a claim that this distribution has passed.
Use Linux VLC 3; stop and record an unsupported-version result if the repository
supplies a different major version.

**Host** means your real computer running Boxes. **Guest** means Arch Linux inside
Boxes. Run commands in the guest unless explicitly marked **Host**. These are
separate distribution guides; record the CPU architecture with `uname -m` too.
The procedure below targets an x86_64 guest on an x86_64 host.

## 1. Install the guest

1. Download a current official [Arch Linux ISO](https://archlinux.org/download/)
   for x86_64. Record its filename, date, and checksum.
2. In Boxes, click **+ → Install from File**, select the ISO, and name the VM
   `Arch-<install-date>-VLC-test`. Allocate 4 GB RAM (8 GB if available) and a
   40 GB virtual disk. Keep Boxes' default virtual network enabled.
3. Boot the ISO. At its root shell, check networking with `ping -c 3 archlinux.org`.
   Arch's installation ISO starts in a terminal rather than a live GNOME desktop.
4. Run `archinstall`. In the guided installer, choose the VM's virtual disk,
   a default partition layout, a bootloader appropriate to the VM's firmware,
   your locale/timezone, and a normal user such as `vlctest` with sudo access.
5. Choose the **Desktop → GNOME** profile, virtual-machine/open-source graphics
   as offered, PipeWire audio, and NetworkManager networking. Menu labels vary
   with the installer version. Use the regular repositories; omit VLC for now.
6. Review the selected disk and configuration, install, then reboot. Eject the
   ISO in Boxes if the installation shell boots again. Log in to the installed
   GNOME desktop and confirm networking and a terminal are available.

The [official archinstall project](https://github.com/archlinux/archinstall)
and [guided installation instructions](https://archinstall.archlinux.page/installing/guided.html)
provide details. The manual [Arch installation guide](https://wiki.archlinux.org/title/Installation_guide)
is an alternative. Arch Linux ARM is a separate project and is outside this guide.

Keep test media on the guest's virtual disk. Metadata Pro creates full video
backups when saving, so allow extra host disk space for videos and snapshots.
Snapshots do not restore changes made to host shared folders or USB storage.

Before each snapshot, shut down the guest normally and wait until Boxes shows
it stopped. Open **Properties/Preferences → Snapshots**, click **+**, and rename
the snapshot. See [GNOME's snapshot instructions](https://help.gnome.org/gnome-boxes/snapshot-create.html).
Optionally save **`00-installed-from-ISO`** before updating.

## 2. Prepare the clean OS baseline

Inside a terminal in the installed desktop, as the normal user:

```sh
sudo pacman -Syu --needed spice-vdagent xdg-user-dirs
xdg-user-dirs-update
sudo reboot
```

Always complete full system upgrades. Do not use `pacman -Sy` followed by an
individual package installation: Arch does not support partial upgrades. Resolve
package errors before continuing. See [Arch system maintenance](https://wiki.archlinux.org/title/System_maintenance).

```sh
command -v vlc
pacman -Q vlc
```

Missing-package output is expected. If VLC is already installed, remove it with
`sudo pacman -Rns vlc`, reviewing the proposed removals first. Only do this in the
disposable guest. If you added Flatpak or Snap VLC, remove that installation too
before taking the baseline. Do not install either extension yet.

```sh
mkdir -p ~/test-records ~/installers ~/Videos/vlc-test
cat /etc/os-release > ~/test-records/os-release.txt
uname -a > ~/test-records/kernel.txt
uname -m > ~/test-records/architecture.txt
date -Iseconds > ~/test-records/baseline-date.txt
pacman -Q > ~/test-records/packages-clean-os.txt
pacman -Qm > ~/test-records/foreign-packages.txt
cp /etc/pacman.conf /etc/pacman.d/mirrorlist ~/test-records/
```

Shut down and create **`01-clean-os-no-vlc`**. Arch is rolling release: the ISO
date is not the installed package version set. Retain the package list and date.

## 3. Prepare clean installer packages on the host


Use the projects' packaging scripts so host presets, caches, installed helpers,
and development environments are not copied into the guest. These packages
contain your current local source files, including any uncommitted changes.

**Host terminal**, from the Super Playlist checkout:

```sh
cd /home/user/dev/super-playlist
bundle_dir=$(mktemp -d /tmp/vlc-install-test.XXXXXX)
python3 package.py "$bundle_dir/super-playlist"
python3 ../video-metadata-pro/package.py "$bundle_dir/video-metadata-pro"
tar -czf "$bundle_dir/installers.tar.gz" -C "$bundle_dir" super-playlist video-metadata-pro
sha256sum "$bundle_dir/installers.tar.gz"
printf 'Installer archive: %s\n' "$bundle_dir/installers.tar.gz"
```

Check that both packaging commands succeeded before using the archive. Copy
the printed archive and its checksum to a persistent host folder if retaining
them for later; `/tmp` is temporary.

Transfer `installers.tar.gz` to the guest using Boxes' file transfer (drag the
file into the running guest, with the guest tools active) or a shared folder.
Copy it into the guest's `~/installers` directory, then extract it there:

```sh
cd ~/installers
sha256sum installers.tar.gz
tar -xzf installers.tar.gz
```

Confirm the checksum matches the host. The resulting directories should be
`~/installers/super-playlist` and `~/installers/video-metadata-pro`.

Also copy a small MP4 and MKV into `~/Videos/vlc-test`. Use disposable copies,
not your original collection, and copy them off any shared folder before editing.
Use the same originals for each fresh test. No GitHub login, Git, pip, or host
virtual environment is required for this installation route.


If Downloads is empty after a transfer notification, check the guest's download
location with `xdg-user-dir DOWNLOAD` and verify the archive exists. For shared
folders, install `spice-webdavd` with `sudo pacman -Syu --needed spice-webdavd`
and follow [GNOME's shared-folder instructions](https://help.gnome.org/gnome-boxes/shared-folders.html).
Copy everything onto the guest disk and verify the checksum before testing.

## 4. Install and check pacman VLC

```sh
sudo pacman -Syu --needed vlc vlc-plugins-all python python-mutagen mkvtoolnix-cli
```

Reboot if this full upgrade updates the kernel or desktop components. Arch splits
VLC into plugins; `vlc-plugins-all` includes Lua support and playback plugins for
this broad desktop test baseline. See [Arch's VLC guidance](https://wiki.archlinux.org/title/VLC_media_player)
and the [Lua plugin package](https://archlinux.org/packages/extra/x86_64/vlc-plugin-lua/).
The metadata dependencies are [python-mutagen](https://archlinux.org/packages/extra/any/python-mutagen/)
and [mkvtoolnix-cli](https://archlinux.org/packages/extra/x86_64/mkvtoolnix-cli/).
No AUR packages, pip installation, or virtual environment are needed.

```sh
/usr/bin/vlc --version
python3 -c 'import sys, mutagen; print(sys.version); print(mutagen.version_string)'
mkvextract --version
mkvpropedit --version
mkvinfo --version
pacman -Q vlc vlc-plugin-lua vlc-plugins-all python python-mutagen mkvtoolnix-cli > ~/test-records/pacman-runtime.txt
pacman -Q > ~/test-records/packages-vlc-ready.txt
date -Iseconds > ~/test-records/vlc-ready-date.txt
```

Confirm VLC reports version 3 and all dependency checks succeed. Launch
`/usr/bin/vlc`, complete its first-run prompt, and play both test videos. Confirm
picture and sound work before installing extensions. Fully quit VLC; neither
extension should appear in its View menu yet.

Shut down and create **`02-pacman-vlc-ready-no-addins`**. Include the uninstalled
packages and untouched test media. Use snapshot 01 for complete installation
tests and snapshot 02 for repeatable extension tests against this package set.

Restoring snapshot 01 and running `pacman -Syu` later tests the repositories as
of that later date. For a fixed dependency comparison, restore snapshot 02 and
do not update between attempts. If an update is needed, create and record a new
baseline; never mix newly synchronized packages with an old restored system.

## 5. Test installations


Run installers as the guest's normal user, without `sudo`. Close VLC before
each installation, and restart it afterward.

| Attempt | Starting snapshot | Install |
| --- | --- | --- |
| Super Playlist alone | 02 | Super Playlist only; checks independence from Metadata Pro |
| Metadata Pro alone | 02 | Metadata Pro only |
| Both together | 02 | Metadata Pro, then Super Playlist |
| Complete fresh setup | 01 | VLC and dependencies, then both add-ins |

For Super Playlist:

```sh
cd ~/installers/super-playlist
python3 install.py > ~/test-records/super-playlist-install.log 2>&1
cat ~/test-records/super-playlist-install.log
```

For Metadata Pro:

```sh
cd ~/installers/video-metadata-pro
python3 install.py > ~/test-records/metadata-pro-install.log 2>&1
cat ~/test-records/metadata-pro-install.log
```

Check for successful installation output; stop and inspect any traceback.
Launch VLC explicitly with `/usr/bin/vlc` to avoid confusing native and sandboxed builds.

For the combined test:

1. Open a copied MP4. Select **View → Metadata Pro** and use **Check status**
   until its metadata loads.
2. Set Artist to `Test_Artist`, Album to `Test_Album`, and Genre to `Test_Genre`.
   Save and check status until saving and verification succeed. Reopen the file
   and confirm the values persisted. Repeat for the MKV.
3. Add both files to the normal VLC playlist. Select **View → Super Playlist**,
   click **Load playlist**, and use **Check status** if requested.
4. Confirm both files and their tags appear. Filter by `Test_Artist`, reset the
   filters, and export the results to an M3U8. Open the export in VLC.
5. Restart VLC and confirm both extensions still open and read the saved tags.

For independent tests, perform the relevant subset. Super Playlist alone should
read existing tags without Metadata Pro being installed.

## 6. Reset between attempts


1. Copy useful logs, screenshots, version records, and the installer archive
   checksum out of the guest to the host.
2. Shut down Arch Linux normally.
3. In Boxes, open **Properties/Preferences → Snapshots**, select 01 or 02,
   and choose **Revert**. Boot the VM again.
4. Transfer the latest installer archive again if needed. A revert also restores
   old source packages, logs, and media inside the guest, not just installed software.
5. Repeat the desired installation attempt and label the results with the tested
   archive checksum and date.

Reverting discards changes since the snapshot; see [GNOME's restore instructions](https://help.gnome.org/gnome-boxes/snapshot-revert.html).
Reinstalling an add-in without reverting is an **upgrade/preservation test**,
not a clean installation: both installers deliberately retain user state.
Guest snapshots also cannot restore files edited in host shared folders.


## 7. Record results and diagnose failures

Record the ISO date/checksum, installed package lists, CPU architecture, test
date, installer archive checksum, starting snapshot, and pass/fail for each
attempt. Include the desktop/session and reproduction steps for UI problems.
Results apply to that recorded package set, not every future Arch update.
Flatpak and Snap installations need separate runtime procedures.

For missing extensions, check `pacman -Q vlc-plugin-lua`, close every VLC process,
and restart `/usr/bin/vlc`. Confirm the installer used the same normal user as
VLC. For helper or playback failures, capture a terminal log:

```sh
/usr/bin/vlc -vv > ~/test-records/vlc-debug.log 2>&1
```

Reproduce the failure and quit VLC. Preserve this log, installer logs, and any
failed dependency-check output before reverting. A future Python or VLC update
may require a compatibility fix; record the failure rather than treating an
installation message alone as a passing test.
