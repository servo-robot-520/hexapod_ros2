#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DPKGS_DIR="$SCRIPT_DIR/dpkgs"

# ============================================================
# 参数解析
# ============================================================
usage() {
    echo "Usage: ws_tools dep_install [-h]"
    echo "  Install packages from dpkgs/ directory"
    echo ""
    echo "  dpkgs/"
    echo "    apt.txt    Each line is an apt package name"
    echo "    deb/       .deb files organized by architecture"
    echo "      amd64/"
    echo "      arm64/"
    echo "      ..."
    echo ""
    echo "  -h    Show this help message"
    exit 0
}

shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        *)
            echo "Error: unknown option '$1'"
            usage
            ;;
    esac
done

# ============================================================
# 检查 dpkgs 目录
# ============================================================
if [[ ! -d "$DPKGS_DIR" ]]; then
    echo "Error: dpkgs/ directory not found in workspace root."
    echo ""
    echo "Please create the following structure:"
    echo ""
    echo "  dpkgs/"
    echo "  ├── apt.txt          # One apt package per line"
    echo "  └── deb/"
    echo "      ├── amd64/       # .deb files for x86_64"
    echo "      │   ├── pkg1.deb"
    echo "      │   └── pkg2.deb"
    echo "      └── arm64/       # .deb files for ARM64"
    echo "          └── ..."
    echo ""
    echo "Example apt.txt:"
    echo "  ros-humble-nav2-bringup"
    echo "  ros-humble-slam-toolbox"
    echo "  # comments and empty lines are ignored"
    exit 1
fi

# ============================================================
# 安装 apt 包
# ============================================================
APT_FILE="$DPKGS_DIR/apt.txt"
if [[ -f "$APT_FILE" ]]; then
    APT_PACKAGES=()
    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/#.*//' | xargs)
        [[ -z "$line" ]] && continue
        APT_PACKAGES+=("$line")
    done < "$APT_FILE"

    if [[ ${#APT_PACKAGES[@]} -gt 0 ]]; then
        echo "Installing apt packages: ${APT_PACKAGES[*]}"
        sudo apt update
        sudo apt install -y "${APT_PACKAGES[@]}"
        echo "Apt packages installed."
    else
        echo "No apt packages defined in dpkgs/apt.txt."
    fi
else
    echo "dpkgs/apt.txt not found, skipping apt packages."
fi

# ============================================================
# 安装 deb 包
# ============================================================
DEB_DIR="$DPKGS_DIR/deb"
if [[ -d "$DEB_DIR" ]]; then
    ARCH=$(dpkg --print-architecture)
    ARCH_DIR="$DEB_DIR/$ARCH"

    if [[ -d "$ARCH_DIR" ]]; then
        DEB_FILES=("$ARCH_DIR"/*.deb)

        if [[ -e "${DEB_FILES[0]}" ]]; then
            echo "Installing deb packages for $ARCH..."
            for deb_file in "${DEB_FILES[@]}"; do
                echo "  Installing: $(basename "$deb_file")"
                sudo dpkg -i "$deb_file" || true
            done
            echo "Fixing dependencies..."
            sudo apt-get install -f -y
            echo "Deb packages installed."
        else
            echo "No .deb files found in dpkgs/deb/$ARCH/."
        fi
    else
        echo "No deb directory for architecture '$ARCH' (dpkgs/deb/$ARCH/ not found)."
        echo "Available architectures:"
        ls -1 "$DEB_DIR" 2>/dev/null || echo "  (none)"
    fi
else
    echo "dpkgs/deb/ not found, skipping deb packages."
fi

echo "Done."
