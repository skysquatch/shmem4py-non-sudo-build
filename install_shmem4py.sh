#!/usr/bin/env bash
# =============================================================================
# install_shmem4py.sh
#
# Automated installer for the full shmem4py stack on Linux without sudo.
# Builds and installs into $HOME/local; uses a Python venv at $HOME/shmem-venv.
#
# Usage:
#   chmod +x install_shmem4py.sh
#   ./install_shmem4py.sh            # full install
#   ./install_shmem4py.sh --test-only  # skip build, run tests only
#
# Idempotent: each component is skipped if its sentinel binary already exists.
# A full log is written to $HOME/shmem-install.log.
# =============================================================================

set -euo pipefail

# ── Version pins ──────────────────────────────────────────────────────────────
AUTOCONF_VERSION="2.71"
AUTOMAKE_VERSION="1.16.5"
LIBTOOL_VERSION="2.4.7"
UCX_VERSION="1.17.0"
LIBEVENT_VERSION="2.1.12"
HWLOC_VERSION="2.11.2"
PMIX_VERSION="4.2.9"
PRRTE_VERSION="3.0.5"
SOS_VERSION="1.5.3"

# ── Paths ─────────────────────────────────────────────────────────────────────
LOCAL_PREFIX="$HOME/local"
BUILD_DIR="$HOME/shmem-build"
VENV_DIR="$HOME/shmem-venv"
LOG_FILE="$HOME/shmem-install.log"

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

# Status helpers: coloured output to terminal + plain copy to log file.
# Noisy commands (configure, make, pip, git) are redirected to the log
# directly with >> "$LOG_FILE" 2>&1 so they never appear on the terminal.
info()    { local m="[INFO]  $*"; echo -e "${BLUE}${m}${RESET}";   echo "${m}"    >> "$LOG_FILE"; }
success() { local m="[DONE]  $*"; echo -e "${GREEN}${m}${RESET}";  echo "${m}"    >> "$LOG_FILE"; }
warn()    { local m="[SKIP]  $*"; echo -e "${YELLOW}${m}${RESET}"; echo "${m}"    >> "$LOG_FILE"; }
error()   { local m="[ERROR] $*"; echo -e "${RED}${m}${RESET}" >&2; echo "${m}"  >> "$LOG_FILE"; }
header()  { local m="━━━  $*  ━━━"; echo -e "\n${BOLD}${m}${RESET}"; echo -e "\n${m}" >> "$LOG_FILE"; }

# ── Write session header to log only (not terminal) ───────────────────────────
{
    echo "============================================================"
    echo " shmem4py installer — $(date)"
    echo "============================================================"
} >> "$LOG_FILE"

# ── ERR trap: when any command fails, show the log tail on the terminal ────────
# This is essential because configure/make output is silenced to the log;
# without this the script would exit with no visible explanation.
on_error() {
    local exit_code=$?
    local line_no=$1
    error "Command failed (exit ${exit_code}) at line ${line_no}."
    error "Last 40 lines of $LOG_FILE:"
    echo "" >&2
    tail -40 "$LOG_FILE" >&2
    echo "" >&2
    error "Full log: $LOG_FILE"
}
trap 'on_error $LINENO' ERR

# ── Argument parsing ──────────────────────────────────────────────────────────
TEST_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --test-only) TEST_ONLY=true ;;
        *) error "Unknown argument: $arg"; exit 1 ;;
    esac
done

# ── Apply local prefix to current shell immediately ───────────────────────────
export PATH="$LOCAL_PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$LOCAL_PREFIX/lib:$LOCAL_PREFIX/lib64:${LD_LIBRARY_PATH:-}"
export PKG_CONFIG_PATH="$LOCAL_PREFIX/lib/pkgconfig:$LOCAL_PREFIX/lib64/pkgconfig:${PKG_CONFIG_PATH:-}"
export LDFLAGS="-L$LOCAL_PREFIX/lib"
export CPPFLAGS="-I$LOCAL_PREFIX/include"

# ── Helper: download with wget or curl ───────────────────────────────────────
download() {
    local url="$1" dest="$2"
    if command -v wget &>/dev/null; then
        wget -q -O "$dest" "$url" >> "$LOG_FILE" 2>&1
    elif command -v curl &>/dev/null; then
        curl -fsSL -o "$dest" "$url" >> "$LOG_FILE" 2>&1
    else
        error "Neither wget nor curl is available. Cannot download files."
        exit 1
    fi
}

