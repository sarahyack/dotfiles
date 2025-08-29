#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

### ---- SETTINGS ----
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$REPO_DIR/packages"
SERVICES_DIR="$REPO_DIR/services"
POST_DIR="$REPO_DIR/post-install.d"

PACMAN_LIST="$PACKAGES_DIR/pacman.txt"
AUR_LIST="$PACKAGES_DIR/aur.txt"
SYSTEM_SERVICES="$SERVICES_DIR/system.txt"
USER_SERVICES="$SERVICES_DIR/user.txt"

# Dotfiles pulled from YOUR repo
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/sarahyack/configs.git}"
DOTFILES_REF="${DOTFILES_REF:-master}"                     # branch/tag/commit
DOTFILES_DIR="${DOTFILES_DIR:-$REPO_DIR/.dotfiles-cache}"  # local clone cache
DOTFILES_MANIFEST="${DOTFILES_MANIFEST:-$REPO_DIR/dotfiles.manifest}"

# Optional: limit what we fetch from the dotfiles repo (faster on big repos)
# Example: SPARSE_PATHS=(".config/nvim" ".config/kitty" ".zshrc")
SPARSE_PATHS=()

# Copy mode for dotfiles: skip | backup | force
COPY_MODE="${COPY_MODE:-skip}"

# Preview actions without changing anything
DRY_RUN="${DRY_RUN:-0}"
### -------------------

log(){ printf "\n==> %s\n" "$*"; }
warn(){ printf "!! %s\n" "$*" >&2; }

read_list(){
  [[ -f "$1" ]] || return 0
  sed -E 's/#.*$//; s/[[:space:]]+$//' "$1" | awk 'NF'
}

ensure_tools(){
  log "Installing base tools (git, curl, rsync)…"
  sudo pacman -Sy --noconfirm
  sudo pacman -S --needed --noconfirm git curl rsync
}

ensure_yay(){
  if command -v yay >/dev/null 2>&1; then
    log "yay present."
    return
  fi
  log "Installing yay (AUR helper)…"
  sudo pacman -S --needed --noconfirm base-devel
  tmpdir="$(mktemp -d)"; pushd "$tmpdir" >/dev/null
  git clone https://aur.archlinux.org/yay-bin.git
  cd yay-bin
  makepkg -si --noconfirm
  popd >/dev/null; rm -rf "$tmpdir"
}

