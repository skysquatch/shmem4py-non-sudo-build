#!/usr/bin/env bash
# =============================================================================
# uninstall_shmem4py.sh
#
# Fully removes the shmem4py stack installed by install_shmem4py.sh.
# Cleans: $HOME/local, $HOME/shmem-build, $HOME/shmem-venv,
#         ~/.shmemrc, the ~/.bashrc sourcing line, and both log files.
#
# Usage:
#   chmod +x uninstall_shmem4py.sh
#   ./uninstall_shmem4py.sh            # interactive (confirms before deleting)
#   ./uninstall_shmem4py.sh --force    # skip confirmation prompt
#   ./uninstall_shmem4py.sh --dry-run  # show what would be removed, do nothing
#
# Safe to run even if the install was only partially completed.
# =============================================================================

set -euo pipefail

# ── Paths — must match install_shmem4py.sh exactly ────────────────────────────
LOCAL_PREFIX="$HOME/local"
BUILD_DIR="$HOME/shmem-build"
VENV_DIR="$HOME/shmem-venv"
SHMEMRC="$HOME/.shmemrc"
INSTALL_LOG="$HOME/shmem-install.log"
UNINSTALL_LOG="$HOME/shmem-uninstall.log"

# ~/.bashrc marker written by install_shmem4py.sh
BASHRC_MARKER="# shmem4py stack — added by install_shmem4py.sh"
# Line that follows the marker
BASHRC_SOURCE_LINE='[[ -f "$HOME/.shmemrc" ]] && source "$HOME/.shmemrc"'

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[DONE]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[SKIP]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}━━━  $*  ━━━${RESET}"; }
dryrun()  { echo -e "${YELLOW}[DRY-RUN]${RESET} Would remove: $*"; }

# ── Logging ───────────────────────────────────────────────────────────────────
exec > >(tee -a "$UNINSTALL_LOG") 2>&1
echo "============================================================"
echo " shmem4py uninstaller — $(date)"
echo "============================================================"

# ── Argument parsing ──────────────────────────────────────────────────────────
FORCE=false
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --force)   FORCE=true ;;
        --dry-run) DRY_RUN=true ;;
        *)
            error "Unknown argument: $arg"
            echo "Usage: $0 [--force] [--dry-run]"
            exit 1
            ;;
    esac
done

if [[ "$FORCE" == true && "$DRY_RUN" == true ]]; then
    error "--force and --dry-run are mutually exclusive."
    exit 1
fi

# ── Helper: remove a file or directory ───────────────────────────────────────
# Usage: remove <path> <label>
remove() {
    local path="$1" label="$2"
    if [[ ! -e "$path" ]]; then
        warn "$label not found — already clean"
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        dryrun "$path"
        return 0
    fi
    rm -rf "$path"
    success "Removed $label ($path)"
}

# =============================================================================
# Pre-flight: inventory what will be removed
# =============================================================================
header "Inventory"

FOUND=()
MISSING=()

check_item() {
    local path="$1" label="$2"
    if [[ -e "$path" ]]; then
        FOUND+=("  • $label  ($path)")
    else
        MISSING+=("  • $label  ($path)")
    fi
}

check_item "$LOCAL_PREFIX"  "Local install prefix  (~3–5 GB binaries/libs)"
check_item "$BUILD_DIR"     "Build workspace       (~1–3 GB source/objects)"
check_item "$VENV_DIR"      "Python venv           (shmem4py + numpy + cython)"
check_item "$SHMEMRC"       "~/.shmemrc            (environment file)"
check_item "$INSTALL_LOG"   "Install log           (~/.shmem-install.log)"

# Check bashrc separately (it exists but may or may not have the marker)
if grep -qF "$BASHRC_MARKER" ~/.bashrc 2>/dev/null; then
    FOUND+=("  • ~/.bashrc entry     (2-line sourcing block)")
else
    MISSING+=("  • ~/.bashrc entry     (not present)")
fi

