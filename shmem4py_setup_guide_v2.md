# shmem4py Local Environment Setup Guide (No sudo, Python venv)

## Overview

This guide builds a complete OpenSHMEM + shmem4py stack entirely in your home
directory — no root access needed. Every fix encountered during a real install
is already incorporated here.

**Full software stack (bottom to top):**
```
shmem4py          (Python bindings)
    └── Sandia OpenSHMEM / SOS  (OpenSHMEM runtime)
            ├── UCX             (network transport layer)
            ├── PMIx            (process management interface)
            │       ├── libevent
            │       └── hwloc
            └── PRRTE           (process launcher / oshrun)
                    ├── libevent
                    └── hwloc
Python venv       (isolated Python environment)
```

**Estimated time:** 60–90 minutes (mostly compile time)

---

## 1. Preflight Checks

```bash
# C/C++ compiler — GCC 13 is confirmed working with this guide
gcc --version
g++ --version

# Build tools
make --version
autoconf --version
automake --version
libtool --version
git --version

# Python 3.8+ required for venv
python3 --version

# Check free disk space (~4–5 GB needed)
df -h ~

# Check for wget or curl
wget --version || curl --version
```

If `autoconf`, `automake`, or `libtool` are missing, see Step 4 — all three
can be built from source in your home directory without sudo.

---

## 2. Define Your Local Prefix

All software installs under a single directory. This keeps everything organized
and makes a clean uninstall trivial (just delete the two directories).

```bash
export LOCAL_PREFIX="$HOME/local"
mkdir -p "$LOCAL_PREFIX"/{bin,lib,lib64,include,share,etc}

export BUILD_DIR="$HOME/shmem-build"
mkdir -p "$BUILD_DIR"
```

Add everything to `~/.bashrc` for persistence across sessions:

```bash
cat >> ~/.bashrc << 'EOF'

# === Local shmem4py stack ===
export LOCAL_PREFIX="$HOME/local"
export BUILD_DIR="$HOME/shmem-build"
export PATH="$LOCAL_PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$LOCAL_PREFIX/lib:$LOCAL_PREFIX/lib64:$LD_LIBRARY_PATH"
export PKG_CONFIG_PATH="$LOCAL_PREFIX/lib/pkgconfig:$LOCAL_PREFIX/lib64/pkgconfig:$PKG_CONFIG_PATH"
export LDFLAGS="-L$LOCAL_PREFIX/lib"
export CPPFLAGS="-I$LOCAL_PREFIX/include"

# OpenSHMEM settings
export SHMEM_HOME="$LOCAL_PREFIX"
export OSHCC="$LOCAL_PREFIX/bin/oshcc"
export OSHCXX="$LOCAL_PREFIX/bin/oshc++"
export OSHRUN="$LOCAL_PREFIX/bin/oshrun"
export UCX_TLS="sm,self"
export SHMEM_SYMMETRIC_SIZE="128M"
EOF

source ~/.bashrc
```

---

## 3. Set Up Python venv

```bash
# Create the virtual environment
python3 -m venv "$HOME/shmem-venv"

# Activate it
source "$HOME/shmem-venv/bin/activate"

# Upgrade pip and install Python build tools
pip install --upgrade pip
pip install numpy cython

# Make activation persistent — add to ~/.bashrc
cat >> ~/.bashrc << 'EOF'

# Activate shmem venv
source "$HOME/shmem-venv/bin/activate"
EOF
```

> From this point on, every `pip install` targets the venv automatically.
> To deactivate at any time run `deactivate`; to reactivate run
> `source "$HOME/shmem-venv/bin/activate"`.

---

## 4. Build libtool

libtool is required by `autogen.sh` in SOS (Step 11) and by the autotools
chain in PMIx and PRRTE. If `libtool --version` in Step 1 returned a
"command not found" error, build it here. If libtool is already available
system-wide, skip this step.

```bash
cd "$BUILD_DIR"

LIBTOOL_VERSION="2.4.7"
wget https://ftp.gnu.org/gnu/libtool/libtool-${LIBTOOL_VERSION}.tar.gz
tar xzf libtool-${LIBTOOL_VERSION}.tar.gz
cd libtool-${LIBTOOL_VERSION}

./configure \
    --prefix="$LOCAL_PREFIX"

make -j$(nproc)
make install

# Verify — should print 2.4.7 or similar
libtool --version
```

> **Why no `--enable-shared` / `--disable-static` here?** libtool is a build
> tool, not a runtime library. It installs scripts and helper executables
> (`libtool`, `libtoolize`) rather than `.so` files, so those flags are not
> applicable.

