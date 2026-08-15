#!/usr/bin/env bash

# 此脚本供 CLion 工具链和 CMake 配置阶段使用：仅准备包查找路径，
# 不加载工作区 install/setup.*，避免旧安装库进入 LD_LIBRARY_PATH。
if [ -n "${ZSH_VERSION:-}" ]; then
    SCRIPT_PATH="${(%):-%N}"
else
    SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
fi
SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

COMMON_ENV_FILE="${SCRIPT_DIR}/_env_common.sh"
if [ ! -f "${COMMON_ENV_FILE}" ]; then
    echo "错误：未找到环境公共函数文件：${COMMON_ENV_FILE}" >&2
    return 1 2>/dev/null || exit 1
fi
source "${COMMON_ENV_FILE}"

# IDE 不继承启动 CLion 的 shell 中已有 ROS overlay；只在 ROS 基础环境上
# 准备当前工作区源码的包查找路径。
unset AMENT_PREFIX_PATH
unset CMAKE_PREFIX_PATH
unset COLCON_PREFIX_PATH
unset LD_LIBRARY_PATH
source_ros_base_environment || return 1 2>/dev/null || exit 1

# ROS 的 setup.bash 会设置 AMENT_PREFIX_PATH，但不会保证 CMake 的
# CMAKE_PREFIX_PATH 包含 ROS prefix；find_package(sensor_msgs) 等需要它。
prepend_cmake_prefix() {
    case ":${CMAKE_PREFIX_PATH:-}:" in
        *":$1:"*) ;;
        *) export CMAKE_PREFIX_PATH="$1${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}" ;;
    esac
}

prepend_ament_prefix() {
    case ":${AMENT_PREFIX_PATH:-}:" in
        *":$1:"*) ;;
        *) export AMENT_PREFIX_PATH="$1${AMENT_PREFIX_PATH:+:${AMENT_PREFIX_PATH}}" ;;
    esac
}

prepend_cmake_prefix "/opt/ros/${ROS_DISTRO}"

# CLion 可能从已 source 工作区 env.sh 的父进程启动。即使本脚本不加载
# install/setup.*，父环境中的旧安装库仍会让调试器加载错误的 .so，因此在
# ROS 与可选 overlay 初始化完成后，只移除当前工作区 install 下的库目录。
filter_workspace_install_prefixes() {
    local remaining_path="$1"
    local path_entry
    local cleaned_path=""

    while [ -n "${remaining_path}" ]; do
        case "${remaining_path}" in
            *:*)
                path_entry="${remaining_path%%:*}"
                remaining_path="${remaining_path#*:}"
                ;;
            *)
                path_entry="${remaining_path}"
                remaining_path=""
                ;;
        esac

        # 空路径项等效于当前目录；IDE 环境中不保留它，避免非预期加载。
        if [ -z "${path_entry}" ]; then
            continue
        fi
        case "${path_entry}" in
            "${WORKSPACE_DIR}"/install | \
            "${WORKSPACE_DIR}"/install/ | \
            "${WORKSPACE_DIR}"/install/* | \
            "${WORKSPACE_DIR}"/install/*/)
                continue
                ;;
        esac

        if [ -z "${cleaned_path}" ]; then
            cleaned_path="${path_entry}"
        else
            cleaned_path="${cleaned_path}:${path_entry}"
        fi
    done

    printf '%s' "${cleaned_path}"
}

remove_workspace_install_prefixes() {
    local cleaned_cmake_prefix
    local cleaned_ament_prefix

    cleaned_cmake_prefix="$(filter_workspace_install_prefixes "${CMAKE_PREFIX_PATH:-}")"
    cleaned_ament_prefix="$(filter_workspace_install_prefixes "${AMENT_PREFIX_PATH:-}")"

    if [ -n "${cleaned_cmake_prefix}" ]; then
        export CMAKE_PREFIX_PATH="${cleaned_cmake_prefix}"
    else
        unset CMAKE_PREFIX_PATH
    fi
    if [ -n "${cleaned_ament_prefix}" ]; then
        export AMENT_PREFIX_PATH="${cleaned_ament_prefix}"
    else
        unset AMENT_PREFIX_PATH
    fi
}

remove_workspace_install_library_paths() {
    local remaining_path="${LD_LIBRARY_PATH:-}"
    local path_entry
    local cleaned_path=""

    while [ -n "${remaining_path}" ]; do
        case "${remaining_path}" in
            *:*)
                path_entry="${remaining_path%%:*}"
                remaining_path="${remaining_path#*:}"
                ;;
            *)
                path_entry="${remaining_path}"
                remaining_path=""
                ;;
        esac

        if [ -z "${path_entry}" ]; then
            continue
        fi
        case "${path_entry}" in
            "${WORKSPACE_DIR}"/install/lib | \
            "${WORKSPACE_DIR}"/install/lib/ | \
            "${WORKSPACE_DIR}"/install/*/lib | \
            "${WORKSPACE_DIR}"/install/*/lib/)
                continue
                ;;
        esac

        if [ -z "${cleaned_path}" ]; then
            cleaned_path="${path_entry}"
        else
            cleaned_path="${cleaned_path}:${path_entry}"
        fi
    done

    if [ -n "${cleaned_path}" ]; then
        export LD_LIBRARY_PATH="${cleaned_path}"
    else
        unset LD_LIBRARY_PATH
    fi
}

# 顶层 CMake 会将当前工作区源码逐包 add_subdirectory。不能把当前工作区
# install/* 加入 CMAKE_PREFIX_PATH 或 AMENT_PREFIX_PATH，否则 find_package()
# 会导入旧安装快照并把其 RPATH 写入 CLion 生成的目标。正式运行时由 env.sh
# source install/setup.* 来提供这些 prefix。
remove_workspace_install_prefixes
remove_workspace_install_library_paths

# 保持既有工作区默认通信域行为；IDE 专用配置可在此后覆盖它。
export ROS_DOMAIN_ID=1

# IDE 专用配置只影响 CLion/CMake 环境。项目级配置先加载，开发机私有配置后
# 加载，因此后者可覆盖项目级配置和脚本默认值。
source_optional_environment_file "${SCRIPT_DIR}/ide_proj_env.sh"
source_optional_environment_file "${SCRIPT_DIR}/ide_my_env.sh"
