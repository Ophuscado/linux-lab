#!/usr/bin/env bash
# apps.sh: the programs this machine should have, by group: what the owner's Mac had
# (Homebrew formulae and casks, Apple's own apps) and what stands in for it here. Fedora's own
# aarch64 packages first (native, updated with the system), Flathub when Fedora has none,
# a language's own installer (npm, cargo, pip) last.
#
#   apps.sh list [GROUP]        the groups, each program with what it replaces and why
#   apps.sh check [GROUP]       installed, installable (from where) or not for aarch64; read-only
#   apps.sh install GROUP...    install what is missing of those groups (asks sudo; Flathub apps
#                               system-wide, from the remote settings.sh adds; the language
#                               installers as yourself)
#
# Not here on purpose: libraries the Mac's formulae pulled in (abseil, boost, ...; Fedora
# installs them as dependencies), macOS-only programs (container, terminal-notifier,
# retroarch-metal, utm), and what Fedora Asahi or KDE already brings (curl, git, openssh,
# rsync, gnupg2, smartmontools, sing-box, 7zip, ...). x86-only programs (DaVinci Resolve,
# Bitwig, Tor Browser, Affinity) would need FEX in a 4K-page VM; see the board.
#
# Kinds: dnf (Fedora package, or what provides that name), flatpak (Flathub id), npm, cargo, pip
# (through pipx, each tool in its own environment), go, release (a project's own download: its
# latest GitHub release for the ones in RELEASES, else by hand), fonts.sh. npm, cargo, pip, go and
# release install for you alone and put their programs in ~/.local/bin, the one folder editors and
# shells find them in; the installer each needs (npm, cargo, pipx, go) comes from Fedora first.
# A sixth field names the command when it differs from the package (taplo-cli gives taplo).

set -euo pipefail
die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }
[[ $EUID != 0 ]] || die "run it as yourself; it asks sudo for the Fedora packages"