# ── Helper: build a GNU autotools package from a tarball ─────────────────────
# Usage: build_autotools <label> <sentinel_bin> <tarball_url> <tar_flags>
#        <src_dir> [extra_configure_args...]
build_autotools() {
    local label="$1" sentinel="$2" url="$3" tar_flags="$4" src_dir="$5"
    shift 5
    local extra_args=("$@")

    if command -v "$sentinel" &>/dev/null; then
        warn "$label already installed ($(command -v "$sentinel")) — skipping"
        return 0
    fi

    header "Building $label"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    local archive
    archive="$(basename "$url")"
    info "Downloading $label…"
    download "$url" "$archive"

    info "Extracting…"
    tar "${tar_flags}xf" "$archive" >> "$LOG_FILE" 2>&1
    cd "$src_dir"

    info "Configuring…"
    PKG_CONFIG_PATH="$LOCAL_PREFIX/lib/pkgconfig:$LOCAL_PREFIX/lib64/pkgconfig:${PKG_CONFIG_PATH:-}" \
    LDFLAGS="-L$LOCAL_PREFIX/lib" \
    CPPFLAGS="-I$LOCAL_PREFIX/include" \
    ./configure --prefix="$LOCAL_PREFIX" "${extra_args[@]}" >> "$LOG_FILE" 2>&1

    info "Compiling with $(nproc) cores…"
    make -j"$(nproc)" >> "$LOG_FILE" 2>&1

    info "Installing…"
    make install >> "$LOG_FILE" 2>&1

    success "$label installed"
    cd "$BUILD_DIR"
}

# =============================================================================
# STEP 0 — Preflight
# =============================================================================
if [[ "$TEST_ONLY" == false ]]; then
header "Step 0 · Preflight checks"

PREFLIGHT_OK=true

check_tool() {
    local tool="$1" label="${2:-$1}"
    if command -v "$tool" &>/dev/null; then
        success "$label: $(command -v "$tool")"
    else
        warn "$label: not found (will attempt to build from source if possible)"
        PREFLIGHT_OK=false
    fi
}

check_tool gcc     "C compiler (gcc)"
check_tool g++     "C++ compiler (g++)"
check_tool make    "make"
check_tool git     "git"
check_tool python3 "Python 3"

# Disk space check — require at least 5 GB free in $HOME
AVAIL_KB=$(df --output=avail "$HOME" | tail -1)
AVAIL_GB=$(( AVAIL_KB / 1024 / 1024 ))
if (( AVAIL_KB < 5242880 )); then
    error "Only ${AVAIL_GB} GB free in \$HOME — at least 5 GB required."
    exit 1
else
    success "Disk space: ~${AVAIL_GB} GB free in \$HOME"
fi

# gcc/g++ and make are hard requirements — cannot build them without them
for tool in gcc g++ make git python3; do
    if ! command -v "$tool" &>/dev/null; then
        error "$tool is required and cannot be installed by this script. Contact your sysadmin."
        exit 1
    fi
done

# Python version check — need 3.8+
PY_MINOR=$(python3 -c "import sys; print(sys.version_info.minor)")
PY_MAJOR=$(python3 -c "import sys; print(sys.version_info.major)")
if (( PY_MAJOR < 3 || (PY_MAJOR == 3 && PY_MINOR < 8) )); then
    error "Python 3.8+ is required. Found: $(python3 --version)"
    exit 1
fi
success "Python version: $(python3 --version)"

fi  # end TEST_ONLY guard

# =============================================================================
# STEP 1 — Create directories and set up local prefix
# =============================================================================
if [[ "$TEST_ONLY" == false ]]; then
header "Step 1 · Directories and environment"

mkdir -p "$LOCAL_PREFIX"/{bin,lib,lib64,include,share,etc}
mkdir -p "$BUILD_DIR"
success "Local prefix: $LOCAL_PREFIX"
success "Build workspace: $BUILD_DIR"

# Write ~/.shmemrc (always overwritten so it stays current)
cat > ~/.shmemrc << 'SHMEMRC_EOF'
# ~/.shmemrc — shmem4py environment (generated by install_shmem4py.sh)
# Source this file to activate the shmem4py stack:
#   source ~/.shmemrc

