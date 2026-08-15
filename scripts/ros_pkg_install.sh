#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/_common.sh"

ROS2_PKGS_DIR="$HOME/ros2_pkgs"

# ============================================================
# 参数解析
# ============================================================
PACKAGES_TO_INSTALL=()

usage() {
    echo "Usage: ws_tools ros_pkg_install [-trac_ik] [-h]"
    echo ""
    echo "Options:"
    echo "  -trac_ik    Install trac_ik package"
    echo "  -h          Show this help message"
    echo ""
    echo "Available packages:"
    echo "  trac_ik     Traclabs inverse kinematics solver"
    exit 0
}

shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        -trac_ik)
            PACKAGES_TO_INSTALL+=("trac_ik")
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: unknown option '$1'"
            usage
            ;;
    esac
done

if [[ ${#PACKAGES_TO_INSTALL[@]} -eq 0 ]]; then
    echo "No package specified. Use -h to see available packages."
    exit 1
fi

# ============================================================
# 安装函数：trac_ik
# ============================================================
install_trac_ik() {
    local PKG_DIR="$ROS2_PKGS_DIR/trac_ik"
    local SRC_DIR="$PKG_DIR/src"

    if [[ ! -d "$SRC_DIR/trac_ik" ]]; then
        mkdir -p "$SRC_DIR"
        echo "Cloning trac_ik..."
        git clone https://bitbucket.org/traclabs/trac_ik.git "$SRC_DIR"
    else
        echo "trac_ik already cloned, pulling latest..."
        git -C "$SRC_DIR/trac_ik" pull
    fi

    echo "Checking header compatibility..."
    if [[ ! -f "/opt/ros/humble/include/urdf/urdf/model.hpp" ]]; then
        echo "urdf/model.hpp not found, patching trac_ik source files..."
        find "$SRC_DIR" -name "*.cpp" -o -name "*.h" -o -name "*.hpp" | while read -r src_file; do
            if grep -q '#include <urdf/model.hpp>' "$src_file" 2>/dev/null; then
                sed -i 's|#include <urdf/model.hpp>|#include <urdf/model.h>|g' "$src_file"
                echo "  [PATCH] $src_file"
            fi
        done
    fi

    if [[ ! -f "/opt/ros/humble/include/moveit/kinematics_base/kinematics_base.hpp" ]]; then
        echo "moveit/kinematics_base/kinematics_base.hpp not found, patching trac_ik source files..."
        find "$SRC_DIR" -name "*.cpp" -o -name "*.h" -o -name "*.hpp" | while read -r src_file; do
            if grep -q '#include <moveit/kinematics_base/kinematics_base.hpp>' "$src_file" 2>/dev/null; then
                sed -i 's|#include <moveit/kinematics_base/kinematics_base.hpp>|#include <moveit/kinematics_base/kinematics_base.h>|g' "$src_file"
                echo "  [PATCH] $src_file"
            fi
        done
    fi

    if [[ ! -f "/opt/ros/humble/include/moveit/robot_model/robot_model.hpp" ]]; then
        echo "moveit/robot_model/robot_model.hpp not found, patching trac_ik source files..."
        find "$SRC_DIR" -name "*.cpp" -o -name "*.h" -o -name "*.hpp" | while read -r src_file; do
            if grep -q '#include <moveit/robot_model/robot_model.hpp>' "$src_file" 2>/dev/null; then
                sed -i 's|#include <moveit/robot_model/robot_model.hpp>|#include <moveit/robot_model/robot_model.h>|g' "$src_file"
                echo "  [PATCH] $src_file"
            fi
        done
    fi

    if [[ ! -f "/opt/ros/humble/include/moveit/robot_state/robot_state.hpp" ]]; then
        echo "moveit/robot_state/robot_state.hpp not found, patching trac_ik source files..."
        find "$SRC_DIR" -name "*.cpp" -o -name "*.h" -o -name "*.hpp" | while read -r src_file; do
            if grep -q '#include <moveit/robot_state/robot_state.hpp>' "$src_file" 2>/dev/null; then
                sed -i 's|#include <moveit/robot_state/robot_state.hpp>|#include <moveit/robot_state/robot_state.h>|g' "$src_file"
                echo "  [PATCH] $src_file"
            fi
        done
    fi

    echo "Building trac_ik (release)..."
    cd "$PKG_DIR"
    colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release

    add_source_to_shellrc "$PKG_DIR/install"
    echo "trac_ik installed to $PKG_DIR"
}

# ============================================================
# 安装函数：其他包（示例）
# ============================================================
# install_your_package() {
#     local PKG_DIR="$ROS2_PKGS_DIR/your_package"
#     # ... clone, build, install ...
# }

# ============================================================
# 执行安装
# ============================================================
mkdir -p "$ROS2_PKGS_DIR"

for pkg in "${PACKAGES_TO_INSTALL[@]}"; do
    echo ""
    echo "========================================"
    echo "Installing: $pkg"
    echo "========================================"

    case "$pkg" in
        trac_ik)
            install_trac_ik
            ;;
        # your_package)
        #     install_your_package
        #     ;;
        *)
            echo "Error: unknown package '$pkg'"
            exit 1
            ;;
    esac
done

echo ""
echo "Done."
