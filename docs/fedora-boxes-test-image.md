# Clean Fedora Workstation test image for Super Playlist and Metadata Pro

This guide follows the [Xubuntu test-image workflow](xubuntu-boxes-test-image.md)
for `super-playlist` and `video-metadata-pro`, using native RPM VLC in GNOME Boxes.
It describes a test procedure, not a claim that this distribution has passed.
Use Linux VLC 3; stop and record an unsupported-version result if the repository
supplies a different major version.

**Host** means your real computer running Boxes. **Guest** means Fedora Workstation inside
Boxes. Run commands in the guest unless explicitly marked **Host**. These are
separate distribution guides; record the CPU architecture with `uname -m` too.
The procedure below targets an x86_64 guest on an x86_64 host.

## 1. Install the guest

1. In Boxes on the host, click **+ → Install from File** and select your Fedora
   Workstation ISO. Record its filename, release, and checksum with the results.
2. Name the VM `Fedora-<release>-VLC-test`. Allocate at least 4 GB RAM (8 GB if
   available) and a 40 GB virtual disk.
3. Boot the ISO, choose **Start Fedora Workstation**, and open **Install Fedora**
   or **Install to Hard Drive** on the live desktop. Wording varies by release.
4. Install onto the VM's virtual disk using automatic partitioning. Restart,
   ejecting the ISO in Boxes' device settings if the live desktop boots again.
5. Complete initial setup with a normal administrator user such as `vlctest`.
   Confirm the installed desktop and network work.

Use a supported Fedora Workstation release. This guide uses DNF on conventional
Workstation; Atomic desktops such as Silverblue need a different installation
workflow. See [Fedora Workstation](https://fedoraproject.org/workstation/download/)
and [creating a box](https://help.gnome.org/gnome-boxes/create.html).

Keep test media on the guest's virtual disk. Metadata Pro creates full video
backups when saving, so allow extra host disk space for videos and snapshots.
Snapshots do not restore changes made to host shared folders or USB storage.

Before each snapshot, shut down the guest normally and wait until Boxes shows
it stopped. Open **Properties/Preferences → Snapshots**, click **+**, and rename
the snapshot. See [GNOME's snapshot instructions](https://help.gnome.org/gnome-boxes/snapshot-create.html).
Optionally save **`00-installed-from-ISO`** before updating.

## 2. Prepare the clean OS baseline

```sh
sudo dnf upgrade --refresh
sudo dnf install spice-vdagent
sudo reboot
```

Wait for successful completion before rebooting. Keep the same Fedora release
throughout a test series, and leave SELinux in its default enforcing mode.
Check for an existing VLC installation:

```sh
command -v vlc
rpm -q vlc
flatpak list --app
```

Missing-package output is expected for a fresh image. If RPM VLC is already
installed, remove it with `sudo dnf remove vlc`, reviewing the transaction first.
If Flatpak VLC is listed, remove that installation through Software before
saving the baseline. Run removals only in this disposable guest. Do not launch
or install either extension yet.

```sh
mkdir -p ~/test-records ~/installers ~/Videos/vlc-test
cat /etc/os-release > ~/test-records/os-release.txt
uname -a > ~/test-records/kernel.txt
uname -m > ~/test-records/architecture.txt
rpm -qa | sort > ~/test-records/packages-clean-os.txt
dnf repolist > ~/test-records/repositories.txt
getenforce > ~/test-records/selinux.txt
```

Shut down and create **`01-clean-os-no-vlc`**.

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


If Boxes reports a transfer but Downloads looks empty, check the guest's actual
download location with `xdg-user-dir DOWNLOAD`. Verify the archive exists and
its checksum matches before proceeding. As an alternative, install
`spice-webdavd` with DNF and configure a Boxes shared folder using
[GNOME's shared-folder instructions](https://help.gnome.org/gnome-boxes/shared-folders.html).
Copy the archive and media onto the guest disk before testing.

## 4. Install and check RPM VLC

```sh
sudo dnf install vlc vlc-plugin-lua vlc-plugin-ffmpeg python3 python3-mutagen mkvtoolnix
/usr/bin/vlc --version
python3 -c 'import sys, mutagen; print(sys.version); print(mutagen.version_string)'
mkvextract --version
mkvpropedit --version
mkvinfo --version
```

The native packages are documented in Fedora's package catalog:
[VLC and its plugins](https://packages.fedoraproject.org/pkgs/vlc/),
[Mutagen](https://packages.fedoraproject.org/pkgs/python-mutagen/python3-mutagen/),
and [MKVToolNix](https://packages.fedoraproject.org/pkgs/mkvtoolnix/mkvtoolnix/).
Install the Lua plugin explicitly because both extensions require Lua support.
No pip installation or virtual environment is needed.

Confirm VLC reports version 3 and every dependency check succeeds. Launch
`/usr/bin/vlc`, complete its first-run prompt, and play both test videos before
installing extensions. Confirm picture and sound work, then fully quit VLC.
Neither extension should appear in its View menu yet.

An MP4 or MKV container does not identify its video/audio codecs. If playback
fails, record the codec error and resolve it before saving the ready snapshot;
otherwise later failures cannot reliably be attributed to the extensions.
Fedora's codec availability depends on the installed packages and repositories.
Consult [Fedora's multimedia guidance](https://docs.fedoraproject.org/en-US/quick-docs/installing-plugins-for-playing-movies-and-music/)
if extra codecs are needed. Record any additional repository and packages as a
separate baseline variant; do not silently replace RPM VLC with Flatpak VLC.

```sh
rpm -q vlc vlc-plugin-lua vlc-plugin-ffmpeg python3 python3-mutagen mkvtoolnix > ~/test-records/rpm-runtime.txt
rpm -qa | sort > ~/test-records/packages-vlc-ready.txt
dnf repolist > ~/test-records/repositories.txt
```

Shut down and create **`02-rpm-vlc-ready-no-addins`**. Include the uninstalled
packages and untouched test media to save time. Use snapshot 01 to test VLC
installation itself and snapshot 02 to test extension installation.

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
Launch VLC explicitly with `/usr/bin/vlc` to avoid confusing RPM and Flatpak builds.

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
2. Shut down Fedora normally.
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

Record the Fedora release, CPU architecture, ISO filename/checksum, test date,
installer archive checksum, starting snapshot, package/repository records, and
pass/fail for each installation attempt. Save the actual error and reproduction
steps for failures. These instructions do not establish Flatpak or Snap support.

For missing extensions, confirm `rpm -q vlc-plugin-lua`, close every VLC process,
and relaunch `/usr/bin/vlc`. For helper failures, capture a terminal log:

```sh
/usr/bin/vlc -vv > ~/test-records/vlc-debug.log 2>&1
```

Reproduce the failure, then quit VLC. Check installer logs and dependency checks
first. If SELinux denials are suspected, inspect `sudo ausearch -m AVC -ts recent`
when `ausearch` is available; retain the denial details instead of disabling
SELinux. Export logs to the host before reverting.