export LOCAL_PREFIX="$HOME/local"
export BUILD_DIR="$HOME/shmem-build"
export PATH="$LOCAL_PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$LOCAL_PREFIX/lib:$LOCAL_PREFIX/lib64:${LD_LIBRARY_PATH:-}"
export PKG_CONFIG_PATH="$LOCAL_PREFIX/lib/pkgconfig:$LOCAL_PREFIX/lib64/pkgconfig:${PKG_CONFIG_PATH:-}"
export LDFLAGS="-L$LOCAL_PREFIX/lib"
export CPPFLAGS="-I$LOCAL_PREFIX/include"

# OpenSHMEM settings
export SHMEM_HOME="$LOCAL_PREFIX"
export OSHCC="$LOCAL_PREFIX/bin/oshcc"
export OSHCXX="$LOCAL_PREFIX/bin/oshc++"
export OSHRUN="$LOCAL_PREFIX/bin/oshrun"
export UCX_TLS="sm,self"
export SHMEM_SYMMETRIC_SIZE="128M"

# Activate the Python venv
source "$HOME/shmem-venv/bin/activate" 2>/dev/null || true
SHMEMRC_EOF
success "~/.shmemrc written"

# Add a single source line to ~/.bashrc (only once)
BASHRC_MARKER="# shmem4py stack — added by install_shmem4py.sh"
if ! grep -qF "$BASHRC_MARKER" ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc << BASHRC_EOF

$BASHRC_MARKER
[[ -f "\$HOME/.shmemrc" ]] && source "\$HOME/.shmemrc"
BASHRC_EOF
    success "~/.bashrc updated to source ~/.shmemrc"
else
    warn "~/.bashrc source line already present — skipping"
fi

fi  # end TEST_ONLY guard

# =============================================================================
# STEP 2 — Python venv
# =============================================================================
if [[ "$TEST_ONLY" == false ]]; then
header "Step 2 · Python virtual environment"

if [[ -f "$VENV_DIR/bin/activate" ]]; then
    warn "venv already exists at $VENV_DIR — skipping creation"
else
    info "Creating venv at $VENV_DIR…"
    python3 -m venv "$VENV_DIR" >> "$LOG_FILE" 2>&1
    success "venv created"
fi

# Activate for the remainder of this script
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
info "Upgrading pip and installing numpy/cython…"
pip install --upgrade pip >> "$LOG_FILE" 2>&1
pip install numpy cython >> "$LOG_FILE" 2>&1
success "venv ready: $(python --version)"

fi  # end TEST_ONLY guard

# =============================================================================
# STEP 3 — autoconf, automake, libtool  (build if missing)
# =============================================================================
if [[ "$TEST_ONLY" == false ]]; then
header "Step 3 · GNU autotools (autoconf / automake / libtool)"

build_autotools "autoconf ${AUTOCONF_VERSION}" \
    "autoconf" \
    "https://ftp.gnu.org/gnu/autoconf/autoconf-${AUTOCONF_VERSION}.tar.gz" \
    "z" \
    "autoconf-${AUTOCONF_VERSION}"

build_autotools "automake ${AUTOMAKE_VERSION}" \
    "automake" \
    "https://ftp.gnu.org/gnu/automake/automake-${AUTOMAKE_VERSION}.tar.gz" \
    "z" \
    "automake-${AUTOMAKE_VERSION}"

build_autotools "libtool ${LIBTOOL_VERSION}" \
    "libtool" \
    "https://ftp.gnu.org/gnu/libtool/libtool-${LIBTOOL_VERSION}.tar.gz" \
    "z" \
    "libtool-${LIBTOOL_VERSION}"

fi  # end TEST_ONLY guard

# =============================================================================
# STEP 4 — g++ wrapper script
# =============================================================================
if [[ "$TEST_ONLY" == false ]]; then
header "Step 4 · g++ wrapper (UCX flag-bleed fix)"

GXX_WRAPPER="$LOCAL_PREFIX/bin/gxx-wrapper"
if [[ -x "$GXX_WRAPPER" ]]; then
    warn "gxx-wrapper already exists — skipping"
else
    cat > "$GXX_WRAPPER" << 'WRAPPER_EOF'
#!/usr/bin/env bash
# Strips C-only warning flags that UCX's build system leaks into C++ compilation.
args=()
for arg in "$@"; do
    case "$arg" in
        -Wno-old-style-declaration)         ;;
        -Wno-implicit-function-declaration) ;;
        *) args+=("$arg") ;;
    esac
done
exec g++ "${args[@]}"
WRAPPER_EOF
    chmod +x "$GXX_WRAPPER"
    success "gxx-wrapper written to $GXX_WRAPPER"