# group|kind|name|replaces on the Mac|why
CATALOG=$(cat <<'EOF'
shell|dnf|fish|fish|the shell
shell|dnf|tmux|tmux|
shell|dnf|btop|btop|
shell|dnf|fd-find|fd|
shell|dnf|ripgrep|ripgrep|
shell|dnf|fzf|fzf|
shell|dnf|jq|jq|
shell|go|github.com/jesseduffield/lazygit@latest|lazygit|not in Fedora|lazygit
shell|dnf|glow|glow|
shell|dnf|ncdu|ncdu|
shell|dnf|dua-cli|dua-cli|
shell|dnf|tree|tree|
shell|dnf|tealdeer|tlrc|tldr pages
shell|dnf|parallel|parallel|
shell|dnf|rlwrap|rlwrap|
shell|dnf|asciinema|asciinema|
shell|dnf|translate-shell|translate-shell|
shell|dnf|fdupes|fdupes|
shell|dnf|bchunk|bchunk|
shell|dnf|qrencode|qrencode|
shell|dnf|git-lfs|git-lfs|
shell|go|github.com/maaslalani/slides@latest|slides|terminal slides; not in Fedora|slides
editor|dnf|neovim|neovim|
editor|dnf|tree-sitter-cli|tree-sitter-cli|
editor|release|lua-language-server|lua-language-server|not in Fedora: its linux-arm64 release (LuaLS/lua-language-server)
editor|dnf|rust-analyzer|rust-analyzer|
editor|dnf|clang-tools-extra|llvm (clangd)|C and C++ language server
editor|go|golang.org/x/tools/gopls@v0.23.0|gopls|v0.24 needs Go 1.27, Fedora 44 has 1.26|gopls
editor|dnf|python3-lsp-server|python-lsp-server|
editor|cargo|texlab|texlab|not in Fedora
editor|cargo|taplo-cli|taplo|TOML; not in Fedora|taplo
editor|npm|bash-language-server|bash-language-server|
editor|npm|typescript-language-server|typescript-language-server|
editor|npm|typescript|typescript|
editor|npm|yaml-language-server|yaml-language-server|
editor|npm|vscode-langservers-extracted|vscode-langservers-extracted|HTML, CSS, JSON, ESLint
editor|npm|dockerfile-language-server-nodejs|dockerfile-language-server|
editor|npm|@ansible/ansible-language-server|ansible-language-server|
editor|npm|fish-lsp|fish-lsp|
editor|go|github.com/sqls-server/sqls@latest|sql-language-server|SQL: init.lua runs sqls|sqls
editor|npm|gh-actions-language-server|actions-languageserver|GitHub Actions: the standalone server init.lua runs
editor|npm|@postgres-language-server/cli|postgres-language-server|Postgres
editor|pip|cmake-language-server|cmake-language-server|
editor|pip|fortls|fortls|Fortran
editor|cargo|asm-lsp|asm-lsp|
editor|cargo|harper-ls|harper|grammar|harper-ls
editor|release|marksman|marksman|Markdown; written in F#, not a crate: its linux-arm64 release (artempyanykh/marksman)
dev|dnf|gcc-c++|(Xcode tools)|
dev|dnf|gdb|(Xcode tools)|debugger
dev|dnf|lldb|(Xcode tools)|debugger (LLVM)
dev|dnf|strace|(Xcode tools)|system calls
dev|dnf|ltrace|(Xcode tools)|library calls
dev|dnf|valgrind|(Xcode tools)|memory errors
dev|dnf|perf|(Xcode tools)|profiler
dev|dnf|clang|llvm|
dev|dnf|cmake|cmake|
dev|dnf|autoconf|autoconf|
dev|dnf|automake|(autoconf)|
dev|dnf|libtool|libtool|
dev|dnf|golang|go|
dev|dnf|rust|(rustup)|
dev|dnf|cargo|(rustup)|
dev|dnf|nodejs|node|
dev|npm|deno|deno|not in Fedora; npm fetches its binary
dev|npm|bun|bun|or its release binary
dev|dnf|python3|python@3.14|
dev|dnf|python3.13|python@3.13|
dev|dnf|python3.12|python@3.12|
dev|dnf|python3-tkinter|python-tk@3.14|
dev|dnf|black|black|
dev|dnf|python3-httpx|httpx|
dev|pip|csvkit|csvkit|not in Fedora
dev|dnf|java-latest-openjdk-devel|openjdk|
dev|dnf|dotnet-sdk-9.0|dotnet@9|
dev|dnf|php-cli|php|
dev|dnf|luajit|luajit|
dev|dnf|z3|z3|
dev|dnf|sqlite|sqlite|
dev|release|duckdb|duckdb|not in Fedora: its linux-aarch64 release
dev|dnf|postgresql-server|postgresql@18|
dev|dnf|unixODBC|unixodbc|
dev|dnf|freetds|freetds|
dev|dnf|podman|container|containers, Docker's command line through podman-docker
dev|dnf|podman-docker|container|
dev|dnf|ansible|ansible|
dev|dnf|imhex|imhex|hex editor
dev|npm|@playwright/cli|playwright-cli|
dev|npm|@playwright/mcp|playwright-mcp|
media|dnf|ffmpeg-free|ffmpeg|Fedora's build; RPM Fusion's ffmpeg has the patented codecs
media|dnf|yt-dlp|yt-dlp|
media|dnf|pandoc|pandoc|
media|dnf|tesseract|tesseract|
media|dnf|tesseract-langpack-spa|tesseract-lang|Spanish; English comes with it
media|dnf|poppler-utils|poppler|
media|dnf|tidy|tidy-html5|
media|release|epubcheck|epubcheck|not in Fedora: its release (a Java jar)
net|dnf|rclone|rclone|
net|dnf|wget2-wget|wget|
net|dnf|lynx|lynx|
net|dnf|telnet|telnet|
net|dnf|proxychains-ng|proxychains-ng|
net|dnf|net-snmp-utils|net-snmp|
net|dnf|ldns-utils|ldns|
net|dnf|lynis|lynis|security audit
net|dnf|qbittorrent|qbittorrent|
net|dnf|electrum|electrum|
net|dnf|chromium|chromium|
net|flatpak|io.gitlab.news_flash.NewsFlash|netnewswire|feeds (KDE's own: Akregator)
creative|dnf|inkscape|affinity-designer|vector drawing
creative|dnf|gimp|affinity-photo|photo editing
creative|dnf|krita|affinity-photo|painting
creative|dnf|darktable|(Photos, raw)|raw photos
creative|dnf|scribus|affinity-publisher|page layout
creative|dnf|digikam|(Photos)|photo library
3d|flatpak|org.freecad.FreeCAD|freecad|parametric CAD; not in Fedora for aarch64
3d|dnf|blender|(none)|3D modelling, animation
3d|dnf|openscad|(none)|CAD as code
3d|dnf|prusa-slicer|(none)|3D printing
electronics|dnf|kicad|(none)|schematics and boards
electronics|dnf|ngspice|(none)|circuit simulation
electronics|dnf|pulseview|(none)|logic analyser (sigrok)
electronics|flatpak|one.flipperzero.qFlipper|qflipper|Flipper Zero
video|dnf|obs-studio|obs|recording, streaming
video|dnf|kdenlive|(Final Cut Pro)|video editing, KDE's
video|dnf|mpv|vlc|player
video|dnf|vlc|vlc|player
audio|dnf|ardour8|(Logic Pro)|recording and mixing
audio|dnf|lmms|(GarageBand)|loops and beats
audio|dnf|audacity|(none)|sound editing
audio|dnf|musescore|(none)|notation
audio|flatpak|studio.kx.carla|(none)|plug-in host; not in Fedora
remote|dnf|krdc|(Screen Sharing)|KDE's VNC and RDP viewer
remote|dnf|krdp|(Screen Sharing)|KDE's RDP server for this desktop
remote|dnf|virt-manager|utm|virtual machines on KVM
remote|dnf|qemu-kvm|utm|
games|flatpak|org.libretro.RetroArch|retroarch-metal|the Mac's RetroArch folder restores into it
fonts|fonts.sh|nerd Hack|font-hack-nerd-font|Hack Nerd Font from its release: fonts.sh nerd Hack
EOF
)

rows() { awk -F'|' -v g="${1:-}" 'NF >= 4 && (g == "" || $1 == g)' <<<"$CATALOG"; }
groups() { rows | cut -d'|' -f1 | uniq; }

list() {
    local g
    for g in ${1:-$(groups)}; do
        echo "$g:"
        rows "$g" | awk -F'|' '{printf "  %-7s %-40s %s%s\n", $2, $3, ($4 == $3 ? "" : "for " $4), ($5 == "" ? "" : "  (" $5 ")")}'
    done
}

# check prints one line per program: installed, dnf / flatpak / npm / cargo / pip / go (can be
# installed from there), release / fonts.sh (another way), or missing (nothing for this machine).
# A dnf name no package has is looked up again as a capability (nodejs is nodejs22's), so
# "dnf:NAME" names the package that would come.
check() {
    local g k n c s p avail flat=""
    avail=$(rows "${1:-}" | awk -F'|' '$2 == "dnf" {print $3}' | xargs -r dnf repoquery -q --available --arch "$(uname -m),noarch" --qf '%{name}\n' 2>/dev/null | sort -u || true)
    [[ -n $avail ]] || ! rows "${1:-}" | grep -q '|dnf|' || echo "WARN: dnf repoquery answered nothing (network?); dnf rows show as missing" >&2
    if rows "${1:-}" | grep -q '|flatpak|'; then flat=$(flatpak remote-ls flathub --app --arch="$(uname -m)" --columns=application 2>/dev/null || true); fi
    while IFS="|" read -r g k n _ _ c; do
        c=${c:-${n##*/}}
        c=${c%@*}
        case $k in
        dnf)
            if rpm -q --whatprovides "$n" >/dev/null 2>&1; then s=installed
            elif grep -qxF "$n" <<<"$avail"; then s=dnf
            elif p=$(dnf repoquery -q --available --arch "$(uname -m),noarch" --whatprovides "$n" --qf '%{name}\n' 2>/dev/null | head -n 1) && [[ -n $p ]]; then s=dnf:$p
            else s=missing; fi
            ;;
        flatpak) if flatpak info "$n" >/dev/null 2>&1; then s=installed; elif grep -qxF "$n" <<<"$flat"; then s=flatpak; else s=missing; fi ;;
        npm) if npm ls -g --prefix "$HOME/.local" --depth=0 "$n" >/dev/null 2>&1; then s=installed; else s=npm; fi ;;
        cargo | pip | go) if command -v "$c" >/dev/null || [[ -x $HOME/.local/bin/$c || -x $HOME/.cargo/bin/$c || -x $HOME/go/bin/$c ]]; then s=installed; else s=$k; fi ;;
        release) if command -v "$c" >/dev/null || [[ -x $HOME/.local/bin/$c ]]; then s=installed; else s=release; fi ;;
        fonts.sh) if fc-list : family 2>/dev/null | grep -qi "${n#* } Nerd Font"; then s=installed; else s=fonts.sh; fi ;;
        esac
        printf '%-12s %-10s %s\n' "$g" "$s" "$n"
    done < <(rows "${1:-}")
}

