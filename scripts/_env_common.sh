#!/usr/bin/env bash

source_ros_base_environment() {
    local ros_setup_file

    export ROS_DISTRO="${ROS_DISTRO:-humble}"
    if [ -n "${ZSH_VERSION:-}" ]; then
        ros_setup_file="/opt/ros/${ROS_DISTRO}/setup.zsh"
    else
        ros_setup_file="/opt/ros/${ROS_DISTRO}/setup.bash"
    fi
    if [ ! -f "${ros_setup_file}" ]; then
        echo "错误：未找到 ROS 环境文件：${ros_setup_file}" >&2
        return 1
    fi

    source "${ros_setup_file}"
}

source_optional_environment_file() {
    local environment_file="$1"

    if [ -f "${environment_file}" ]; then
        source "${environment_file}"
    fi
}