echo ""
if [[ ${#FOUND[@]} -gt 0 ]]; then
    echo -e "${BOLD}Will be removed:${RESET}"
    for item in "${FOUND[@]}"; do echo "$item"; done
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo ""
    echo -e "${BOLD}Already absent (nothing to do):${RESET}"
    for item in "${MISSING[@]}"; do echo "$item"; done
fi

if [[ ${#FOUND[@]} -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}Nothing to remove — system is already clean.${RESET}"
    exit 0
fi

# ── Dry-run exits here after printing the inventory ───────────────────────────
if [[ "$DRY_RUN" == true ]]; then
    echo ""
    info "Dry-run mode — no files were modified."
    echo ""
    echo "Run without --dry-run to perform the actual removal."
    exit 0
fi

# ── Confirmation prompt (skipped with --force) ────────────────────────────────
if [[ "$FORCE" == false ]]; then
    echo ""
    echo -e "${YELLOW}${BOLD}This will permanently delete the items listed above.${RESET}"
    echo -n "Proceed? [y/N] "
    read -r REPLY
    case "$REPLY" in
        [yY]|[yY][eE][sS]) ;;
        *)
            echo "Aborted — nothing was removed."
            exit 0
            ;;
    esac
fi

# =============================================================================
# Step 1 — Deactivate the venv if currently active
# =============================================================================
header "Step 1 · Deactivating venv"

if [[ -n "${VIRTUAL_ENV:-}" && "$VIRTUAL_ENV" == "$VENV_DIR" ]]; then
    # shellcheck disable=SC1091
    deactivate 2>/dev/null || true
    success "venv deactivated"
else
    warn "venv not currently active — skipping deactivation"
fi

# =============================================================================
# Step 2 — Remove the Python venv
# =============================================================================
header "Step 2 · Python venv ($VENV_DIR)"
remove "$VENV_DIR" "Python venv"

# =============================================================================
# Step 3 — Remove shmem4py and all compiled libraries ($HOME/local)
# =============================================================================
header "Step 3 · Local install prefix ($LOCAL_PREFIX)"
remove "$LOCAL_PREFIX" "local install prefix"

# =============================================================================
# Step 4 — Remove the build workspace
# =============================================================================
header "Step 4 · Build workspace ($BUILD_DIR)"
remove "$BUILD_DIR" "build workspace"

# =============================================================================
# Step 5 — Remove ~/.shmemrc
# =============================================================================
header "Step 5 · Environment file (~/.shmemrc)"
remove "$SHMEMRC" "~/.shmemrc"

# =============================================================================
# Step 6 — Remove the install log
# =============================================================================
header "Step 6 · Install log ($INSTALL_LOG)"
remove "$INSTALL_LOG" "install log"

# =============================================================================
# Step 7 — Clean the ~/.bashrc sourcing block
# =============================================================================
header "Step 7 · ~/.bashrc cleanup"

if ! grep -qF "$BASHRC_MARKER" ~/.bashrc 2>/dev/null; then
    warn "No shmem4py entry found in ~/.bashrc — already clean"
else
    # Create a backup before editing
    BASHRC_BACKUP="$HOME/.bashrc.shmem-uninstall-backup"
    cp ~/.bashrc "$BASHRC_BACKUP"
    info "Backed up ~/.bashrc to $BASHRC_BACKUP"

    # Remove the marker line, the source line, and the blank line before them.
    # Uses a two-pass sed:
    #   Pass 1: delete the blank line immediately before the marker
    #   Pass 2: delete the marker line and the source line that follows it
    sed -i "/^[[:space:]]*$/{
        N
        /\n[[:space:]]*$(echo "$BASHRC_MARKER" | sed 's/[^^]/[&]/g; s/\^/\\^/g')/d
    }" ~/.bashrc

    sed -i "/$(echo "$BASHRC_MARKER" | sed 's/[^^]/[&]/g; s/\^/\\^/g')/{
        N
        d
    }" ~/.bashrc

    # Verify the marker is gone
    if grep -qF "$BASHRC_MARKER" ~/.bashrc 2>/dev/null; then
        error "Could not automatically remove the shmem4py block from ~/.bashrc."
        error "Please remove these two lines manually:"
        error "  $BASHRC_MARKER"
        error "  $BASHRC_SOURCE_LINE"
        error "A backup of your original ~/.bashrc is at $BASHRC_BACKUP"
    else
        success "shmem4py block removed from ~/.bashrc"
        info "Backup retained at $BASHRC_BACKUP (delete it once you've verified ~/.bashrc)"
    fi
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  Uninstall Summary${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  Log written to : $UNINSTALL_LOG"
echo ""
echo -e "${GREEN}${BOLD}  Uninstall complete.${RESET}"
echo ""
echo -e "  Open a new shell (or run ${BOLD}source ~/.bashrc${RESET}) to ensure"
echo -e "  all removed paths are cleared from your current session."
echo ""
echo -e "  To reinstall at any time, run ${BOLD}./install_shmem4py.sh${RESET}."
echo ""
