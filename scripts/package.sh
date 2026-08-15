#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ============================================================
# 参数解析
# ============================================================
INCLUDE_FILES=("CMakeLists.txt" "pyproject.toml" "ws_tools" ".ln_py_packages" "uv.lock")
PACKAGES=()

usage() {
    echo "Usage: ws_tools package [-p package1,package2,...] [-h]"
    echo "  -p    Comma-separated list of packages under src/ to include"
    echo "        If omitted, all packages under src/ are included"
    echo "  -h    Show this help message"
    echo ""
    echo "Available packages:"
    for d in "$SCRIPT_DIR/src"/*/; do
        [ -d "$d" ] && echo "  $(basename "$d")"
    done
    exit 0
}

shift
while getopts "p:h" opt "$@"; do
    case $opt in
        p) IFS=',' read -ra PACKAGES <<< "$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# ============================================================
# 自动添加 *_bringup 功能包
# ============================================================
BRINGUP_PKG=""
for d in "$SCRIPT_DIR/src"/*_bringup; do
    [[ -d "$d" ]] && BRINGUP_PKG="$(basename "$d")" && break
done

if [[ -n "$BRINGUP_PKG" && ${#PACKAGES[@]} -gt 0 ]]; then
    found=false
    for pkg in "${PACKAGES[@]}"; do
        [[ "$pkg" == "$BRINGUP_PKG" ]] && found=true && break
    done
    if [[ "$found" == false ]]; then
        echo "Auto-including required package: $BRINGUP_PKG"
        PACKAGES+=("$BRINGUP_PKG")
    fi
fi

# ============================================================
# 校验包目录
# ============================================================
for pkg in "${PACKAGES[@]}"; do
    if [ ! -d "$SCRIPT_DIR/src/$pkg" ]; then
        echo "Error: package 'src/$pkg' not found."
        exit 1
    fi
done

# ============================================================
# 提取版本号
# ============================================================
VERSION="$(grep -oP 'set\(PROJECT_VERSION\s+\K[0-9]+\.[0-9]+\.[0-9]+' "$SCRIPT_DIR/CMakeLists.txt")"
if [ -z "$VERSION" ]; then
    echo "Error: cannot extract PROJECT_VERSION from CMakeLists.txt"
    exit 1
fi

WORKSPACE_NAME="$(basename "$SCRIPT_DIR")"
OUTPUT="$SCRIPT_DIR/${WORKSPACE_NAME}_${VERSION}.zip"

# ============================================================
# 过滤不存在的 include 文件
# ============================================================
VALID_FILES=()
for f in "${INCLUDE_FILES[@]}"; do
    if [ -f "$SCRIPT_DIR/$f" ]; then
        VALID_FILES+=("$f")
    else
        echo "Warning: '$f' not found, skipping."
    fi
done
INCLUDE_FILES=("${VALID_FILES[@]}")

# ============================================================
# 打包
# ============================================================
cd "$SCRIPT_DIR"

# 构建排除参数（排除 scripts/update.sh，包含敏感 GitLab 地址）
EXCLUDE_ARGS=(-x "scripts/update.sh")

if [ ${#PACKAGES[@]} -eq 0 ]; then
    echo "Packing all packages..."
    zip -r "$OUTPUT" src/ scripts/ dpkgs/ "${INCLUDE_FILES[@]}" "${EXCLUDE_ARGS[@]}"
else
    echo "Packing packages: ${PACKAGES[*]}"
    PKG_DIRS=()
    for pkg in "${PACKAGES[@]}"; do
        PKG_DIRS+=("src/$pkg")
    done
    zip -r "$OUTPUT" "${PKG_DIRS[@]}" scripts/ dpkgs/ "${INCLUDE_FILES[@]}" "${EXCLUDE_ARGS[@]}"
fi

echo "Done: $OUTPUT"
