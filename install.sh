#!/bin/sh
# AGP Community Edition — CLI installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/getraksha/agp/main/install.sh | sh
#
# Environment overrides:
#   AGP_VERSION      release tag to install (default: latest, e.g. "v0.1.0")
#   AGP_INSTALL_DIR  install directory (default: /usr/local/bin if writable,
#                    otherwise ~/.local/bin)
#   AGP_BASE_URL     alternate asset base URL (internal mirrors / testing);
#                    assets are fetched from $AGP_BASE_URL/<asset> directly
#   AGP_NO_MODIFY_PATH  set to any value to skip editing your shell profile;
#                    the installer will only print the PATH line instead
#
# While the distribution repo is private, anonymous downloads return 404.
# The script then falls back to the GitHub CLI: install gh, run
# `gh auth login`, and re-run this script.
#
# This script downloads the `agp` CLI binary for your platform from
# https://github.com/getraksha/agp/releases, verifies its SHA-256 checksum
# against the release's SHA256SUMS, and installs it. The AGP services are
# then installed by the CLI itself via `agp fetch`.
#
# Copyright (c) Raksha AI. This install script is licensed under the MIT
# License. The AGP binaries it downloads are licensed under the AGP
# Community Edition License (see LICENSE.md in this repository).

set -eu

REPO="getraksha/agp"
BASE_LATEST="https://github.com/${REPO}/releases/latest/download"
BASE_TAGGED="https://github.com/${REPO}/releases/download"

say()  { printf '%s\n' "$*"; }
fail() { printf 'install.sh: error: %s\n' "$*" >&2; exit 1; }

# ── Platform detection ───────────────────────────────────────────────────────
os=$(uname -s)
case "$os" in
  Darwin) os="darwin" ;;
  Linux)  os="linux" ;;
  *) fail "unsupported operating system: $os (AGP supports macOS and Linux)" ;;
esac

arch=$(uname -m)
case "$arch" in
  arm64|aarch64) arch="arm64" ;;
  x86_64|amd64)  arch="amd64" ;;
  *) fail "unsupported architecture: $arch (AGP supports arm64 and amd64)" ;;
esac
platform="${os}-${arch}"