> **`autoconf` and `automake` missing too?** They can be built the same way
> from GNU mirrors:
> ```bash
> # autoconf
> wget https://ftp.gnu.org/gnu/autoconf/autoconf-2.71.tar.gz
> tar xzf autoconf-2.71.tar.gz && cd autoconf-2.71
> ./configure --prefix="$LOCAL_PREFIX" && make -j$(nproc) && make install
> cd "$BUILD_DIR"
>
> # automake
> wget https://ftp.gnu.org/gnu/automake/automake-1.16.5.tar.gz
> tar xzf automake-1.16.5.tar.gz && cd automake-1.16.5
> ./configure --prefix="$LOCAL_PREFIX" && make -j$(nproc) && make install
> cd "$BUILD_DIR"
> ```

---

## 5. Create the g++ Wrapper Script

UCX's build system leaks C-only warning flags into C++ compilation, causing
fatal errors regardless of how `CXXFLAGS` is set. The reliable fix is a wrapper
script that strips the offending flags before they reach `g++`.

```bash
cat > "$LOCAL_PREFIX/bin/gxx-wrapper" << 'EOF'
#!/bin/bash
args=()
for arg in "$@"; do
    case "$arg" in
        -Wno-old-style-declaration)        ;;
        -Wno-implicit-function-declaration) ;;
        *) args+=("$arg") ;;
    esac
done
exec g++ "${args[@]}"
EOF

chmod +x "$LOCAL_PREFIX/bin/gxx-wrapper"
```

---

## 6. Build UCX

UCX is the high-performance network transport layer.

```bash
cd "$BUILD_DIR"

UCX_VERSION="1.17.0"
wget https://github.com/openucx/ucx/releases/download/v${UCX_VERSION}/ucx-${UCX_VERSION}.tar.gz
tar xzf ucx-${UCX_VERSION}.tar.gz
cd ucx-${UCX_VERSION}

CFLAGS="-Wno-cast-function-type \
        -Wno-old-style-declaration \
        -Wno-implicit-function-declaration" \
CXXFLAGS="-Wno-cast-function-type" \
CXX="$LOCAL_PREFIX/bin/gxx-wrapper" \
./configure \
    --prefix="$LOCAL_PREFIX" \
    --enable-shared \
    --disable-static \
    --without-cuda \
    --without-rocm \
    --without-go \
    --with-pic

make -j$(nproc)
make install

# Verify
ucx_info -v
```

**Flags explained:**
- `CFLAGS` — suppresses legacy C coding patterns that GCC 8+ warns on
- `CXXFLAGS` — suppresses the function-pointer cast warning for C++ files only
- `CXX=gxx-wrapper` — intercepts every C++ compiler call and strips the C-only flags before they reach g++
- `--without-go` — disables the Go bindings, which have a missing-directory bug in UCX 1.17.0

---

## 7. Build libevent

Required by both PMIx and PRRTE. Not auto-detected from `$LOCAL_PREFIX` without
being told explicitly, so build it first.

```bash
cd "$BUILD_DIR"

LIBEVENT_VERSION="2.1.12"
wget https://github.com/libevent/libevent/releases/download/release-${LIBEVENT_VERSION}-stable/libevent-${LIBEVENT_VERSION}-stable.tar.gz
tar xzf libevent-${LIBEVENT_VERSION}-stable.tar.gz
cd libevent-${LIBEVENT_VERSION}-stable

./configure \
    --prefix="$LOCAL_PREFIX" \
    --enable-shared \
    --disable-static \
    --with-pic

make -j$(nproc)
make install

# Verify
ls "$LOCAL_PREFIX/lib/libevent"*
```

---

## 8. Build hwloc

Required by both PMIx and PRRTE for hardware topology awareness.

```bash
cd "$BUILD_DIR"

HWLOC_VERSION="2.11.2"
wget https://download.open-mpi.org/release/hwloc/v2.11/hwloc-${HWLOC_VERSION}.tar.gz
tar xzf hwloc-${HWLOC_VERSION}.tar.gz
cd hwloc-${HWLOC_VERSION}

./configure \
    --prefix="$LOCAL_PREFIX" \
    --enable-shared \
    --disable-static \
    --with-pic

make -j$(nproc)
make install

# Verify
"$LOCAL_PREFIX/bin/lstopo" --version
ls "$LOCAL_PREFIX/lib/libhwloc"*
```

---

## 9. Build PMIx

The process management interface. Must have libevent and hwloc pointed at
explicitly — it will not find them via `PKG_CONFIG_PATH` alone.

