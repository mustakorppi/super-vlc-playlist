# Clean Xubuntu test image for Super Playlist and Metadata Pro

This guide uses GNOME Boxes on your Ubuntu 20.04 host and your Xubuntu
20.04.3 LTS ISO. The two projects are `super-playlist` and
`video-metadata-pro`. Start with APT VLC; test Snap separately from the clean
OS snapshot.

**Host** means your real Ubuntu computer. **Guest** means Xubuntu inside Boxes.
Run commands in the guest unless explicitly marked **Host**.

Xubuntu 20.04 reached end of support on April 29, 2023. This image is useful
for testing that older environment; results do not establish compatibility
with current distributions. See the [Xubuntu release record](https://xubuntu.org/release/20.04/).

## 1. Install the guest

1. Open Boxes on the host. Create a VM from the Xubuntu 20.04.3 ISO.
2. Name it `Xubuntu-20.04-VLC-test`. Allocate 4 GB RAM if the host can spare it
   and a 40 GB virtual disk. Allow additional host storage for snapshots and
   test videos; Metadata Pro creates full video backups when saving.
3. Install Xubuntu onto the VM's virtual disk, with a normal user such as
   `vlctest`. The installer's erase-disk choice applies to that virtual disk.
4. Finish installation and restart. Eject the ISO in Boxes' device settings
   if the installer boots again. Confirm the installed desktop boots normally.
5. Keep test media inside the guest disk. VM snapshots do not undo changes to
   host shared folders, USB disks, or other external storage.

For all snapshots below, shut down Xubuntu normally first and wait until Boxes
shows it stopped. In Boxes, right-click the VM, open **Properties** (called
**Preferences** in newer versions), then **Snapshots**, and click **+**.
Rename the snapshot using its menu. See [GNOME's snapshot instructions](https://help.gnome.org/gnome-boxes/snapshot-create.html).

Optionally save `00-installed-from-ISO` before updating if you also want to
reproduce the original installation media's package versions.

## 2. Prepare the clean OS baseline

In a terminal inside Xubuntu:

```sh
sudo apt update
sudo apt upgrade
sudo apt install spice-vdagent
sudo reboot
```

Wait for package operations to finish successfully. If an operation fails,
resolve it before calling the image ready. Decline any offer to upgrade to a
different Ubuntu release. This produces an updated 20.04 installation, not
the exact original 20.04.3 package set.

Check whether the installation already includes VLC:

```sh
command -v vlc
dpkg-query -W -f='${Package} ${Status} ${Version}\n' vlc
snap list vlc
```

Missing-package messages are expected when VLC is absent. If APT VLC is
installed, remove it with `sudo apt purge vlc`. If Snap VLC is installed,
remove it with `sudo snap remove --purge vlc`. Only run those removal commands
inside this disposable guest. Do not launch or install either extension yet.

Save a package record:

```sh
mkdir -p ~/test-records ~/installers ~/Videos/vlc-test
cat /etc/os-release > ~/test-records/os-release.txt
uname -a > ~/test-records/kernel.txt
dpkg-query -W > ~/test-records/packages-clean-os.txt
```

Shut down and create **`01-clean-os-no-vlc`**. This is the baseline for testing
the complete VLC and add-in installation process. Keep it for all later attempts.

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

## 4. Install and check APT VLC

Boot from the clean OS state and run inside the guest:

```sh
sudo apt update
sudo apt install vlc python3 python3-mutagen mkvtoolnix
/usr/bin/vlc --version
python3 -c 'import sys, mutagen; print(sys.version); print(mutagen.version_string)'
mkvextract --version
mkvpropedit --version
mkvinfo --version
```

Confirm VLC reports version 3. Record the actual dependency versions rather
than assuming they match the development host. Metadata Pro documents Mutagen
1.44.0 as its tested baseline; this test deliberately uses the guest's APT packages.

Launch `/usr/bin/vlc`, complete its first-run prompt, and try playing both test
videos. Confirm picture and sound work before installing add-ins. Fully quit VLC.
Neither **Metadata Pro** nor **Super Playlist** should appear in its View menu yet.

```sh
dpkg-query -W vlc python3 python3-mutagen mkvtoolnix > ~/test-records/apt-runtime.txt
```

Shut down and create **`02-apt-vlc-ready-no-addins`**. You can include the
uninstalled packages and untouched media copies in this snapshot to save time.
Use snapshot 01 when testing VLC installation itself; use snapshot 02 when
testing add-in installation.

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
Launch VLC explicitly with `/usr/bin/vlc` to avoid confusing APT and Snap builds.

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
2. Shut down Xubuntu normally.
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

## 7. Optional Snap testing

Start again from **01-clean-os-no-vlc**, keeping this separate from APT tests:

```sh
sudo apt update
sudo apt install snapd python3
sudo snap install vlc
snap run vlc
```

Close VLC after its first launch. Transfer the installer packages, then follow
Metadata Pro's packaged `docs/snap-installation.md` for runtime preparation and
checks inside Snap confinement. In that document, “host” means this Xubuntu
guest outside Snap, not your real Ubuntu computer.

This route requires a compatible staged MKVToolNix runtime and a working Python
launcher inside confinement. Neither project bundles or downloads that complete
runtime. Installing the APT dependencies alone does not satisfy it. Include
`mkvextract`, `mkvpropedit`, and `mkvinfo` and verify all dependency checks before
installing the extensions. Then install Super Playlist with:

```sh
cd ~/installers/super-playlist
python3 install.py --snap
```

Use `snap run vlc` for these tests and record `snap list vlc` and
`snap connections vlc`. Save a separately named Snap snapshot only after its
runtime checks succeed. The clean OS snapshot remains the reusable starting point.
