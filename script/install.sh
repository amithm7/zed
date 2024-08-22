#!/usr/bin/env sh
set -eu

# Downloads the latest tarball from https://zed.dev/releases and unpacks it
# into ~/.local/. If you'd prefer to do this manually, instructions are at
# https://zed.dev/docs/linux.

main() {
    operation="${1:-install}"
    platform="$(uname -s)"
    arch="$(uname -m)"
    channel="${ZED_CHANNEL:-stable}"
    temp="$(mktemp -d "/tmp/zed-XXXXXX")"

    [ "$operation" = install ] || [ "$operation" = uninstall ] || {
        echo "Unknown operation '$operation'"
        echo "Available operations: 'install' 'uninstall'"
        exit 1
    }

    if [ "$platform" = "Darwin" ]; then
        platform="macos"
    elif [ "$platform" = "Linux" ]; then
        platform="linux"
    else
        echo "Unsupported platform $platform"
        exit 1
    fi

    case "$platform-$arch" in
        macos-arm64* | linux-arm64* | linux-armhf | linux-aarch64)
            arch="aarch64"
            ;;
        macos-x86* | linux-x86* | linux-i686*)
            arch="x86_64"
            ;;
        *)
            echo "Unsupported platform or architecture"
            exit 1
            ;;
    esac

    if which curl >/dev/null 2>&1; then
        curl () {
            command curl -fL "$@"
        }
    elif which wget >/dev/null 2>&1; then
        curl () {
            wget -O- "$@"
        }
    else
        echo "Could not find 'curl' or 'wget' in your path"
        exit 1
    fi

    "$platform" "$@"

    if [ "$operation" = install ] && [ "$(which "zed")" = "$HOME/.local/bin/zed" ]; then
        echo "Zed has been installed. Run with 'zed'"
    elif [ "$operation" = install ]; then
        echo "To run Zed from your terminal, you must add ~/.local/bin to your PATH"
        echo "Run:"

        case "$SHELL" in
            *zsh)
                echo "   echo 'export PATH=\$HOME/.local/bin:\$PATH' >> ~/.zshrc"
                echo "   source ~/.zshrc"
                ;;
            *fish)
                echo "   fish_add_path -U $HOME/.local/bin"
                ;;
            *)
                echo "   echo 'export PATH=\$HOME/.local/bin:\$PATH' >> ~/.bashrc"
                echo "   source ~/.bashrc"
                ;;
        esac

        echo "To run Zed now, '~/.local/bin/zed'"
    else
        echo "Uninstall completed."
    fi
}

linux() {
    [ "$operation" = install ] && if [ -n "${ZED_BUNDLE_PATH:-}" ]; then
        cp "$ZED_BUNDLE_PATH" "$temp/zed-linux-$arch.tar.gz"
    else
        echo "Downloading Zed"
        curl "https://zed.dev/api/releases/$channel/latest/zed-linux-$arch.tar.gz" > "$temp/zed-linux-$arch.tar.gz"
    fi

    suffix=""
    if [ "$channel" != "stable" ]; then
        suffix="-$channel"
    fi

    appid=""
    case "$channel" in
      stable)
        appid="dev.zed.Zed"
        ;;
      nightly)
        appid="dev.zed.Zed-Nightly"
        ;;
      preview)
        appid="dev.zed.Zed-Preview"
        ;;
      dev)
        appid="dev.zed.Zed-Dev"
        ;;
      *)
        echo "Unknown release channel: ${channel}. Using stable app ID."
        appid="dev.zed.Zed"
        ;;
    esac

    rm -rf "$HOME/.local/zed$suffix.app"

    [ "$operation" = install ] && {
        # Unpack
        mkdir -p "$HOME/.local/zed$suffix.app" && tar -xzf "$temp/zed-linux-$arch.tar.gz" -C "$HOME/.local/"

        # Setup ~/.local directories
        mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"

        # Link the binary
        if [ -f "$HOME/.local/zed$suffix.app/bin/zed" ]; then
            ln -sf "$HOME/.local/zed$suffix.app/bin/zed" "$HOME/.local/bin/zed"
        else
            # support for versions before 0.139.x.
            ln -sf "$HOME/.local/zed$suffix.app/bin/cli" "$HOME/.local/bin/zed"
        fi
    }

    [ "$operation" = uninstall ] && rm -f "$HOME/.local/bin/zed"

    # Copy .desktop file
    desktop_file_path="$HOME/.local/share/applications/${appid}.desktop"

    [ "$operation" = install ] && {
        cp "$HOME/.local/zed$suffix.app/share/applications/zed$suffix.desktop" "${desktop_file_path}"
        sed -i "s|Icon=zed|Icon=$HOME/.local/zed$suffix.app/share/icons/hicolor/512x512/apps/zed.png|g" "${desktop_file_path}"
        sed -i "s|Exec=zed|Exec=$HOME/.local/zed$suffix.app/libexec/zed-editor|g" "${desktop_file_path}"
    }

    [ "$operation" = uninstall ] && rm -f "$desktop_file_path"

    return 0
}

macos() {
    echo "Downloading Zed"
    curl "https://zed.dev/api/releases/$channel/latest/Zed-$arch.dmg" > "$temp/Zed-$arch.dmg"

    hdiutil attach -quiet "$temp/Zed-$arch.dmg" -mountpoint "$temp/mount"
    app="$(cd "$temp/mount/"; echo *.app)"

    [ "$operation" = install ] && echo "Installing $app"

    if [ -d "/Applications/$app" ]; then
        echo "Removing existing $app"
        rm -rf "/Applications/$app"
    fi

    [ "$operation" = install ] && ditto "$temp/mount/$app" "/Applications/$app"

    hdiutil detach -quiet "$temp/mount"

    [ "$operation" = install ] && {
        mkdir -p "$HOME/.local/bin"
        # Link the binary
        ln -sf "/Applications/$app/Contents/MacOS/cli" "$HOME/.local/bin/zed"
    }

    [ "$operation" = uninstall ] && rm -f "$HOME/.local/bin/zed"

    return 0
}

main "$@"
