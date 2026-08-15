#!/usr/bin/env bash

# 此脚本用于正式 ROS 运行环境；IDE 工具链请使用独立的 IDE 环境入口。
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
source_ros_base_environment || return 1 2>/dev/null || exit 1

# 正式运行需要工作区安装 overlay，其中包含运行时共享库路径。
# 与当前 shell 匹配的 setup 文件可避免在 zsh 中加载 bash 专用初始化逻辑。
if [ -n "${ZSH_VERSION:-}" ]; then
    INSTALL_SETUP_FILE="${WORKSPACE_DIR}/install/setup.zsh"
else
    INSTALL_SETUP_FILE="${WORKSPACE_DIR}/install/setup.bash"
fi
if [ ! -f "${INSTALL_SETUP_FILE}" ]; then
    echo "错误：未找到工作区安装环境文件：${INSTALL_SETUP_FILE}。请先执行 ./ws_tools build。" >&2
    return 1 2>/dev/null || exit 1
fi
source "${INSTALL_SETUP_FILE}"

# 保持既有工作区默认通信域行为。
export ROS_DOMAIN_ID=1

# 让 Gazebo 只使用指定的 IP 地址进行通信。
# Ignition Gazebo (Gz)
export GZ_IP=127.0.0.1
# Gazebo Classic
export GAZEBO_IP=127.0.0.1
export GAZEBO_MASTER_URI=http://127.0.0.1:11345

# 项目级配置先加载；开发机私有配置后加载，因此可覆盖项目默认值。
source_optional_environment_file "${SCRIPT_DIR}/proj_env.sh"
source_optional_environment_file "${SCRIPT_DIR}/my_env.sh"