```bash
cd "$BUILD_DIR"

PMIX_VERSION="4.2.9"
wget https://github.com/pmix/pmix/releases/download/v${PMIX_VERSION}/pmix-${PMIX_VERSION}.tar.bz2
tar xjf pmix-${PMIX_VERSION}.tar.bz2
cd pmix-${PMIX_VERSION}

./configure \
    --prefix="$LOCAL_PREFIX" \
    --enable-shared \
    --disable-static \
    --with-pic \
    --with-libevent="$LOCAL_PREFIX" \
    --with-hwloc="$LOCAL_PREFIX"

make -j$(nproc)
make install

# Verify
pmix_info | head -10
```

---

## 10. Build PRRTE

The process runtime that provides `prterun` / `oshrun`. Needs the same explicit
flags as PMIx.

```bash
cd "$BUILD_DIR"

PRRTE_VERSION="3.0.5"
wget https://github.com/openpmix/prrte/releases/download/v${PRRTE_VERSION}/prrte-${PRRTE_VERSION}.tar.bz2
tar xjf prrte-${PRRTE_VERSION}.tar.bz2
cd prrte-${PRRTE_VERSION}

./configure \
    --prefix="$LOCAL_PREFIX" \
    --enable-shared \
    --disable-static \
    --with-pmix="$LOCAL_PREFIX" \
    --with-ucx="$LOCAL_PREFIX" \
    --with-libevent="$LOCAL_PREFIX" \
    --with-hwloc="$LOCAL_PREFIX"

make -j$(nproc)
make install
```

---

## 11. Build Sandia OpenSHMEM (SOS)

The OpenSHMEM runtime. Cloned from GitHub because the release tarball URL
changed — `git clone` is more reliable across versions. The `autogen.sh` step
is required when building from a git clone (it generates the `configure` script
from autotools sources).

```bash
cd "$BUILD_DIR"

git clone --depth=1 --branch v1.5.3 \
    https://github.com/Sandia-OpenSHMEM/SOS.git SOS-1.5.3
cd SOS-1.5.3

# Generate the configure script (mandatory for git clones)
./autogen.sh

./configure \
    --prefix="$LOCAL_PREFIX" \
    --enable-shared \
    --disable-static \
    --with-ucx="$LOCAL_PREFIX" \
    --with-pmix="$LOCAL_PREFIX" \
    --with-libevent="$LOCAL_PREFIX" \
    --with-hwloc="$LOCAL_PREFIX" \
    --enable-pmi-simple \
    --disable-fortran

make -j$(nproc)
make install

# Verify
oshcc --version
ls "$LOCAL_PREFIX/bin/osh"*
```

---

## 12. Install shmem4py

With the runtime in place, install the Python bindings. The `CC` variable tells
pip to compile the extension module against the OpenSHMEM headers via `oshcc`.

```bash
# Ensure the venv is active
source "$HOME/shmem-venv/bin/activate"

CC="$LOCAL_PREFIX/bin/oshcc" pip install shmem4py

# Verify
python -c "import shmem4py; print('shmem4py version:', shmem4py.__version__)"
```

> If pip can't find `shmem.h`, set `SHMEM_DIR` explicitly:
> ```bash
> SHMEM_DIR="$LOCAL_PREFIX" CC="$LOCAL_PREFIX/bin/oshcc" pip install shmem4py
> ```

---

## 13. Test Your Installation

### 13.1 — C-level sanity check

Validate the runtime before touching Python:

```bash
cat > /tmp/hello_shmem.c << 'EOF'
#include <stdio.h>
#include <shmem.h>

int main(void) {
    shmem_init();
    int npes = shmem_n_pes();
    int mype = shmem_my_pe();
    printf("Hello from PE %d of %d\n", mype, npes);
    shmem_finalize();
    return 0;
}
EOF

oshcc -o /tmp/hello_shmem /tmp/hello_shmem.c
oshrun -np 4 /tmp/hello_shmem
```

Expected output (order may vary):
```
Hello from PE 0 of 4
Hello from PE 2 of 4
Hello from PE 1 of 4
Hello from PE 3 of 4
```

---

### 13.2 — shmem4py Hello World

Two important differences from the C API:
- Import as `from shmem4py import shmem`, not `import shmem4py as shmem`
- **Do not call `init()` or `finalize()`** — shmem4py handles these automatically on import and exit

```bash
cat > /tmp/hello_shmem4py.py << 'EOF'
from shmem4py import shmem

mype = shmem.my_pe()
npes = shmem.n_pes()
print(f"Hello from PE {mype} of {npes}")
EOF

oshrun -np 4 python /tmp/hello_shmem4py.py
```

Expected output:
```
Hello from PE 1 of 4
Hello from PE 3 of 4
Hello from PE 2 of 4
Hello from PE 0 of 4
```

---

### 13.3 — Broadcast

Symmetric memory is allocated with `shmem.zeros()` / `shmem.full()` / `shmem.empty()`,
and freed explicitly with `shmem.free()`.