# ── Download helpers ─────────────────────────────────────────────────────────
if command -v curl >/dev/null 2>&1; then
  download() { curl -fsSL -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
  download() { wget -qO "$2" "$1"; }
else
  fail "neither curl nor wget is available"
fi

gh_ready() {
  command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1
}

checksum() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    fail "neither shasum nor sha256sum is available"
  fi
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT INT TERM

manifest_version() {
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n 1
}

# ── Resolve version + transport ──────────────────────────────────────────────
# mode "url": plain HTTPS from GitHub releases (public repo) or a mirror.
# mode "gh":  authenticated GitHub CLI (private repo during testing).
version="${AGP_VERSION:-}"
mode="url"

if [ -n "${AGP_BASE_URL:-}" ]; then
  base="$AGP_BASE_URL"
  if [ -z "$version" ]; then
    download "${base}/manifest.json" "$tmpdir/manifest.json" \
      || fail "could not download manifest from $base"
    version=$(manifest_version "$tmpdir/manifest.json")
    [ -n "$version" ] || fail "could not parse version from manifest"
  fi
elif [ -n "$version" ]; then
  base="${BASE_TAGGED}/${version}"
  if ! download "${base}/SHA256SUMS" "$tmpdir/.probe" 2>/dev/null; then
    gh_ready || fail "could not download release ${version} anonymously — if the repo is private, install the GitHub CLI and run: gh auth login"
    mode="gh"
  fi
else
  if download "${BASE_LATEST}/manifest.json" "$tmpdir/manifest.json" 2>/dev/null; then
    version=$(manifest_version "$tmpdir/manifest.json")
    [ -n "$version" ] || fail "could not parse version from release manifest"
    base="${BASE_TAGGED}/${version}"
  else
    gh_ready || fail "could not reach the latest release anonymously — if the repo is private, install the GitHub CLI and run: gh auth login"
    mode="gh"
    version=$(gh release view --repo "$REPO" --json tagName --jq .tagName) \
      || fail "could not resolve the latest release via gh"
    [ -n "$version" ] || fail "no releases found on $REPO"
  fi
fi

fetch_asset() { # $1 = asset name → $tmpdir/$1
  if [ "$mode" = "gh" ]; then
    gh release download "$version" --repo "$REPO" --pattern "$1" --output "$tmpdir/$1"
  else
    download "${base}/$1" "$tmpdir/$1"
  fi
}

asset="agp_${version}_${platform}.tar.gz"
say "Installing AGP CLI ${version} (${platform})"
[ "$mode" = "gh" ] && say "Using authenticated GitHub CLI (private repository)."

# ── Download and verify ──────────────────────────────────────────────────────
fetch_asset "SHA256SUMS" || fail "could not download SHA256SUMS for ${version}"
fetch_asset "$asset" \
  || fail "could not download ${asset} — release ${version} may not include ${platform}"

want=$(awk -v f="$asset" '$2 == f || $2 == "*"f {print $1}' "$tmpdir/SHA256SUMS" | head -n 1)
[ -n "$want" ] || fail "no checksum entry for ${asset} in SHA256SUMS"
got=$(checksum "$tmpdir/${asset}")
[ "$want" = "$got" ] || fail "checksum mismatch for ${asset} (expected ${want}, got ${got}) — aborting"
say "Checksum verified."

tar -xzf "$tmpdir/${asset}" -C "$tmpdir"
[ -f "$tmpdir/agp" ] || fail "archive did not contain the agp binary"
chmod +x "$tmpdir/agp"

# ── Install ──────────────────────────────────────────────────────────────────
install_dir="${AGP_INSTALL_DIR:-}"
if [ -z "$install_dir" ]; then
  if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
    install_dir="/usr/local/bin"
  else
    install_dir="${HOME}/.local/bin"
  fi
fi
mkdir -p "$install_dir"

# Remove before copy: overwriting an existing binary in place invalidates
# macOS's cached code signature and the kernel kills the process with SIGKILL.
rm -f "$install_dir/agp"
cp "$tmpdir/agp" "$install_dir/agp"

"$install_dir/agp" help >/dev/null 2>&1 || fail "installed binary failed to run"

say ""
say "agp ${version} installed to ${install_dir}/agp"

# ── PATH setup ───────────────────────────────────────────────────────────────
# Three cases: already on PATH (nothing to do); user opted out
# (AGP_NO_MODIFY_PATH); otherwise persist to the shell profile so new shells
# work, and print the one line that activates the current shell. A piped
# installer runs in a subshell and cannot change the parent shell's PATH — no
# installer can — so the current session needs that one line or a new tab.
activate_line="export PATH=\"${install_dir}:\$PATH\""

case ":${PATH}:" in
  *":${install_dir}:"*)
    say ""
    say "agp is on your PATH — you're ready to go." ;;
  *)
    if [ -n "${AGP_NO_MODIFY_PATH:-}" ]; then
      say ""
      say "${install_dir} is not on your PATH (AGP_NO_MODIFY_PATH set — profile left untouched)."
      say "Add it with:  ${activate_line}"
    else
      # Choose the profile file for the user's shell.
      is_fish=0
      case "$(basename "${SHELL:-sh}")" in
        zsh)  profile="${ZDOTDIR:-$HOME}/.zshrc" ;;
        bash) if [ -f "$HOME/.bash_profile" ]; then profile="$HOME/.bash_profile"; else profile="$HOME/.bashrc"; fi ;;
        fish) profile="$HOME/.config/fish/config.fish"; is_fish=1 ;;
        *)    profile="$HOME/.profile" ;;
      esac
      [ "$is_fish" -eq 1 ] && activate_line="fish_add_path ${install_dir}"

      mkdir -p "$(dirname "$profile")" 2>/dev/null || true
      added="no"
      if [ -e "$profile" ] && grep -F "$install_dir" "$profile" >/dev/null 2>&1; then
        added="already"
      elif { printf '\n# Added by AGP install.sh (https://github.com/%s)\n%s\n' "$REPO" "$activate_line" >> "$profile"; } 2>/dev/null; then
        added="yes"
      fi

      say ""
      case "$added" in
        yes)     say "Added ${install_dir} to your PATH in ${profile}." ;;
        already) say "${install_dir} is already configured in ${profile}." ;;
        *)       say "Could not update ${profile} automatically — add the line below yourself." ;;
      esac
      say "New terminals will find agp automatically. To use it in THIS terminal now, run:"
      say ""
      say "    ${activate_line}"
    fi ;;
esac

say ""
say "Next steps:"
say "  agp init        # initialize ~/.agp (secrets, config, CLI profile)"
say "  agp fetch all   # download the AGP services for your platform"
say "  agp start all   # start the stack"
say "  agp setup --agent-id my-agent --client claude-desktop"