fi

fi  # end TEST_ONLY guard

# =============================================================================
# STEP 5 — UCX
# =============================================================================
if [[ "$TEST_ONLY" == false ]]; then
header "Step 5 · UCX ${UCX_VERSION}"

if command -v ucx_info &>/dev/null; then
    warn "UCX already installed ($(ucx_info -v 2>&1 | head -1)) — skipping"
else
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    info "Downloading UCX ${UCX_VERSION}…"
    download \
        "https://github.com/openucx/ucx/releases/download/v${UCX_VERSION}/ucx-${UCX_VERSION}.tar.gz" \
        "ucx-${UCX_VERSION}.tar.gz"

    tar xzf "ucx-${UCX_VERSION}.tar.gz" >> "$LOG_FILE" 2>&1
    cd "ucx-${UCX_VERSION}"

    info "Configuring UCX…"
    CFLAGS="-Wno-cast-function-type -Wno-old-style-declaration -Wno-implicit-function-declaration" \
    CXXFLAGS="-Wno-cast-function-type" \
    CXX="$GXX_WRAPPER" \
    PKG_CONFIG_PATH="$LOCAL_PREFIX/lib/pkgconfig:$LOCAL_PREFIX/lib64/pkgconfig:${PKG_CONFIG_PATH:-}" \
    LDFLAGS="-L$LOCAL_PREFIX/lib" \
    CPPFLAGS="-I$LOCAL_PREFIX/include" \
    ./configure \
        --prefix="$LOCAL_PREFIX" \
        --enable-shared \
        --disable-static \
        --without-cuda \
        --without-rocm \
        --without-go \
        --with-pic >> "$LOG_FILE" 2>&1

    info "Compiling UCX with $(nproc) cores…"
    make -j"$(nproc)" >> "$LOG_FILE" 2>&1
    make install >> "$LOG_FILE" 2>&1

    success "UCX installed: $(ucx_info -v 2>&1 | head -1)"
fi

fi  # end TEST_ONLY guard

# =============================================================================
# STEP 6 — libevent
# =============================================================================
if [[ "$TEST_ONLY" == false ]]; then
header "Step 6 · libevent ${LIBEVENT_VERSION}"

LIBEVENT_LIB="$LOCAL_PREFIX/lib/libevent.so"
if [[ -f "$LIBEVENT_LIB" ]] || ls "$LOCAL_PREFIX/lib/libevent-"*.so &>/dev/null 2>&1; then
    warn "libevent already installed — skipping"
else
    build_autotools "libevent ${LIBEVENT_VERSION}" \
        "_NEVER_EXISTS_SENTINEL_" \
        "https://github.com/libevent/libevent/releases/download/release-${LIBEVENT_VERSION}-stable/libevent-${LIBEVENT_VERSION}-stable.tar.gz" \
        "z" \
        "libevent-${LIBEVENT_VERSION}-stable" \
        --enable-shared --disable-static --with-pic
    success "libevent installed"
fi

fi  # end TEST_ONLY guard

# =============================================================================
# STEP 7 — hwloc
# =============================================================================
if [[ "$TEST_ONLY" == false ]]; then
header "Step 7 · hwloc ${HWLOC_VERSION}"

if pkg-config --exists hwloc; then
    warn "hwloc already installed ($(lstopo --version)) — skipping"
else
    build_autotools "hwloc ${HWLOC_VERSION}" \
        "_NEVER_EXISTS_SENTINEL_" \
        "https://download.open-mpi.org/release/hwloc/v2.11/hwloc-${HWLOC_VERSION}.tar.gz" \
        "z" \
        "hwloc-${HWLOC_VERSION}" \
        --enable-shared --disable-static --with-pic
    success "hwloc installed: $("$LOCAL_PREFIX/bin/lstopo" --version)"
fi

fi  # end TEST_ONLY guard

# =============================================================================
# STEP 8 — PMIx
# =============================================================================
if [[ "$TEST_ONLY" == false ]]; then
header "Step 8 · PMIx ${PMIX_VERSION}"

if command -v pmix_info &>/dev/null; then
    warn "PMIx already installed — skipping"