# Programs installed from their project's latest GitHub release: NAME="OWNER/REPO tar|bin". tar: the
# archive unpacked into ~/.local/share/NAME, with ~/.local/bin/NAME running its bin/NAME; bin: the
# file itself is the program. The asset is the one named for linux and this CPU (arm64 or x64),
# checked against the sha256 digest GitHub keeps for it when there is one.
declare -A RELEASES=(
    [lua-language-server]="LuaLS/lua-language-server tar"
    [marksman]="artempyanykh/marksman bin"
)
release_install() {
    local n=$1 repo how cpu tmp asset url sum
    read -r repo how <<<"${RELEASES[$n]}"
    case $(uname -m) in aarch64) cpu=arm64 ;; x86_64) cpu=x64 ;; *) echo "no $n release for $(uname -m)" >&2; return 1 ;; esac
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/release.json" "https://api.github.com/repos/$repo/releases/latest" || { rm -rf "$tmp"; return 1; }
    read -r asset url sum < <(python3 -c '
import json, re, sys
rel, cpu, how = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3]
want = re.compile(r"linux-%s%s$" % (cpu, r"\.tar\.gz" if how == "tar" else ""))
hits = [a for a in rel.get("assets", []) if want.search(a["name"])]
if len(hits) != 1:
    sys.exit("%s %s: %d assets match %s among %s" % (sys.argv[4], rel.get("tag_name"), len(hits), want.pattern, [a["name"] for a in rel.get("assets", [])]))