install_packages(){
  mapfile -t pacman_in < <(read_list "$PACMAN_LIST" || true)
  mapfile -t aur_in    < <(read_list "$AUR_LIST" || true)

  # Buckets we’ll actually install
  local pacman_pkgs=() aur_pkgs=() unknown=()

  # Helper: add unique
  add_unique(){ local -n arr=$1 x; for x in "${arr[@]}"; do [[ "$x" == "$2" ]] && return; done; arr+=("$2"); }

  # Ensure yay exists before probing AUR
  ensure_yay

  # Check a name: installed? repo? aur?
  classify(){
    local pkg="$1"
    # already installed?
    if pacman -Qq "$pkg" &>/dev/null; then return 0; fi
    # in official repos?
    if pacman -Si "$pkg" &>/dev/null; then add_unique pacman_pkgs "$pkg"; return 0; fi
    # in AUR?
    if yay -Si "$pkg" &>/dev/null; then add_unique aur_pkgs "$pkg"; return 0; fi
    unknown+=("$pkg")
  }

  # Classify everything the user put in pacman.txt (some may actually be AUR)
  for p in "${pacman_in[@]}"; do classify "$p"; done
  # Classify everything in aur.txt (some may actually be repo now)
  for p in "${aur_in[@]}";    do classify "$p"; done

  # Install repos first
  if ((${#pacman_pkgs[@]})); then
    log "Installing repo packages (${#pacman_pkgs[@]})…"
    sudo pacman -S --needed --noconfirm "${pacman_pkgs[@]}"
  else
    log "No new repo packages to install."
  fi

  # Then AUR
  if ((${#aur_pkgs[@]})); then
    log "Installing AUR packages (${#aur_pkgs[@]})…"
    yay -S --needed --noconfirm "${aur_pkgs[@]}"
  else
    log "No new AUR packages to install."
  fi

  # Warn about true unknowns (typos / retired packages)
  if ((${#unknown[@]})); then
    warn "These names weren’t found in repos or AUR: ${unknown[*]}"
  fi
}

expand_path(){
  local p="$1"
  [[ "$p" == "~"* ]] && p="${p/#\~/$HOME}"
  printf "%s" "$p"
}

clone_or_update_dotfiles(){
  mkdir -p "$(dirname "$DOTFILES_DIR")"
  if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
    log "Cloning dotfiles (shallow)…"
    if ((${#SPARSE_PATHS[@]})); then
      git clone --filter=blob:none --no-checkout "$DOTFILES_REPO" "$DOTFILES_DIR"
      git -C "$DOTFILES_DIR" sparse-checkout init --cone
      git -C "$DOTFILES_DIR" sparse-checkout set "${SPARSE_PATHS[@]}"
      git -C "$DOTFILES_DIR" checkout "$DOTFILES_REF"
    else
      git clone --depth=1 --branch "$DOTFILES_REF" "$DOTFILES_REPO" "$DOTFILES_DIR"
    fi
  else
    log "Updating dotfiles cache…"
    git -C "$DOTFILES_DIR" fetch --depth=1 origin "$DOTFILES_REF"
    git -C "$DOTFILES_DIR" reset --hard "origin/$DOTFILES_REF"
  fi
}

copy_one(){
  # copy_one SRC(in dotfiles repo) -> DEST(on system)
  local src_rel="$1"; shift
  local dest="$1"; shift

  local src="$DOTFILES_DIR/$src_rel"
  dest="$(expand_path "$dest")"

  if [[ -d "$src" ]]; then
    mkdir -p "$dest"
    local stamp; stamp="$(date +%Y%m%d%H%M%S)"
    local rs_flags=(-aH --human-readable)
    case "$COPY_MODE" in
      skip)   rs_flags+=(--ignore-existing) ;;
      backup) rs_flags+=(--backup --suffix=".bak-$stamp") ;;
      force)  : ;;
      *)      rs_flags+=(--ignore-existing) ;;
    esac
    (( DRY_RUN )) && rs_flags+=(--dry-run)
    rsync "${rs_flags[@]}" "$src"/ "$dest"/
  elif [[ -f "$src" ]]; then
    mkdir -p "$(dirname "$dest")"
    if (( DRY_RUN )); then
      log "[dry-run] copy $src -> $dest"
      return
    fi
    if [[ -e "$dest" ]]; then
      case "$COPY_MODE" in
        skip)   return ;;
        backup) cp -a --backup=numbered "$dest" "$dest.bak" ;;
        force)  : ;;
      esac
    fi
    install -m 0644 "$src" "$dest"
  else
    warn "Missing in dotfiles repo: $src_rel"
  fi
}

apply_dotfiles_manifest(){
  [[ -f "$DOTFILES_MANIFEST" ]] || { log "No manifest: $DOTFILES_MANIFEST (skipping)"; return; }
  log "Applying dotfiles manifest ($COPY_MODE mode)…"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"; line="$(printf "%s" "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [[ -z "$line" ]] && continue
    local src_rel dest
    src_rel="$(printf "%s" "$line" | awk -F'->' '{print $1}' | sed -E 's/[[:space:]]+$//')"
    dest="$(printf "%s" "$line" | awk -F'->' '{print $2}' | sed -E 's/^[[:space:]]+//')"
    if [[ -z "$src_rel" || -z "$dest" ]]; then
      warn "Bad manifest line: $line"; continue
    fi
    copy_one "$src_rel" "$dest"
  done < "$DOTFILES_MANIFEST"
}

enable_services(){
  if [[ -f "$SYSTEM_SERVICES" ]]; then
    while read -r svc; do
      [[ -n "$svc" ]] || continue
      log "Enable system service: $svc"
      sudo systemctl enable --now "$svc" || true
    done < <(read_list "$SYSTEM_SERVICES")
  fi
  if [[ -f "$USER_SERVICES" ]]; then
    if command -v loginctl >/dev/null 2>&1; then
      loginctl enable-linger "$USER" || true
    fi
    while read -r svc; do
      [[ -n "$svc" ]] || continue
      log "Enable user service: $svc"
      systemctl --user enable --now "$svc" || true
    done < <(read_list "$USER_SERVICES")
  fi
}

run_post(){
  [[ -d "$POST_DIR" ]] || return
  log "Running post-install scripts…"
  for f in "$POST_DIR"/*.sh; do
    [[ -e "$f" ]] || continue
    log "  $f"
    bash "$f"
  done
}

main(){
  ensure_tools
  ensure_yay
  install_packages
  clone_or_update_dotfiles
  apply_dotfiles_manifest
  enable_services
  run_post
  log "Done. Tip: DRY_RUN=1 bash install.sh to preview."
}

main "$@"
