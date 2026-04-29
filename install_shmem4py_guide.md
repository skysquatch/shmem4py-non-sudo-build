# install_shmem4py.sh — User Guide

## Overview

`install_shmem4py.sh` is a self-contained bash script that builds and installs
the complete shmem4py software stack on a Linux machine **without requiring
sudo or root access**. It downloads, compiles, and links every dependency from
source, places everything under `$HOME/local`, and validates the result with
four automated tests.

Running the script a second time is safe — each component is skipped if it is
already present.

---

## What the Script Installs

The full dependency chain, built in order:

| Component | Version | Purpose |
|---|---|---|
| autoconf | 2.71 | Build-system generator (if missing) |
| automake | 1.16.5 | Makefile generator (if missing) |
| libtool | 2.4.7 | Shared-library build helper (if missing) |
| UCX | 1.17.0 | High-performance network transport |
| libevent | 2.1.12 | Event-loop library (required by PMIx/PRRTE) |
| hwloc | 2.11.2 | Hardware topology library (required by PMIx/PRRTE) |
| PMIx | 4.2.9 | Process management interface |
| PRRTE | 3.0.5 | Process launcher (`oshrun`) |
| Sandia OpenSHMEM (SOS) | 1.5.3 | OpenSHMEM runtime (`oshcc`, `shmem.h`) |
| shmem4py | latest | Python bindings for OpenSHMEM |
| Python venv | — | Isolated Python environment at `$HOME/shmem-venv` |

Everything except the venv installs into `$HOME/local`.

---

## Hard Requirements

These tools **must already be present** on the system. The script cannot install
them and will exit immediately if any are missing:

| Tool | Minimum | How to check |
|---|---|---|
| `gcc` / `g++` | GCC 7+ (GCC 13 confirmed) | `gcc --version` |
| `make` | any | `make --version` |
| `git` | any | `git --version` |
| `python3` | 3.8+ | `python3 --version` |
| `wget` or `curl` | any | `wget --version \|\| curl --version` |

If `autoconf`, `automake`, or `libtool` are missing they will be built
automatically from source — they are **not** hard requirements.

Disk space: at least **5 GB free** in `$HOME`. The script checks this at
startup and exits if the requirement is not met.

---

## Getting Started

**1. Download the script**

Place `install_shmem4py.sh` in any directory you have write access to, for
example your home directory:

```bash
cd ~
# copy or transfer install_shmem4py.sh here
```

**2. Make it executable**

```bash
chmod +x install_shmem4py.sh
```

**3. Run it**

```bash
./install_shmem4py.sh
```

The script runs for roughly **60–90 minutes** depending on machine speed,
with most of the time spent compiling UCX, PMIx, PRRTE, and SOS.

**4. Activate the environment in new shells**

The script writes a block to `~/.bashrc` automatically. After the install
finishes, either open a new terminal or run:

```bash
source ~/.bashrc
```

You are then ready to run shmem4py programs with:

```bash
oshrun -np <N> python your_script.py
```

---

## Usage Modes

```
./install_shmem4py.sh              Full install + tests (default)
./install_shmem4py.sh --test-only  Skip all build steps; run tests only
```

`--test-only` is useful for checking an existing installation after a machine
reboot or environment change without waiting for a full rebuild.

---

## Understanding the Output

The script uses colour-coded prefixes for every line of terminal output:

| Prefix | Colour | Meaning |
|---|---|---|
| `[INFO]` | Blue | An action is in progress |
| `[DONE]` | Green | A step completed successfully |
| `[SKIP]` | Yellow | A component was already found; step was skipped |
| `[ERROR]` | Red | A fatal problem occurred |

Section boundaries are printed as bold horizontal rules:
```
━━━  Step 5 · UCX 1.17.0  ━━━
```

A typical successful run looks like this:

```
━━━  Step 0 · Preflight checks  ━━━
[DONE]  C compiler (gcc): /usr/bin/gcc
[DONE]  C++ compiler (g++): /usr/bin/g++
[DONE]  make: /usr/bin/make
[DONE]  git: /usr/bin/git
[DONE]  Python 3: /usr/bin/python3
[DONE]  Disk space: ~120 GB free in $HOME
[DONE]  Python version: Python 3.11.4

━━━  Step 1 · Directories and environment  ━━━
[DONE]  Local prefix: /home/you/local
[DONE]  Build workspace: /home/you/shmem-build
[DONE]  ~/.shmemrc written
[DONE]  ~/.bashrc updated to source ~/.shmemrc

━━━  Step 2 · Python virtual environment  ━━━
[INFO]  Creating venv at /home/you/shmem-venv…
[DONE]  venv ready: Python 3.11.4

━━━  Step 3 · GNU autotools  ━━━
[SKIP]  autoconf already installed (/usr/bin/autoconf) — skipping
[SKIP]  automake already installed (/usr/bin/automake) — skipping
[SKIP]  libtool already installed (/usr/bin/libtool) — skipping

...

━━━  Step 12 · Validation tests  ━━━
[INFO]  Running: C OpenSHMEM hello world (4 PEs)…
[DONE]  PASSED — C OpenSHMEM hello world (4 PEs)
[INFO]  Running: shmem4py hello world (4 PEs)…
[DONE]  PASSED — shmem4py hello world (4 PEs)
[INFO]  Running: shmem4py broadcast (4 PEs)…
[DONE]  PASSED — shmem4py broadcast (4 PEs)
[INFO]  Running: shmem4py put/get (4 PEs)…
[DONE]  PASSED — shmem4py put/get (4 PEs)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Install + Test Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Tests passed : 4
  Tests failed : 0
  Full log     : /home/you/shmem-install.log

  All done! shmem4py is ready to use.

  Start a new shell (or run source ~/.bashrc) to activate
  the environment, then run your programs with:

    oshrun -np <N> python your_script.py
```

---

## What the Script Changes on Your System

**Files created under `$HOME/local/`:**
```
bin/    oshcc, oshrun, oshc++, ucx_info, prterun, pmix_info,
        lstopo, libtool, autoconf, automake, gxx-wrapper
include/ shmem.h, ucx/, pmix.h, hwloc.h, event.h, …
lib/    libshmem.so, libucx*.so, libpmix.so,
        libhwloc.so, libevent*.so, …
share/  man pages and documentation
```

**`$HOME/shmem-venv/`** — Python virtual environment containing shmem4py,
numpy, cython, and their dependencies.

**`$HOME/shmem-build/`** — Build workspace containing downloaded tarballs and
compiled source trees. This directory is safe to delete after a successful
install to reclaim disk space (~3–4 GB).

**`$HOME/shmem-install.log`** — Full log of every command run and its output.
The script keeps the terminal quiet: only the coloured status lines (`[INFO]`,
`[DONE]`, `[SKIP]`, `[ERROR]`, and section headers) appear on screen. All
output from `./configure`, `make`, `pip`, `git clone`, and other noisy
commands is sent exclusively to the log file. If a step fails, the log
contains the full compiler or build output needed to diagnose the problem.

**`~/.shmemrc`** — Contains all environment variables for the shmem4py stack.
Written fresh on every run (using `>`, not `>>`), so it is always up to date
and never accumulates duplicate entries. Contents:

```bash
# ~/.shmemrc — shmem4py environment (generated by install_shmem4py.sh)
export LOCAL_PREFIX="$HOME/local"
export PATH="$LOCAL_PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="..."
export PKG_CONFIG_PATH="..."
export LDFLAGS="-L$LOCAL_PREFIX/lib"
export CPPFLAGS="-I$LOCAL_PREFIX/include"
export SHMEM_HOME / OSHCC / OSHCXX / OSHRUN / UCX_TLS / SHMEM_SYMMETRIC_SIZE
source "$HOME/shmem-venv/bin/activate"
```

You can activate the environment manually in any shell at any time with:
```bash
source ~/.shmemrc
```

**`~/.bashrc`** — A single line is appended (only once, guarded by a marker
comment):
```bash
# shmem4py stack
[[ -f "$HOME/.shmemrc" ]] && source "$HOME/.shmemrc"
```

This keeps `~/.bashrc` clean. All the actual settings live in `~/.shmemrc`
and can be edited, inspected, or sourced independently.

---

## Idempotency — Re-running the Script

Every component is skipped if its sentinel binary is already found on `PATH`:

| Component | Sentinel checked |
|---|---|
| autoconf | `autoconf` |
| automake | `automake` |
| libtool | `libtool` |
| UCX | `ucx_info` |
| libevent | `$HOME/local/lib/libevent-*.so` |
| hwloc | `lstopo` |
| PMIx | `pmix_info` |
| PRRTE | `prterun` |
| SOS | `oshcc` |
| shmem4py | `python -c "import shmem4py"` |
| Python venv | `$HOME/shmem-venv/bin/activate` |

This means you can safely re-run the script after a partial failure — it will
pick up from the first component that is missing and skip everything that
already succeeded.

