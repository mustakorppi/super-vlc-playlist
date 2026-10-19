# Super Playlist for VLC

Filter the **current VLC playlist** by wildcard title, genre, album, artist,
and duration. Designed for Linux VLC 3, including the VLC Snap installation
used with Video Metadata Pro. Media files are never modified.

[Installation](#fresh-installation)

## License

Super Playlist is licensed under the GNU General Public License version 2 only
(`GPL-2.0-only`). See [LICENSE](LICENSE) for the complete license text.
See [COPYRIGHT.md](COPYRIGHT.md) for copyright attribution and the scope of
these notices, including AI-generated material. Third-party dependencies
retain their own licenses.


## Use

Open **View → Super Playlist** (or **View → Super Playlist → Show editor**
when VLC displays a submenu); the window header is **Π Super Playlist**. The version and build date appear
at the top right inside the main dialog.
The dialog groups playlist loading, filters, results, and presets in order.
Playback, queue, shuffle, reset, and settings buttons include small text symbols;
their appearance depends on your system font. Click **Help** for title wildcard,
metadata selection, and duration syntax tips in the status panel.
Status messages, warnings, file paths, and metadata details share a scrollable
panel so their length does not enlarge the window. Scroll to read longer text;
you can also resize the window yourself. VLC 3 may reset a manually chosen size
when updating extension widgets; its Lua API does not expose size persistence.

Use **Hide editor** in the **View → Super Playlist** submenu to hide the window
while keeping filters, results, selections, and unsaved input. **Show editor**
shows the same dialog again, including an open preset or export naming dialog.
Hiding does not cancel a pending helper job; use **Check status** after returning
if needed. Closing the main window still ends the editor session.
If the window is covered by VLC, choose **Hide editor**, then reopen the submenu
and choose **Show editor**. Show alone does not reliably bring a covered window
forward, and these actions may not restore a minimized window.

1. Put media in VLC's normal playlist. Open **View → Super Playlist**.
2. Click **Load playlist**; the list refreshes automatically when the scan finishes
   within one second. For a longer scan, click **Check status** to collect results.
3. Enter a title search, select metadata values, and/or enter duration ranges.
4. Click **Apply filters**; results refresh automatically. **Reset filters** also
   restores the full list immediately.
5. Select results to play or queue, or export all matches.

Use Ctrl-click or Shift-click to select multiple values in a list. Ctrl-click
a selected value to deselect it. No selection means no restriction. Selections
in different fields combine with **AND**. Within each field, selections match
**ANY**, unless **Require ALL selected** is checked. Matching is case-insensitive,
including Unicode text. **(Unknown / missing)** matches an empty metadata field.

Filter columns appear in Artist, Album, Genre order. Each result row shows its
duration and title followed by Artist, Album, and Genre, including all values.

The source is a snapshot, including entries in nested playlist folders. Filters
always operate on that snapshot. **Reset filters** restores all captured items.
**Load playlist** captures the current VLC playlist again and resets the filters.
It also refreshes metadata for local files whose size or modification time changed.

### Title wildcards

| Input | Meaning |
| --- | --- |
| `live` | Title contains `live` |
| `live*` | Title starts with `live` |
| `*concert*` | Title contains `concert` |
| `Episode 0?` | `Episode 0` followed by exactly one character |

Wildcard patterns match the whole title; use surrounding `*` for substring
matching. Only `*` and `?` are special; brackets and other punctuation are literal.
Titles fall back to VLC's playlist display name when no embedded title is available.

Enter one pattern in the title box. To use multiple patterns, click **Add title
pattern** after each. All added patterns are active and combine with **OR**; the
current text box also participates when applying filters. Select patterns and
click **Remove selected patterns** to remove them. VLC's text widget is single-line,
so the MVP uses the Add button rather than multiline entry.

### Duration

Enter an inclusive range such as `03:00-08:00`. Bounds accept seconds, `mm:ss`,
or `hh:mm:ss`. Examples:

- `-05:00`: at most five minutes.
- `01:00:00-`: at least one hour.
- `03:00-08:00; 12:00-15:00`: either range.
- Empty: any duration, including unknown.

When ranges are active, unknown durations are excluded unless **Include unknown
duration** is checked. Invalid ranges show an error and clear the old results.

### Playback and export

- **Play selected** plays exactly one selected result. If its original playlist
  entry still exists, VLC jumps to it. Otherwise it adds and plays that item.
  Subsequent playback follows VLC's current playlist, not the filtered results.
- **Queue selected** and **Queue all matches** append items in displayed order without
  stopping playback. Appending can create duplicates in VLC's playlist.
  Title, duration, artist, album, and genre are passed to the new VLC entries.
- **Play matches instantly** appends all current matches in displayed order and
  immediately starts the first newly added entry, in one click. The existing
  playlist is kept; each click appends another copy of the matches.
  Playback follows VLC's current order and repeat/shuffle settings.
- **Details** shows the first selected result's metadata and URI.
- **Export matches** opens **Save playlist as**. Enter a playlist name and click
  **Save**; `.m3u8` is added automatically. The export contains the matches in
  displayed order. Existing files are never overwritten; choose another name.
  **Cancel** or closing the naming dialog returns to your filters and results.
  Errors stay in the naming dialog so you can correct the name and retry.
  For longer exports, click **Check status**. The completed export path appears
  in the status panel; open that file in VLC to play only the matches.
  Under **Settings**, enter an absolute **Export folder** (or `~/folder`) and
  click **Save export folder**. The folder is created and checked for access.
  This setting persists across restarts and reinstalls; the default remains
  the extension's `exports` folder. Snap VLC must have access to your chosen folder.

### Shuffle

**Shuffle results** randomizes the current matches, keeping every video's metadata
attached and using the loaded snapshot without rereading files. It leaves VLC's
existing playlist and playback untouched. Queue or export the results to use the
displayed order. Playing one selected result still follows VLC's existing playlist
after that item.

Further filtering preserves the shuffled order. **Reset filters** shows all items
in the current order; previously hidden items retain their snapshot positions.
**Restore original order** returns to the order captured by **Load playlist** while
keeping the current filters. Loading the playlist again captures a new original
order. Shuffling or restoring clears result selections so they cannot accidentally
refer to different videos.

Shuffle uses fresh randomness from Linux's `/dev/urandom`, independent of the
clock and video file timestamps. With at least two matches, a successful shuffle
always changes the current entry order. With two entries this means swapping
them; an order from an earlier shuffle can still recur. Duplicate playlist
entries may look identical even when their positions change. If the system
random source is unavailable, the extension reports an error and keeps the order.

File modification times and sizes are used only to decide whether cached metadata
needs refreshing. They never determine video order. Metadata refresh preserves
the input playlist order, and filtering preserves the relative order of matches.
**Load playlist** explicitly captures VLC's current order again; it does not keep
a previous shuffled snapshot. Super Playlist does not control sorting or shuffle
performed by VLC itself.

By default, exports are saved under `super_playlist_support/exports` beside the installed
extension. For Snap this is:

```text
~/snap/vlc/current/.local/share/vlc/lua/extensions/super_playlist_support/exports/
```

## Metadata compatibility and limits

MP4/M4V/M4A metadata is read with Mutagen, including Video Metadata Pro's private
multi-value records. Video-only MP4 duration comes from the movie header rather
than an audio track. MKV/MKA/WebM uses MKVToolNix to read repeated global tags,
packed album and genre values, title and duration. Spaces and other whitespace
separate artist, album, and genre tags; leading/trailing whitespace and empty tags
are discarded. Underscores are preserved (use `The_Band` for a single tag).
Album tags matching that item's genres are excluded from Album, ignoring case,
including genres appended by the metadata editor. These rules also apply to VLC
fallback metadata. Titles keep their spaces.

Other formats and remote URLs use metadata already available in VLC. The helper
does not download or probe remote URLs. Unavailable metadata is shown as missing;
unreadable local files produce warnings and retain VLC's fallback values.

The helper runs in the background. **Load playlist** and **Apply filters**
automatically collect results, waiting up to one second; if a helper takes longer,
the dialog asks you to use
**Check status**. **Reset filters** can abandon a pending filter and immediately
restore the full source snapshot. Filter edits made while a job is running apply
only on the next **Apply filters**. **Cancel** abandons the
pending result; a local metadata subprocess may take up to its 30-second timeout
to exit. Closing the dialog cancels collection without affecting playback.

Successful collected jobs are removed. Cancelled jobs retain small diagnostic
files under `super_playlist_support/jobs`; these can be removed with VLC closed.
The metadata cache is `super_playlist_support/cache.json`. Delete it with the
extension closed to force a complete reread.

### Preset folder setting

Click **Settings** to reveal the preset-folder field, then **Save folder** to
validate and remember the location. The default is `~/Super Playlist Presets`.
Enter an absolute path or a path beginning with `~/`; `~` refers to the home
directory of the user who installed the plugin, including for Snap installs.
Missing folders are created when saved. The helper checks directory listing and
file creation using the same runtime as the plugin, so inaccessible folders
produce an error without replacing the previous setting.

The location is stored in `super_playlist_support/settings.json` and survives
restarting VLC and reinstalling/updating the plugin in the same location.
Changing it does not move or delete files in the previous folder. Opening or
saving settings preserves the current filters and results. If the helper takes
longer to finish, use **Check status** as with other operations.

### Saving and loading filter presets

1. Set the filters and click **Save preset as…**. Enter the name in the save
   dialog and click **Save**. You do not need to apply the filters first.
   Invalid names or duration ranges are reported in the save dialog.
2. If that name already exists, a **Replace preset?** dialog offers **Replace
   preset**, **Change name**, and **Cancel**. Saving or cancelling returns to the
   main view with the filters, results, and ordering preserved. Closing the save
   dialog also returns to the main view. VLC supports one dialog per extension,
   so the name dialog temporarily replaces the main view. Metadata criteria are
   restored with **[active]** markers; result-row highlights are cleared.
3. Load the playlist, choose a name from the preset dropdown, and click
   **Load and apply preset**. Loading uses only the selector; there is no name
   input in the main view.
   The saved filters are restored and applied automatically, refreshing the
   results. If a job takes longer, use **Check status**; no separate apply is
   needed. You can still edit the restored controls and click **Apply filters**
   to apply your edits.

Presets preserve added title patterns, text still in the title box, artist/album/
genre criteria and their ALL switches, duration ranges, and the unknown-duration
checkbox. Playlist contents and shuffled order are not stored. **Load playlist**
and **Reset filters** still clear filters, so load the playlist before the preset.

VLC 3 cannot programmatically highlight list selections. Restored metadata values
therefore carry an **[active]** marker; both marked values and highlighted values
are used by **Apply filters** and **Save preset as…**. To remove restored criteria,
highlight them and use the corresponding **Remove selected … criteria** button.
Removing artist, album, or genre criteria automatically reapplies the current
filters and refreshes the results. For longer jobs, click **Check status**.
Ctrl/Shift still lets you highlight multiple values. An active value absent from
the snapshot is marked **[not in playlist]** and remains a filter condition.

Each preset is a readable, versioned UTF-8 `.json` file in the configured folder.
The default folder is created on the first save if necessary. Names can contain
spaces and Unicode, but not path separators, control characters, leading/trailing
spaces, or more than 180 UTF-8 bytes. Files can be renamed, copied, or deleted in
the file manager; click **Refresh presets** afterward. The list also refreshes
when opening the plugin, saving/loading a preset, or changing the preset folder.
Damaged or unsupported presets report an error without changing the filters.
Writes are atomic; an unsuccessful replacement preserves the previous preset.
Save operations cannot be cancelled once started; use **Check status** if needed.

This MVP does not include folder scanning, searchable metadata choice lists,
sorting controls, or automatic replacement of VLC's playlist

## Fresh installation


These instructions are for **Linux with VLC 3**. Choose **one** installation
path below, matching the VLC application you actually use. Installing both the
APT and Snap versions of VLC is not necessary.

### What you need (and what you do not)

| Component | Regular Linux VLC | Snap VLC |
| --- | --- | --- |
| VLC 3 | Required | Required; launch it once before setup |
| Python 3 | Required to install and run the helper | Host Python 3 runs the installer; the shared runtime runs the helper |
| Mutagen | Install for MP4/M4V/M4A metadata | Supplied by the shared runtime |
| MKVToolNix (`mkvextract`, `mkvinfo`) | Install for MKV/MKA/WebM metadata | Supplied by the shared runtime |
| Video Metadata Pro | **Not required** | Its installed **Snap runtime is required** by the current installer |
| Git | Only needed to clone or pull this repository; a downloaded ZIP also works | Same |
| GitHub CLI (`gh`) | **Not required** | **Not required** |
| FFmpeg and Lua 5.2 library | Only needed for the full automated test suite | Only needed for tests, not normal use |

Super Playlist reads existing metadata; you do not need to run a metadata editor
alongside it. Missing metadata stays missing unless VLC supplies a fallback.
The regular-VLC commands below install both metadata readers so all supported
local formats can be read.

### 1. Get the Super Playlist source

Clone the repository and enter its directory:

```sh
git clone https://github.com/mustakorppi/super-vlc-playlist.git
cd super-vlc-playlist
```

No GitHub account or authentication is needed to clone this public repository.
Alternatively, download the ZIP from GitHub, extract it, and open a terminal
in the extracted directory.

**Already have this project on your computer?** Use that directory; do not clone
it again. Run every installation command below from the directory containing
`install.py` and `requirements.txt`.

### 2A. Regular Linux VLC (Ubuntu/Debian APT installation)

Use this path if you run the regular system VLC application, not Snap VLC.
On a fresh Ubuntu/Debian installation:

```sh
sudo apt update
sudo apt install vlc python3 python3-mutagen mkvtoolnix
python3 install.py
```

Only the APT commands use `sudo`. Run `install.py` as your normal user so the
extension is installed for your VLC account.

This path does **not** require Video Metadata Pro, its repository, its Snap
runtime, `pip`, or a virtual environment. Installing `python3-mutagen` supplies
the Python dependency; you do not also need to install `requirements.txt`.

By default, the extension is installed at:

```text
~/.local/share/vlc/lua/extensions/super_playlist.lua
```

If `XDG_DATA_HOME` is set, the installer uses `$XDG_DATA_HOME/vlc` instead of
`~/.local/share/vlc`.

### 2B. Snap VLC

Use this path if the VLC application you run is installed with Snap. You can
check with `snap list vlc` (having Snap VLC installed does not mean you are using
it if a regular VLC installation is also present).

1. If needed, install Snap VLC with `sudo snap install vlc` and host Python 3
   with `sudo apt install python3`.
2. Launch Snap VLC once with `snap run vlc`, then close it.
3. Install **Video Metadata Pro's Snap runtime** using that project's installation
   instructions. Video Metadata Pro is maintained separately; this repository
   does not install or bundle that runtime.
   Include `mkvinfo` as well as `mkvextract` and `mkvpropedit` in the staged runtime;
   Super Playlist uses `mkvinfo` to read MKV titles and durations.
4. From the Super Playlist source directory, run:

   ```sh
   python3 install.py --snap
   ```

**On a fresh machine, step 3 is required.** The `--snap` option does not download
Python, Mutagen, or MKVToolNix. It checks for and reuses these existing files:

```text
~/snap/vlc/common/video-metadata-runtime/python-launcher
~/snap/vlc/common/video-metadata-runtime/python/mutagen/__init__.py
~/snap/vlc/common/video-metadata-runtime/mkvtoolnix/usr/bin/mkvextract
~/snap/vlc/common/video-metadata-runtime/mkvtoolnix/usr/bin/mkvinfo
```

If you already use Video Metadata Pro with this runtime, skip its installation
and run step 4. Keep the runtime directory installed while using Super Playlist;
the metadata editor does not need to be open. Installing Mutagen and MKVToolNix
only on the host does not replace this Snap runtime requirement.

The Snap extension is installed at:

```text
~/snap/vlc/current/.local/share/vlc/lua/extensions/super_playlist.lua
```

### 3. Open and check the extension

1. Fully quit and reopen the VLC installation you chose above.
2. Add media files to VLC's normal playlist.
3. Select **View → Super Playlist**.
4. Click **Load playlist**. If the scan takes more than one second, click
   **Check status** to collect the results.
5. Confirm the files appear, then try a title filter. Artist, album, and genre
   choices depend on the metadata in your files.

There is no separate server to start. VLC starts the Python helper as needed.
The installer copies the extension and helper into VLC's user data directory;
you do not run VLC from the source directory.

### Optional: use a virtual environment with regular VLC

Skip this section if you used the APT dependencies in step 2A. If you prefer an
isolated Python environment, use this **alternative** on Ubuntu/Debian:

```sh
sudo apt install vlc python3 python3-venv mkvtoolnix
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python install.py
```

The installer records the Python interpreter used to run it. Keep `.venv` at
that location after installation; VLC will use it without requiring activation.
`requirements.txt` installs Mutagen only, not VLC or MKVToolNix.

For an existing environment, `--python /absolute/path/to/python` explicitly
selects the interpreter VLC will use. That interpreter must have Mutagen installed.
`--data-dir /path/to/vlc` selects a custom VLC data directory for regular VLC.
Neither option is needed for the standard instructions above. With `--snap`,
the installer always selects the shared runtime launcher, and `--data-dir` is
not allowed.

### Updating

Keep your source checkout for future updates. Close VLC, then, if you obtained
the source with Git, run `git pull` in that checkout. For a ZIP installation,
download and extract the new version instead. Run the same installation command
you originally used:

- Regular VLC: `python3 install.py`
- Regular VLC with the virtual environment: `.venv/bin/python install.py`
- Snap VLC: `python3 install.py --snap`

Restart VLC. Pulling or downloading source alone does not update the installed
extension. You do not need to reinstall all system packages for each update.
The installer preserves existing cache, jobs, and exports.

### Installation troubleshooting

| Symptom | What to check |
| --- | --- |
| Super Playlist is absent from the View menu | Fully restart VLC. Confirm you installed for the VLC application you opened: regular VLC and Snap VLC use different directories. |
| `Install Video Metadata Pro for Snap first` | Complete step 2B's runtime setup; `--snap` cannot create that runtime. |
| `Launch Snap VLC once before installing` | Run `snap run vlc`, close it, and retry the installer. |
| MP4 metadata is missing or a Mutagen import fails | For regular VLC, install Mutagen for the interpreter selected during installation. For Snap, check the shared runtime. |
| MKV metadata cannot be read | For regular VLC, check that `mkvextract` and `mkvinfo` are installed and available on `PATH`. For Snap, check the shared runtime. |
| Helper fails after moving or deleting a virtual environment | Recreate the environment, install `requirements.txt`, and rerun the installer with its Python. |

## Development and tests (optional)

### Version and build date

[release.json](release.json) is the single source for the application version and
build date. Update it when preparing a release, then package and reinstall:

```json
{
  "version": "00.90 RC1",
  "build_date": "2026-10-19"
}
```

The build date identifies the prepared release, not the installation date. Use
`YYYY-MM-DD`; packaging and installation preserve it. The installer embeds both
values in the extension, including the version reported to VLC. Restart VLC after
reinstalling to see the new values. Editing this file alone does not update an
already installed extension.

Versions support two or three numeric components and an optional release-candidate
suffix, such as `00.90 RC1`. Increase the candidate number for each testing release
(`00.90 RC2`, etc.) and remove the suffix for the final release (`00.90`).
Leading zeroes are preserved exactly as written.

### Create a minimal installation package

From the source checkout, run:

```sh
python3 package.py /tmp/super-playlist-release
```

The destination must not already exist; its parent directories are created as
needed. The script copies only an explicit list of runtime files, `install.py`,
`requirements.txt`, release metadata, documentation, and license notices. Git history, tests, Python caches, virtual
environments, and local settings are excluded. It can be run from any working
directory by using the path to `package.py`.

Copy or archive the resulting folder for distribution. On the receiving machine,
install the dependencies described under **Fresh installation**, then run
`python3 install.py` (regular VLC) or `python3 install.py --snap` from that folder.
The package does not bundle Python, VLC, Mutagen, MKVToolNix, or the shared Snap
runtime. The packaging script itself is only needed in the source checkout.

### Run tests

**Skip this section for normal use.** Run tests from the source directory.
For the full test suite with regular system Python on Ubuntu/Debian:

```sh
sudo apt install python3 python3-mutagen ffmpeg mkvtoolnix liblua5.2-0
```

```sh
python3 -m unittest discover -s tests -v
```

Tests cover matching rules, wildcard punctuation and Unicode, duration validation,
wire encoding, real MP4/MKV reads, read-only behavior, cache invalidation, and Lua
dialog workflows using a VLC stub with real background helper jobs. Real-media
tests require FFmpeg and MKVToolNix; Lua tests require `liblua5.2`.

Manual VLC check: load a playlist with tagged MP4/MKV files, combine filters,
confirm Ctrl/Shift selection, queue while playing, export/open an M3U8, and use
Video Metadata Pro alongside Super Playlist. Automated dialog tests do not
establish that the actual Qt layout and focus behavior are correct.

Implementation references: [VLC 3 Lua API](https://github.com/videolan/vlc/blob/3.0.x/share/lua/README.txt)
and the separate Video Metadata Pro project's metadata conventions.

## Install to virtual machines, experimental
For repeatable installation trials of both projects in GNOME Boxes, use the
guide for your guest distribution:

- [Xubuntu 20.04 (APT VLC)](docs/xubuntu-boxes-test-image.md)
- [Fedora Workstation (RPM VLC)](docs/fedora-boxes-test-image.md)
- [Arch Linux (pacman VLC)](docs/arch-boxes-test-image.md)

These guides cover clean snapshots, installer transfer, dependency checks, and
manual testing. They describe test procedures rather than verified compatibility.

