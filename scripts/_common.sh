#!/bin/bash
# 共享函数库 — 供子命令脚本 source 使用

# ============================================================
# Git 凭证管理
# ============================================================

cleanup_credentials() {
    if [[ -n "${TMP_ASKPASS:-}" && -f "$TMP_ASKPASS" ]]; then
        rm -f -- "$TMP_ASKPASS"
    fi
    unset VSC_GIT_USER VSC_GIT_PASS
    unset GIT_ASKPASS GIT_ASKPASS_REQUIRE GIT_TERMINAL_PROMPT
    CREDENTIALS_READY=false
}

prompt_credentials() {
    local new_user=""
    local new_pass=""

    printf "Git username: "
    if ! read -r new_user; then
        echo ""
        echo "Error: unable to read Git username."
        return 1
    fi

    printf "Git password: "
    if ! read -rs new_pass; then
        echo ""
        echo "Error: unable to read Git password."
        return 1
    fi
    echo ""

    GIT_USER="$new_user"
    GIT_PASS="$new_pass"
    export VSC_GIT_USER="$GIT_USER"
    export VSC_GIT_PASS="$GIT_PASS"
}

setup_credentials() {
    if [[ "$CREDENTIALS_READY" == true ]]; then
        return 0
    fi

    if ! prompt_credentials; then
        return 1
    fi

    TMP_ASKPASS=$(mktemp) || {
        echo "Error: unable to create temporary Git credential helper."
        return 1
    }

    trap 'cleanup_credentials' EXIT
    trap 'cleanup_credentials; trap - EXIT INT TERM; exit 130' INT
    trap 'cleanup_credentials; trap - EXIT INT TERM; exit 143' TERM

    if ! cat > "$TMP_ASKPASS" <<'ASKPASS'
#!/bin/bash
case "$1" in
    *Username*|*username*) echo "${VSC_GIT_USER:-}" ;;
    *Password*|*password*) echo "${VSC_GIT_PASS:-}" ;;
    *) echo "" ;;
esac
ASKPASS
    then
        echo "Error: unable to configure temporary Git credential helper."
        cleanup_credentials
        trap - EXIT INT TERM
        return 1
    fi

    if ! chmod 700 "$TMP_ASKPASS"; then
        echo "Error: unable to configure temporary Git credential helper."
        cleanup_credentials
        trap - EXIT INT TERM
        return 1
    fi

    export GIT_ASKPASS="$TMP_ASKPASS"
    export GIT_ASKPASS_REQUIRE=force
    export GIT_TERMINAL_PROMPT=0
    CREDENTIALS_READY=true
}

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