**To force a component to rebuild**, remove its sentinel binary first. For
example, to force SOS to rebuild:

```bash
rm "$HOME/local/bin/oshcc"
./install_shmem4py.sh
```

---

## The Validation Tests

Step 12 always runs, even with `--test-only`. Four tests are executed:

**Test 1 — C OpenSHMEM hello world**
Compiles a small C program with `oshcc` and launches it with `oshrun -np 4`.
Confirms the C-level runtime is functional end-to-end.

**Test 2 — shmem4py hello world**
Runs a Python script with `oshrun -np 4` that prints each PE's rank. Confirms
the Python bindings load and that the runtime initialises correctly.

**Test 3 — Broadcast**
Each PE allocates symmetric memory and PE 0 broadcasts an array to all others.
The result is asserted with `assert` inside the script, so the test fails if
any PE receives incorrect data — not just if the process crashes.

**Test 4 — Put/Get (one-sided communication)**
Each PE reads from the next PE's symmetric buffer using `shmem.get` in a ring
pattern and asserts the received value is correct.

Tests write temporary files to `/tmp` (cleaned up automatically on completion)
and redirect their full output to the log file. The terminal shows only the
pass/fail result.

---

## Reading the Log File

Every line of terminal output and all compiler/make output is appended to
`$HOME/shmem-install.log`. Each run is separated by a timestamped header:

```
============================================================
 shmem4py installer — Tue Apr 28 14:32:01 EDT 2026
============================================================
```

When a step fails, `set -euo pipefail` causes the script to exit immediately.
To find the error:

```bash
# Show the last 100 lines of the log
tail -100 ~/shmem-install.log

# Search for error lines specifically
grep -i "error\|fatal\|failed" ~/shmem-install.log | tail -30
```

---

## Customising Version Numbers

All version strings are defined as variables at the top of the script and can
be changed before running if you need a different version of any component:

```bash
# Example: use UCX 1.16.0 instead of 1.17.0
# Open the script and edit:
UCX_VERSION="1.16.0"
```

No other changes are needed — the download URLs and directory names are
constructed from the version variables throughout the script.

---

## Uninstalling

Use the companion `uninstall_shmem4py.sh` script. It handles everything
automatically and safely.

```bash
chmod +x uninstall_shmem4py.sh
./uninstall_shmem4py.sh
```

It removes:
- `$HOME/local` — all compiled binaries and libraries
- `$HOME/shmem-build` — all downloaded tarballs and build trees
- `$HOME/shmem-venv` — the Python virtual environment
- `~/.shmemrc` — the environment file
- `$HOME/shmem-install.log` — the install log
- The two-line sourcing block in `~/.bashrc`

Before touching `~/.bashrc` the script creates a backup at
`~/.bashrc.shmem-uninstall-backup`.

**Flags:**

```
./uninstall_shmem4py.sh            # interactive — confirms before deleting
./uninstall_shmem4py.sh --force    # skip confirmation prompt
./uninstall_shmem4py.sh --dry-run  # show what would be removed, do nothing
```

See `uninstall_shmem4py_guide.md` for full details.

---

## Troubleshooting

**The script exits at preflight with "only N GB free"**
The script requires at least 5 GB free in `$HOME`. Free up space or point
`$HOME` to a filesystem with more room.

**A component fails to configure or compile**
Run with the log open in a second terminal to watch in real time:
```bash
tail -f ~/shmem-install.log
```
Find the first `error:` line — that is the root cause. Everything after it is
typically cascading noise. The component's build directory is preserved under
`$HOME/shmem-build/` so you can `cd` into it and re-run `./configure` or
`make` manually to iterate.

**"Neither wget nor curl is available"**
The script needs one of them to download sources. Contact your sysadmin to
have either tool made available, or manually download the tarballs to
`$HOME/shmem-build/` before running the script (it will extract them if the
file is already present).

**Tests fail after a successful build**
Run the test suite in isolation to get more output:
```bash
source ~/.bashrc
./install_shmem4py.sh --test-only
```
Then check the log. Common causes are `UCX_TLS` selecting a transport that is
not available on the machine (`unset UCX_TLS` to let UCX auto-detect) or
`LD_LIBRARY_PATH` not being set (`source ~/.bashrc` before running).

**`[SKIP]` on every step but tests still fail**
The environment from a previous partial install may be stale. Start a fresh
shell, run `source ~/.bashrc`, and then re-run with `--test-only`.

**You want to rebuild only one component**
Remove its sentinel binary (see the Idempotency table above), then re-run the
full script. All other components will be skipped automatically.
