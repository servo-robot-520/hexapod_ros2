#!/bin/bash
# 共享函数库 — 供子命令脚本 source 使用

# ============================================================
# Git 辅助
# ============================================================

authentication_failed() {
    local output="$1"
    echo "$output" | grep -qiE \
        'authentication failed|invalid username or password|HTTP Basic: Access denied|could not read (Username|Password)|fatal:.*(401|403)|remote:.*(401|403)'
}

# ============================================================
# Shell 配置辅助
# ============================================================

add_source_to_shellrc() {
    local install_dir="$1"
    if [[ -f "$HOME/.bashrc" ]]; then
        local bash_line="source $install_dir/setup.bash"
        if ! grep -qF "$bash_line" "$HOME/.bashrc"; then
            echo "$bash_line" >> "$HOME/.bashrc"
            echo "Added to ~/.bashrc"
        fi
    fi
    if [[ -f "$HOME/.zshrc" ]]; then
        local zsh_line="source $install_dir/setup.zsh"
        if ! grep -qF "$zsh_line" "$HOME/.zshrc"; then
            echo "$zsh_line" >> "$HOME/.zshrc"
            echo "Added to ~/.zshrc"
        fi
    fi
}