else
    build_autotools "PMIx ${PMIX_VERSION}" \
        "_NEVER_EXISTS_SENTINEL_" \
        "https://github.com/pmix/pmix/releases/download/v${PMIX_VERSION}/pmix-${PMIX_VERSION}.tar.bz2" \
        "j" \
        "pmix-${PMIX_VERSION}" \
        --enable-shared --disable-static --with-pic \
        "--with-libevent=$LOCAL_PREFIX" \
        "--with-hwloc=$LOCAL_PREFIX"
    success "PMIx installed"
fi

fi  # end TEST_ONLY guard

# =============================================================================
# STEP 9 — PRRTE
# =============================================================================
if [[ "$TEST_ONLY" == false ]]; then
header "Step 9 · PRRTE ${PRRTE_VERSION}"

if command -v prterun &>/dev/null; then
    warn "PRRTE already installed — skipping"
else
    build_autotools "PRRTE ${PRRTE_VERSION}" \
        "_NEVER_EXISTS_SENTINEL_" \
        "https://github.com/openpmix/prrte/releases/download/v${PRRTE_VERSION}/prrte-${PRRTE_VERSION}.tar.bz2" \
        "j" \
        "prrte-${PRRTE_VERSION}" \
        --enable-shared --disable-static \
        "--with-pmix=$LOCAL_PREFIX" \
        "--with-ucx=$LOCAL_PREFIX" \
        "--with-libevent=$LOCAL_PREFIX" \
        "--with-hwloc=$LOCAL_PREFIX"
    success "PRRTE installed"
fi

fi  # end TEST_ONLY guard

# =============================================================================
# STEP 10 — Sandia OpenSHMEM (SOS)
# =============================================================================
if [[ "$TEST_ONLY" == false ]]; then
header "Step 10 · Sandia OpenSHMEM (SOS) v${SOS_VERSION}"

if command -v oshcc &>/dev/null; then
    warn "SOS already installed ($(oshcc --version 2>&1 | head -1)) — skipping"
else
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    local_sos_dir="$BUILD_DIR/SOS-${SOS_VERSION}"
    if [[ -d "$local_sos_dir" ]]; then
        warn "SOS source already cloned — skipping git clone"
    else
        info "Cloning SOS v${SOS_VERSION}…"
        git clone --depth=1 --branch "v${SOS_VERSION}" \
            https://github.com/Sandia-OpenSHMEM/SOS.git \
            "$local_sos_dir" >> "$LOG_FILE" 2>&1
    fi

    cd "$local_sos_dir"
    git submodule update --init

    info "Running autogen.sh…"
    ./autogen.sh >> "$LOG_FILE" 2>&1

    info "Configuring SOS…"
    PKG_CONFIG_PATH="$LOCAL_PREFIX/lib/pkgconfig:$LOCAL_PREFIX/lib64/pkgconfig:${PKG_CONFIG_PATH:-}" \
    LDFLAGS="-L$LOCAL_PREFIX/lib" \
    CPPFLAGS="-I$LOCAL_PREFIX/include" \
    ./configure \
        --prefix="$LOCAL_PREFIX" \
        --enable-shared \
        --disable-static \
        "--with-ucx=$LOCAL_PREFIX" \
        "--with-pmix=$LOCAL_PREFIX" \
        "--with-libevent=$LOCAL_PREFIX" \
        "--with-hwloc=$LOCAL_PREFIX" \
        --enable-pmi-simple \
        --disable-fortran >> "$LOG_FILE" 2>&1

    info "Compiling SOS with $(nproc) cores…"
    make -j"$(nproc)" >> "$LOG_FILE" 2>&1
    make install >> "$LOG_FILE" 2>&1

    success "SOS installed: $(oshcc --version 2>&1 | head -1)"
fi

fi  # end TEST_ONLY guard

# =============================================================================
# STEP 11 — shmem4py
# =============================================================================
if [[ "$TEST_ONLY" == false ]]; then
header "Step 11 · shmem4py"

# Activate venv if not already active
if [[ -z "${VIRTUAL_ENV:-}" ]]; then
    source "$VENV_DIR/bin/activate"
fi

if python -c "import shmem4py" &>/dev/null 2>&1; then
    INSTALLED_VER=$(python -c "import shmem4py; print(shmem4py.__version__)")
    warn "shmem4py ${INSTALLED_VER} already installed — skipping"
else
    info "Installing shmem4py via pip…"
    CC="$LOCAL_PREFIX/bin/oshcc" \
    SHMEM_DIR="$LOCAL_PREFIX" \
    pip install shmem4py >> "$LOG_FILE" 2>&1
    success "shmem4py $(python -c 'import shmem4py; print(shmem4py.__version__)') installed"