a = hits[0]
print(a["name"], a["browser_download_url"], (a.get("digest") or "-").removeprefix("sha256:"))' "$tmp/release.json" "$cpu" "$how" "$repo") || { rm -rf "$tmp"; return 1; }
    curl -fsSL -o "$tmp/$asset" "$url" || { rm -rf "$tmp"; return 1; }
    if [[ $sum != - ]]; then
        echo "$sum  $tmp/$asset" | sha256sum -c --quiet - || { echo "$asset does not match GitHub's sha256" >&2; rm -rf "$tmp"; return 1; }
    else
        echo "WARN: GitHub keeps no digest for $asset; installed unchecked" >&2
    fi
    mkdir -p "$HOME/.local/bin" "$HOME/.local/share"
    case $how in
    tar)
        rm -rf "$HOME/.local/share/$n.new"
        mkdir -p "$HOME/.local/share/$n.new"
        tar -xzf "$tmp/$asset" -C "$HOME/.local/share/$n.new" && [[ -x $HOME/.local/share/$n.new/bin/$n ]] || { rm -rf "$tmp" "$HOME/.local/share/$n.new"; echo "$asset has no bin/$n" >&2; return 1; }
        rm -rf "$HOME/.local/share/$n"
        mv "$HOME/.local/share/$n.new" "$HOME/.local/share/$n"
        printf '#!/bin/sh\n# Written by apps.sh: %s from %s\nexec "$HOME/.local/share/%s/bin/%s" "$@"\n' "$n" "$asset" "$n" "$n" >"$HOME/.local/bin/$n"
        chmod 755 "$HOME/.local/bin/$n"
        ;;
    bin) command install -m 755 "$tmp/$asset" "$HOME/.local/bin/$n" ;; # command: install() is this script's
    esac
    rm -rf "$tmp"
    echo "$n: $asset"
}

install() {
    local g dnfs=() rest=() k n s
    [[ $# -gt 0 ]] || die "apps.sh install GROUP... (apps.sh list shows them)"
    for g in "$@"; do
        [[ -n $(rows "$g") ]] || die "no group $g"
        while read -r _ s n; do
            case $s in
            dnf) dnfs+=("$n") ;;
            dnf:*) dnfs+=("${s#dnf:}") ;;
            flatpak | npm | cargo | pip | go) rest+=("$s|$n") ;;
            release) if [[ -n ${RELEASES[$n]:-} ]]; then rest+=("release|$n"); else echo "by hand for now: $n (apps.sh list shows where)"; fi ;;
            fonts.sh) "$(dirname "$0")/../desktop/fonts.sh" ${n} ;;
            esac
        done < <(check "$g")
    done
    # The installers themselves, from Fedora, when a group needs one that is not here.
    for k in npm:nodejs-npm cargo:cargo pip:pipx go:golang; do
        if printf '%s\n' "${rest[@]}" | grep -q "^${k%%:*}|" && ! command -v "$([[ ${k%%:*} == pip ]] && echo pipx || echo "${k%%:*}")" >/dev/null; then
            dnfs+=("${k#*:}")
        fi
    done
    ((${#dnfs[@]} == 0)) || sudo dnf install -y "${dnfs[@]}"
    mkdir -p "$HOME/.local/bin"
    # One tool that fails does not keep the others out; the failed ones are named at the end.
    local failed=()
    for k in "${rest[@]}"; do
        n=${k#*|}
        case ${k%%|*} in
        flatpak) sudo flatpak install -y --system flathub "$n" ;;
        npm) npm install -g --prefix "$HOME/.local" "$n" ;;
        cargo) cargo install --locked --root "$HOME/.local" "$n" ;;
        pip) pipx install "$n" ;;
        go) GOBIN=$HOME/.local/bin go install "$n" ;;
        release) release_install "$n" ;;
        esac || failed+=("$n")
    done
    echo "installed: ${#dnfs[@]} Fedora packages, $((${#rest[@]} - ${#failed[@]})) others"
    ((${#failed[@]} == 0)) || die "not installed: ${failed[*]}"
}

case ${1:-} in
list) list "${2:-}" ;;
check) check "${2:-}" ;;
install) shift; install "$@" ;;
*)
    echo "usage: $0 {list [GROUP] | check [GROUP] | install GROUP...}" >&2
    exit 2
    ;;
esac
