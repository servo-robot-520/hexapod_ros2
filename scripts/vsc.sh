#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/_common.sh"

# ============================================================
# 参数解析
# ============================================================
MODULE_CLONE_FLAG=false
ADD_SAFE_FLAG=false
CLONE_JOBS=4
GIT_USER=""
GIT_PASS=""
TMP_ASKPASS=""
CREDENTIALS_READY=false

usage() {
    echo "Usage: ws_tools vsc [-module_clone|-mc [-j N]] [-safe] [-h]"
    echo "  -module_clone, -mc  Clone modules configured in .modules.conf"
    echo "  -j N                Number of parallel clone jobs (default: 4)"
    echo "  -safe               Add module paths to git safe.directory"
    echo "  -h, --help          Show this help message"
}

shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        -module_clone|-mc)
            MODULE_CLONE_FLAG=true
            shift
            ;;
        -j)
            if [[ -z "${2:-}" || "$2" == -* ]]; then
                echo "Error: -j requires a number"
                exit 1
            fi
            CLONE_JOBS="$2"
            shift 2
            ;;
        -safe)
            ADD_SAFE_FLAG=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown option '$1'"
            usage
            exit 1
            ;;
    esac
done

# ============================================================
# module_clone 辅助函数
# ============================================================
module_clone_print_summary() {
    echo ""
    echo "Module clone summary:"
    echo "  Success: $SUCCESS_COUNT"
    echo "  Skipped: $SKIPPED_COUNT"
    echo "  Failed: $FAILED_COUNT"

    if [[ ${#FAILED_ITEMS[@]} -gt 0 ]]; then
        echo ""
        echo "Failed modules:"
        local item
        for item in "${FAILED_ITEMS[@]}"; do
            echo "  - $item"
        done
    fi
}

# 单个模块 clone（供并行调用）
clone_single_module() {
    local section="$1"
    local MODULES_FILE="$2"
    local RESULT_DIR="$3"
    local workspace_root="$4"

    # 将 section 名中的 / 替换为 _，用作临时文件名
    local result_key="${section//\//_}"

    local module_path module_url module_branch label destination
    local clone_output clone_reason attempt

    module_path=$(git config -f "$MODULES_FILE" --get "module.$section.path" 2>/dev/null || true)
    module_url=$(git config -f "$MODULES_FILE" --get "module.$section.url" 2>/dev/null || true)
    module_branch=$(git config -f "$MODULES_FILE" --get "module.$section.branch" 2>/dev/null || true)
    label="${module_path:-$section}"

    if [[ -z "$module_path" ]]; then
        echo "fail:$label:missing path" > "$RESULT_DIR/$result_key"
        return
    fi

    if [[ -z "$module_url" ]]; then
        echo "fail:$label:missing url" > "$RESULT_DIR/$result_key"
        return
    fi

    if [[ "$module_path" == /* ]]; then
        echo "fail:$label:path must be relative to the workspace" > "$RESULT_DIR/$result_key"
        return
    fi

    destination=$(realpath -m -- "$SCRIPT_DIR/$module_path") 2>/dev/null || {
        echo "fail:$label:unable to resolve destination path" > "$RESULT_DIR/$result_key"
        return
    }

    if [[ "$destination" != "$workspace_root/"* ]]; then
        echo "fail:$label:path escapes the workspace" > "$RESULT_DIR/$result_key"
        return
    fi

    if [[ -e "$destination" || -L "$destination" ]]; then
        echo "skip:$label:path already exists" > "$RESULT_DIR/$result_key"
        return
    fi

    local parent_dir
    parent_dir=$(dirname -- "$destination")
    if ! mkdir -p -- "$parent_dir"; then
        echo "fail:$label:unable to create parent directory" > "$RESULT_DIR/$result_key"
        return
    fi

    local branch_info="${module_branch:-remote default}"
    printf '[CLONE]   %s (branch: %s)\n' "$module_path" "$branch_info"

    attempt=1
    while true; do
        local clone_command=(git clone)
        if [[ -n "$module_branch" ]]; then
            clone_command+=(--branch "$module_branch")
        fi
        clone_command+=("$module_url" "$destination")

        clone_output=""
        if clone_output=$("${clone_command[@]}" 2>&1); then
            echo "ok:$label" > "$RESULT_DIR/$result_key"
            printf '[OK]      %s\n' "$module_path"
            return
        fi

        if [[ -e "$destination" || -L "$destination" ]]; then
            rm -rf -- "$destination"
        fi

        if authentication_failed "$clone_output"; then
            echo "fail:$label:authentication failed" > "$RESULT_DIR/$result_key"
            [[ -n "$clone_output" ]] && echo "$clone_output" >&2
            return
        fi

        clone_reason=$(printf '%s\n' "$clone_output" | awk 'NF { line=$0 } END { print line }')
        clone_reason="${clone_reason:-git clone failed}"
        [[ -n "$clone_output" ]] && echo "$clone_output" >&2
        echo "fail:$label:$clone_reason" > "$RESULT_DIR/$result_key"
        return
    done
}

vsc_module_clone() {
    local MODULES_FILE="$SCRIPT_DIR/.modules.conf"
    SUCCESS_COUNT=0
    SKIPPED_COUNT=0
    FAILED_COUNT=0
    FAILED_ITEMS=()

    if [[ ! -r "$MODULES_FILE" ]]; then
        echo "Error: .modules.conf not found or not readable: $MODULES_FILE"
        return 1
    fi

    if ! git config -f "$MODULES_FILE" --list >/dev/null 2>&1; then
        echo "Error: unable to parse .modules.conf: $MODULES_FILE"
        return 1
    fi

    module_keys=$(git config -f "$MODULES_FILE" --name-only --get-regexp '^module\.' 2>/dev/null || true)

    module_sections=()
    declare -A seen_module_sections=()
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        remainder="${key#module.}"
        section="${remainder%.*}"
        [[ -z "$section" || "$section" == "$remainder" ]] && continue
        if [[ -z "${seen_module_sections[$section]+x}" ]]; then
            seen_module_sections["$section"]=1
            module_sections+=("$section")
        fi
    done <<< "$module_keys"

    if [[ ${#module_sections[@]} -eq 0 ]]; then
        echo "No modules configured in .modules.conf."
        module_clone_print_summary
        return 0
    fi

    workspace_root=$(realpath -m -- "$SCRIPT_DIR") || {
        echo "Error: unable to resolve workspace root: $SCRIPT_DIR"
        return 1
    }

    # 提前设置凭证（并行 clone 时无法交互输入）
    if ! setup_credentials; then
        echo "Error: unable to configure Git credentials"
        return 1
    fi

    # 创建临时目录存放每个模块的结果
    RESULT_DIR=$(mktemp -d)
    trap "rm -rf '$RESULT_DIR'" EXIT

    local running=0
    local pids=()

    echo "Cloning ${#module_sections[@]} modules with $CLONE_JOBS parallel jobs..."

    for section in "${module_sections[@]}"; do
        # 控制并发数：等待任意一个后台进程完成
        while [[ $running -ge $CLONE_JOBS ]]; do
            wait -n 2>/dev/null || true
            running=$((running - 1))
        done

        clone_single_module "$section" "$MODULES_FILE" "$RESULT_DIR" "$workspace_root" &
        pids+=($!)
        running=$((running + 1))
    done

    # 等待所有后台进程完成
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    # 收集结果
    for section in "${module_sections[@]}"; do
        local result_key="${section//\//_}"
        local result_file="$RESULT_DIR/$result_key"
        if [[ ! -f "$result_file" ]]; then
            continue
        fi

        local result
        result=$(cat "$result_file")
        local status="${result%%:*}"
        local rest="${result#*:}"
        local label="${rest%%:*}"
        local reason="${rest#*:}"

        case "$status" in
            ok)
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                ;;
            skip)
                SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                printf '[SKIP]    %s (%s)\n' "$label" "$reason"
                ;;
            fail)
                FAILED_COUNT=$((FAILED_COUNT + 1))
                FAILED_ITEMS+=("$label: $reason")
                printf '[FAILED]  %s (%s)\n' "$label" "$reason"
                ;;
        esac
    done

    module_clone_print_summary

    if [[ $FAILED_COUNT -gt 0 ]]; then
        return 1
    fi
    return 0
}

# ============================================================
# 将模块路径添加到 git safe.directory
# ============================================================
vsc_add_safe() {
    local MODULES_FILE="$SCRIPT_DIR/.modules.conf"

    if [[ ! -r "$MODULES_FILE" ]]; then
        echo "Error: .modules.conf not found or not readable: $MODULES_FILE"
        return 1
    fi

    if ! git config -f "$MODULES_FILE" --list >/dev/null 2>&1; then
        echo "Error: unable to parse .modules.conf: $MODULES_FILE"
        return 1
    fi

    local module_keys
    module_keys=$(git config -f "$MODULES_FILE" --name-only --get-regexp '^module\.' 2>/dev/null || true)

    local module_sections=()
    declare -A seen_module_sections=()
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        local remainder="${key#module.}"
        local section="${remainder%.*}"
        [[ -z "$section" || "$section" == "$remainder" ]] && continue
        if [[ -z "${seen_module_sections[$section]+x}" ]]; then
            seen_module_sections["$section"]=1
            module_sections+=("$section")
        fi
    done <<< "$module_keys"

    if [[ ${#module_sections[@]} -eq 0 ]]; then
        echo "No modules configured in .modules.conf."
        return 0
    fi

    local added=0 skipped=0

    for section in "${module_sections[@]}"; do
        local module_path
        module_path=$(git config -f "$MODULES_FILE" --get "module.$section.path" 2>/dev/null || true)

        if [[ -z "$module_path" ]]; then
            continue
        fi

        local full_path="$SCRIPT_DIR/$module_path"

        # 检查路径是否存在
        if [[ ! -d "$full_path" ]]; then
            continue
        fi

        # 获取绝对路径
        local abs_path
        abs_path=$(realpath "$full_path") || continue

        # 检查是否已添加
        if git config --global --get-all safe.directory 2>/dev/null | grep -qF "$abs_path"; then
            skipped=$((skipped + 1))
            continue
        fi

        # 添加到 safe.directory
        git config --global --add safe.directory "$abs_path"
        echo "[SAFE] $module_path"
        added=$((added + 1))
    done

    echo "Safe directory: $added added, $skipped skipped."
    return 0
}

# ============================================================
# 执行
# ============================================================
status=0

if [[ "$MODULE_CLONE_FLAG" == true ]]; then
    vsc_module_clone || status=1
    # clone 完成后自动添加 safe.directory
    vsc_add_safe || true
fi

if [[ "$ADD_SAFE_FLAG" == true ]]; then
    vsc_add_safe || status=1
fi

if [[ "$MODULE_CLONE_FLAG" == false && "$ADD_SAFE_FLAG" == false ]]; then
    usage
    exit 1
fi

cleanup_credentials
trap - EXIT INT TERM
echo "Done."
exit "$status"