```bash
cat > /tmp/broadcast_test.py << 'EOF'
from shmem4py import shmem

mype = shmem.my_pe()
npes = shmem.n_pes()

source = shmem.zeros(npes, dtype="int32")
dest   = shmem.full(npes, -999, dtype="int32")

if mype == 0:
    for i in range(npes):
        source[i] = i + 1

shmem.barrier_all()
shmem.broadcast(dest, source, 0)

print(f"PE {mype}: {dest}")

shmem.free(source)
shmem.free(dest)
EOF

oshrun -np 4 python /tmp/broadcast_test.py
```

Expected output:
```
PE 0: [1 2 3 4]
PE 1: [1 2 3 4]
PE 2: [1 2 3 4]
PE 3: [1 2 3 4]
```

---

### 13.4 — Put/Get (One-Sided Communication)

Note that `src` (symmetric) is allocated via `shmem.empty()`, while `dst`
(local only) uses `numpy.empty()` directly.

```bash
cat > /tmp/put_get_test.py << 'EOF'
from shmem4py import shmem
import numpy as np

mype   = shmem.my_pe()
npes   = shmem.n_pes()
nextpe = (mype + 1) % npes

# Symmetric buffer — visible to all PEs
src    = shmem.empty(1, dtype='i')
src[0] = mype

# Local buffer — only used by this PE
dst    = np.empty(1, dtype='i')
dst[0] = -1

shmem.barrier_all()
shmem.get(dst, src, nextpe)

print(f"PE {mype}: got {dst[0]} from PE {nextpe} (expected {nextpe})")
EOF

oshrun -np 4 python /tmp/put_get_test.py
```

Expected output:
```
PE 0: got 1 from PE 1 (expected 1)
PE 1: got 2 from PE 2 (expected 2)
PE 2: got 3 from PE 3 (expected 3)
PE 3: got 0 from PE 0 (expected 0)
```

---

## 14. Quick Reference: Useful Environment Variables

| Variable | Purpose | Example |
|---|---|---|
| `UCX_TLS` | Transport layers | `sm,self` (local) · `rc,sm,self` (IB+local) |
| `SHMEM_SYMMETRIC_SIZE` | Symmetric heap size | `128M`, `1G` |
| `UCX_NET_DEVICES` | Restrict to a NIC | `eth0`, `mlx5_0:1` |
| `SHMEM_DEBUG` | Runtime debug output | `1` |
| `UCX_LOG_LEVEL` | UCX verbosity | `warn`, `info`, `debug` |

---

## 15. Troubleshooting

**`libucx.so.0: cannot open shared object file`**
```bash
export LD_LIBRARY_PATH="$LOCAL_PREFIX/lib:$LOCAL_PREFIX/lib64:$LD_LIBRARY_PATH"
```

**`oshrun: command not found`**
```bash
export PATH="$LOCAL_PREFIX/bin:$PATH"
```

**`ImportError: shmem4py` or `shmem.h not found` during pip install**
```bash
SHMEM_DIR="$LOCAL_PREFIX" CC="$LOCAL_PREFIX/bin/oshcc" pip install --force-reinstall shmem4py
```

**`AttributeError: module 'shmem4py' has no attribute 'init'`**
You used `import shmem4py as shmem`. Change to:
```python
from shmem4py import shmem
```
And remove any `shmem.init()` / `shmem.finalize()` calls — they are not needed.

**`UCX ERROR no active transports`**
```bash
unset UCX_TLS   # let UCX auto-select
```

**`cc1plus: error: '-Wno-old-style-declaration' valid for C/ObjC but not C++`**
The g++ wrapper was not used during UCX configure. Redo from Step 5 with
`CXX="$LOCAL_PREFIX/bin/gxx-wrapper"`.

**PMIx/PRRTE: `libevent or libev support required`**
Add `--with-libevent="$LOCAL_PREFIX"` to the configure command.

**PMIx/PRRTE: `HWLOC topology library not found`**
Add `--with-hwloc="$LOCAL_PREFIX"` to the configure command.

---

## 16. Directory Layout Summary

```
~/local/
├── bin/     ← oshcc, oshrun, oshc++, ucx_info, prterun, pmix_info, gxx-wrapper
├── include/ ← shmem.h, ucx/, pmix.h, hwloc.h, event.h ...
├── lib/     ← libshmem.so, libucx*.so, libpmix.so, libhwloc.so, libevent*.so
└── share/   ← man pages, docs

~/shmem-venv/   ← Python venv (shmem4py + numpy installed here)
~/shmem-build/  ← build workspace (safe to delete after everything works)
```

To uninstall everything cleanly:
```bash
rm -rf ~/local ~/shmem-build ~/shmem-venv
# Then remove the lines added to ~/.bashrc between the === markers
```