fi

fi  # end TEST_ONLY guard

# =============================================================================
# STEP 12 — Tests
# =============================================================================
header "Step 12 · Validation tests"

# Activate venv for tests
if [[ -f "$VENV_DIR/bin/activate" ]]; then
    source "$VENV_DIR/bin/activate"
fi

TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local name="$1" cmd="$2"
    info "Running: $name…"
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        success "PASSED — $name"
        (( TESTS_PASSED++ )) || true
    else
        error "FAILED — $name  (see $LOG_FILE for details)"
        (( TESTS_FAILED++ )) || true
    fi
}

# ── Test 1: C hello world ─────────────────────────────────────────────────────
C_SRC=$(mktemp /tmp/hello_shmem_XXXX.c)
C_BIN=$(mktemp /tmp/hello_shmem_XXXX)
cat > "$C_SRC" << 'C_EOF'
#include <stdio.h>
#include <shmem.h>
int main(void) {
    shmem_init();
    printf("Hello from PE %d of %d\n", shmem_my_pe(), shmem_n_pes());
    shmem_finalize();
    return 0;
}
C_EOF
oshcc -o "$C_BIN" "$C_SRC"
run_test "C OpenSHMEM hello world (4 PEs)" \
    "oshrun -np 4 $C_BIN"

# ── Test 2: shmem4py hello world ─────────────────────────────────────────────
PY_HELLO=$(mktemp /tmp/hello_shmem4py_XXXX.py)
cat > "$PY_HELLO" << 'PY_EOF'
from shmem4py import shmem
print(f"Hello from PE {shmem.my_pe()} of {shmem.n_pes()}")
PY_EOF
run_test "shmem4py hello world (4 PEs)" \
    "oshrun -np 4 python $PY_HELLO"

# ── Test 3: broadcast ─────────────────────────────────────────────────────────
PY_BCAST=$(mktemp /tmp/broadcast_XXXX.py)
cat > "$PY_BCAST" << 'PY_EOF'
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
assert all(dest[i] == i + 1 for i in range(npes)), f"PE {mype}: broadcast failed: {dest}"
if mype == 0:
    print(f"Broadcast result: {list(dest)}")
shmem.free(source)
shmem.free(dest)
PY_EOF
run_test "shmem4py broadcast (4 PEs)" \
    "oshrun -np 4 python $PY_BCAST"

# ── Test 4: put/get ───────────────────────────────────────────────────────────
PY_PUTGET=$(mktemp /tmp/putget_XXXX.py)
cat > "$PY_PUTGET" << 'PY_EOF'
from shmem4py import shmem
import numpy as np
mype   = shmem.my_pe()
npes   = shmem.n_pes()
nextpe = (mype + 1) % npes
src    = shmem.empty(1, dtype='i')
src[0] = mype
dst    = np.empty(1, dtype='i')
dst[0] = -1
shmem.barrier_all()
shmem.get(dst, src, nextpe)
assert dst[0] == nextpe, f"PE {mype}: expected {nextpe}, got {dst[0]}"
print(f"PE {mype}: got {dst[0]} from PE {nextpe} ✓")
PY_EOF
run_test "shmem4py put/get (4 PEs)" \
    "oshrun -np 4 python $PY_PUTGET"

# Clean up temp files
rm -f "$C_SRC" "$C_BIN" "$PY_HELLO" "$PY_BCAST" "$PY_PUTGET"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  Install + Test Summary${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  Tests passed : ${GREEN}${TESTS_PASSED}${RESET}"
if (( TESTS_FAILED > 0 )); then
    echo -e "  Tests failed : ${RED}${TESTS_FAILED}${RESET}"
else
    echo -e "  Tests failed : ${GREEN}0${RESET}"
fi
echo -e "  Full log     : $LOG_FILE"
echo ""

if (( TESTS_FAILED == 0 )); then
    echo -e "${GREEN}${BOLD}  All done! shmem4py is ready to use.${RESET}"
    echo ""
    echo -e "  Start a new shell (or run ${BOLD}source ~/.bashrc${RESET}) to activate"
    echo -e "  the environment, then run your programs with:"
    echo ""
    echo -e "    ${BOLD}oshrun -np <N> python your_script.py${RESET}"
    echo ""
else
    echo -e "${RED}${BOLD}  Some tests failed. Check $LOG_FILE for details.${RESET}"
    exit 1
fi
