# uninstall_shmem4py.sh — User Guide

## Overview

`uninstall_shmem4py.sh` fully removes the shmem4py stack installed by
`install_shmem4py.sh`. It cleans every file and directory the installer
created, patches `~/.bashrc` back to its original state, and makes a
backup of `~/.bashrc` before touching it.

The script is safe to run even if the original install was only partially
completed — any item that is already absent is silently skipped.

---

## What Gets Removed

| Item | Path | Description |
|---|---|---|
| Local install prefix | `$HOME/local` | All compiled binaries, libraries, and headers (oshcc, oshrun, libshmem.so, libucx*.so, etc.) |
| Build workspace | `$HOME/shmem-build` | Downloaded tarballs and compiled source trees (~1–3 GB; safe to delete independently) |
| Python venv | `$HOME/shmem-venv` | Virtual environment containing shmem4py, numpy, and cython |
| Environment file | `~/.shmemrc` | All exported environment variables for the stack |
| Install log | `$HOME/shmem-install.log` | Log written by `install_shmem4py.sh` |
| `~/.bashrc` entry | 2 lines | The marker comment and `source ~/.shmemrc` line added by the installer |

The uninstall log itself (`$HOME/shmem-uninstall.log`) is the only file left
behind after a successful run, so you have a record of what was removed.

---

## Usage

**Make the script executable (first time only):**

```bash
chmod +x uninstall_shmem4py.sh
```

**Interactive mode (default) — confirms before deleting:**

```bash
./uninstall_shmem4py.sh
```

You will see an inventory of everything that will be removed, then a
`Proceed? [y/N]` prompt. Type `y` or `yes` to continue; anything else
aborts with no changes made.

**Force mode — skips the confirmation prompt:**

```bash
./uninstall_shmem4py.sh --force
```

Useful in scripts or automated environments where interactive input is not
possible.

**Dry-run mode — shows what would be removed without deleting anything:**

```bash
./uninstall_shmem4py.sh --dry-run
```

Prints a `[DRY-RUN] Would remove:` line for each item and then exits. No
files are modified. Use this to verify the script will do what you expect
before committing.

---

## Understanding the Output

The script uses the same colour-coded output prefixes as the installer:

| Prefix | Colour | Meaning |
|---|---|---|
| `[INFO]` | Blue | An action is in progress |
| `[DONE]` | Green | An item was successfully removed |
| `[SKIP]` | Yellow | An item was not found — already absent |
| `[DRY-RUN]` | Yellow | What would be removed (dry-run mode only) |
| `[ERROR]` | Red | Something went wrong |

A typical successful run looks like this:

```
━━━  Inventory  ━━━

Will be removed:
  • Local install prefix  ($HOME/local)
  • Build workspace       ($HOME/shmem-build)
  • Python venv           ($HOME/shmem-venv)
  • ~/.shmemrc            ($HOME/.shmemrc)
  • Install log           ($HOME/shmem-install.log)
  • ~/.bashrc entry       (2-line sourcing block)

This will permanently delete the items listed above.
Proceed? [y/N] y

━━━  Step 1 · Deactivating venv  ━━━
[SKIP]  venv not currently active — skipping deactivation

━━━  Step 2 · Python venv ($HOME/shmem-venv)  ━━━
[DONE]  Removed Python venv ($HOME/shmem-venv)

━━━  Step 3 · Local install prefix ($HOME/local)  ━━━
[DONE]  Removed local install prefix ($HOME/local)

━━━  Step 4 · Build workspace ($HOME/shmem-build)  ━━━
[DONE]  Removed build workspace ($HOME/shmem-build)

━━━  Step 5 · Environment file (~/.shmemrc)  ━━━
[DONE]  Removed ~/.shmemrc ($HOME/.shmemrc)

━━━  Step 6 · Install log ($HOME/shmem-install.log)  ━━━
[DONE]  Removed install log ($HOME/shmem-install.log)

━━━  Step 7 · ~/.bashrc cleanup  ━━━
[INFO]  Backed up ~/.bashrc to $HOME/.bashrc.shmem-uninstall-backup
[DONE]  shmem4py block removed from ~/.bashrc

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Uninstall Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Log written to : $HOME/shmem-uninstall.log

  Uninstall complete.

  Open a new shell (or run source ~/.bashrc) to ensure
  all removed paths are cleared from your current session.

  To reinstall at any time, run ./install_shmem4py.sh.
```

---

## The ~/.bashrc Backup

Before modifying `~/.bashrc`, the script creates a backup at:

```
~/.bashrc.shmem-uninstall-backup
```

This backup is kept after the script finishes. Once you have confirmed your
`~/.bashrc` looks correct, you can safely delete it:

```bash
rm ~/.bashrc.shmem-uninstall-backup
```

If the automatic `~/.bashrc` edit fails for any reason, the script prints the
exact two lines to remove manually and tells you where the backup is:

```
# shmem4py stack — added by install_shmem4py.sh
[[ -f "$HOME/.shmemrc" ]] && source "$HOME/.shmemrc"
```

---

## Partial Installs

The script handles partial installs gracefully. If `install_shmem4py.sh` was
interrupted partway through, some items will be present and some absent.
Items not found are reported as `[SKIP]` and counted as already clean — the
script continues through all remaining steps rather than stopping.

---

## After Uninstalling

Open a new shell or reload your environment so that the removed paths are
cleared from the current session:

```bash
source ~/.bashrc
```

Verify the stack is gone:

```bash
# All of these should return "command not found"
oshcc --version
oshrun --version
ucx_info -v

# This should fail with ModuleNotFoundError
python3 -c "import shmem4py"
```

---

## Reinstalling

The uninstall script leaves your system in a clean state. To reinstall the
full stack from scratch:

```bash
./install_shmem4py.sh
```

---

## Troubleshooting

**`~/.bashrc` still sources `.shmemrc` after uninstall**
The automatic sed edit may not have matched your `~/.bashrc` formatting. Open
`~/.bashrc` in a text editor and manually delete the two lines:
```
# shmem4py stack — added by install_shmem4py.sh
[[ -f "$HOME/.shmemrc" ]] && source "$HOME/.shmemrc"
```
Your backup is at `~/.bashrc.shmem-uninstall-backup` if you need to compare.

**Commands like `oshcc` still resolve after uninstall**
Your current shell session still has the old `PATH` set from before the
uninstall. Open a new terminal or run `source ~/.bashrc` — the paths will
no longer resolve once `$HOME/local/bin` is gone.

**The venv is still active in the current shell**
Run `deactivate` manually, then `source ~/.bashrc` to reload the clean
environment.

**You only want to remove the build workspace to free disk space**
The build workspace is safe to delete independently at any time after a
successful install — the compiled outputs in `$HOME/local` are fully
self-contained:
```bash
rm -rf "$HOME/shmem-build"
```
