#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ============================================================
# 帮助信息
# ============================================================
usage() {
    echo "Usage: ws_tools build [-c] [-r] [-e] [-t] [-p <pkg1,...>] [-pe <pkg1,...>] [-h]"
    echo ""
    echo "Options:"
    echo "  -c              Clean build (delete build/install/log directories)"
    echo "  -r              Release mode (default: Debug)"
    echo "  -e              Generate/update .env file for PyCharm/CLion"
    echo "  -t              Build and run tests (default: tests disabled)"
    echo "  -p <pkgs>       Build specified packages (comma- or space-separated)"
    echo "  -pe <pkgs>      Exclude specified packages, build all others"
    echo "  -h              Show this help message"
    echo ""
    echo "Compiler:"
    echo "  Defaults to /usr/bin/gcc-13 and /usr/bin/g++-13."
    echo "  Set both CC and CXX to use an equivalent custom compiler pair."
    echo ""
    echo "Examples:"
    echo "  ws_tools build              # Debug mode, build all"
    echo "  ws_tools build -r           # Release mode, build all"
    echo "  ws_tools build -e           # Build and generate .env"
    echo "  ws_tools build -t           # Build and run tests"
    echo "  ws_tools build -p pkg1,pkg2 # Build specified packages"
    echo "  ws_tools build -pe pkg1     # Build all except pkg1"
    echo "  ws_tools build -t -p pkg1   # Build and test specified package"
    echo "  ws_tools build -c           # Clean and build all"
    echo "  ws_tools build -p pkg1 -c   # Clean and build specified package"
    exit 0
}

# 跳过第一个参数（命令名称）
shift

# 默认配置
CLEAN=false
BUILD_TYPE="debug"
UPDATE_ENV=false
RUN_TESTS=false
PACKAGE_NAMES=()
PACKAGE_EXCLUDE_NAMES=()
PACKAGE_SELECT_ARGS=()

# 先手动解析 -pe 参数（getopts 不支持 -pe 这种两字母选项）
TEMP_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -pe)
            if [[ -z "${2:-}" || "$2" == -* ]]; then
                echo "选项 -pe 需要至少一个功能包" >&2
                exit 1
            fi
            IFS=',' read -r -a PACKAGE_EXCLUDE_NAMES <<< "$2"
            shift 2
            ;;
        *)
            TEMP_ARGS+=("$1")
            shift
            ;;
    esac
done

# 恢复参数供 getopts 使用
set -- "${TEMP_ARGS[@]}"

# 解析其他参数
while getopts ":crep:ht" opt; do
  case $opt in
    c)
      CLEAN=true
      ;;
    r)
      BUILD_TYPE="release"
      ;;
    e)
      UPDATE_ENV=true
      ;;
    t)
      RUN_TESTS=true
      ;;
    p)
      if [ -z "$OPTARG" ] || [[ "$OPTARG" == -* ]]; then
        echo "选项 -p 需要至少一个功能包" >&2
        exit 1
      fi

      # 支持 -p pkg1,pkg2 和 -p "pkg1 pkg2"；逗号两侧可以有空格。
      # 显式拒绝空的逗号分段，避免 -p 在 -c 下退化为全量清理。
      if [[ "$OPTARG" == ,* || "$OPTARG" == *, || "$OPTARG" == *,,* ]]; then
        echo "选项 -p 包含空的功能包名称" >&2
        exit 1
      fi

      PACKAGE_NAMES=()
      IFS=',' read -r -a comma_separated_packages <<< "$OPTARG"
      for package_group in "${comma_separated_packages[@]}"; do
        if [[ "$package_group" =~ ^[[:space:]]*$ ]]; then
          echo "选项 -p 包含空的功能包名称" >&2
          exit 1
        fi

        read -r -a space_separated_packages <<< "$package_group"
        if [ "${#space_separated_packages[@]}" -eq 0 ]; then
          echo "选项 -p 包含空的功能包名称" >&2
          exit 1
        fi

        for package_name in "${space_separated_packages[@]}"; do
          if [ -z "$package_name" ]; then
            echo "选项 -p 包含空的功能包名称" >&2
            exit 1
          fi
          PACKAGE_NAMES+=("$package_name")
        done
      done
      ;;
    h)
      usage
      ;;
    :)
      echo "选项 -$OPTARG 需要一个参数" >&2
      exit 1
      ;;
    \?)
      echo "无效选项: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# A clean build deletes build/install/log. Do not allow a second invocation to
# remove those directories while another colcon process is still using them.
# Acquire this only after option parsing so `./ws_tools build -h` remains
# available while a build is in progress. The descriptor is inherited by child
# processes, so the lock stays held for the whole build (including tests).
if ! command -v flock >/dev/null 2>&1; then
  echo "Error: ws_tools build requires the 'flock' command (util-linux)." >&2
  exit 1
fi
BUILD_LOCK_FILE="$SCRIPT_DIR/.ws_tools_build.lock"
exec 9>"$BUILD_LOCK_FILE"
if ! flock -n 9; then
  echo "Error: another ws_tools build is already running in this workspace." >&2
  echo "Wait for it to finish or stop that build before starting a new one." >&2
  exit 1
fi

# 如果带-c参数，执行清理
if [ "$CLEAN" = true ]; then
  # 始终删除 log 文件夹
  rm -rf "$SCRIPT_DIR/log"

  if [ "${#PACKAGE_NAMES[@]}" -gt 0 ]; then
    # 有 -p 参数，只删除对应的包
    for pkg in "${PACKAGE_NAMES[@]}"; do
      echo "Cleaning package: $pkg"
      rm -rf "$SCRIPT_DIR/install/$pkg"
      rm -rf "$SCRIPT_DIR/build/$pkg"
    done
  else
    # 没有 -p 参数，删除整个 build 和 install
    echo "Clearing all build directories..."
    rm -rf "$SCRIPT_DIR/install"
    rm -rf "$SCRIPT_DIR/build"
  fi
fi

cd "$SCRIPT_DIR"

# colcon resolves CMake from PATH. Prefer the system CMake rather than a
# toolchain-bundled CMake (for example STM32CubeCLT), whose install behavior
# can differ from the ROS 2 / Ubuntu toolchain.
SYSTEM_CMAKE="/usr/bin/cmake"
if [ ! -x "$SYSTEM_CMAKE" ]; then
  echo "Error: system CMake not found or not executable: $SYSTEM_CMAKE" >&2
  exit 1
fi
export PATH="/usr/bin:$PATH"
echo "Using CMake: $(command -v cmake)"

# CMake only reads CC/CXX when it creates a package's compiler cache. Ubuntu
# 22.04's /usr/bin/cc and /usr/bin/c++ point at GCC 11, whose standard library
# lacks the C++23 facilities required by ros_common_cpp. Keep an explicit
# caller-provided compiler pair intact, but make GCC 13 the workspace default.
if [[ -z "${CC:-}" && -z "${CXX:-}" ]]; then
  export CC="/usr/bin/gcc-13"
  export CXX="/usr/bin/g++-13"
elif [[ -z "${CC:-}" || -z "${CXX:-}" ]]; then
  echo "Error: set both CC and CXX, or leave both unset to use GCC 13." >&2
  exit 1
fi

if ! command -v "$CC" >/dev/null 2>&1; then
  echo "Error: C compiler not found: $CC" >&2
  exit 1
fi
if ! command -v "$CXX" >/dev/null 2>&1; then
  echo "Error: C++ compiler not found: $CXX" >&2
  exit 1
fi

echo "Using C compiler: $(command -v "$CC")"
echo "Using C++ compiler: $(command -v "$CXX")"

# 根据构建类型设置mixin参数
MIXIN_ARG=""
SYMLINK_ARG=""
if [ "$BUILD_TYPE" = "release" ]; then
  echo "Using Release build"
  MIXIN_ARG="--mixin release"
else
  echo "Using Debug build"
  MIXIN_ARG="--mixin debug"
  SYMLINK_ARG="--symlink-install"
fi

# 构建包选择参数
if [ "${#PACKAGE_EXCLUDE_NAMES[@]}" -gt 0 ]; then
  # -pe 参数：排除指定包，构建其余所有包
  # 扫描包含 CMakeLists.txt 或 package.xml 的目录
  ALL_PACKAGES=()
  for pkg_dir in "$SCRIPT_DIR/src"/*/; do
    if [ -d "$pkg_dir" ] && ([ -f "$pkg_dir/CMakeLists.txt" ] || [ -f "$pkg_dir/package.xml" ]); then
      ALL_PACKAGES+=("$(basename "$pkg_dir")")
    fi
  done

  # 排除指定的包
  BUILD_PACKAGES=()
  for pkg in "${ALL_PACKAGES[@]}"; do
    excluded=false
    for exclude in "${PACKAGE_EXCLUDE_NAMES[@]}"; do
      if [[ "$pkg" == "$exclude" ]]; then
        excluded=true
        break
      fi
    done
    if [[ "$excluded" == false ]]; then
      BUILD_PACKAGES+=("$pkg")
    fi
  done

  if [ "${#BUILD_PACKAGES[@]}" -eq 0 ]; then
    echo "Error: no packages to build after exclusion" >&2
    exit 1
  fi

  PACKAGE_SELECT_ARGS=(--packages-select "${BUILD_PACKAGES[@]}")
  echo "Building packages (excluding ${PACKAGE_EXCLUDE_NAMES[*]}): ${BUILD_PACKAGES[*]}"
elif [ "${#PACKAGE_NAMES[@]}" -gt 0 ]; then
  PACKAGE_SELECT_ARGS=(--packages-select "${PACKAGE_NAMES[@]}")
  echo "Building packages: ${PACKAGE_NAMES[*]}"
else
  echo "Building all packages"
fi

# 默认关闭测试；只有指定 -t 时才构建并运行测试。
BUILD_TESTING_ARG="-DBUILD_TESTING=OFF"
if [ "$RUN_TESTS" = true ]; then
  BUILD_TESTING_ARG="-DBUILD_TESTING=ON"
fi

if ! colcon --log-level info \
  --log-base "$SCRIPT_DIR/log" \
  build \
  --base-paths "$SCRIPT_DIR/src" \
  --build-base "$SCRIPT_DIR/build" \
  --install-base "$SCRIPT_DIR/install" \
  --event-handlers console_direct+ \
  --parallel-workers 8 \
  $SYMLINK_ARG \
  "${PACKAGE_SELECT_ARGS[@]}" \
  --cmake-args \
  -Wno-dev \
  $BUILD_TESTING_ARG \
  -DCMAKE_BUILD_TYPE=$BUILD_TYPE; then
  echo "Build failed" >&2
  exit 1
fi

echo "Build finished"

if [ "$RUN_TESTS" = true ]; then
  if ! colcon --log-base "$SCRIPT_DIR/log" test \
    --base-paths "$SCRIPT_DIR/src" \
    --build-base "$SCRIPT_DIR/build" \
    --install-base "$SCRIPT_DIR/install" \
    --event-handlers console_direct+ \
    "${PACKAGE_SELECT_ARGS[@]}"; then
    echo "Tests failed" >&2
    exit 1
  fi

  if ! colcon test-result --test-result-base "$SCRIPT_DIR/build" --verbose; then
    echo "Test result reporting failed" >&2
    exit 1
  fi
fi

# -e 选项：将install下各包的lib路径写入.env的LD_LIBRARY_PATH
if [ "$UPDATE_ENV" = true ]; then
  ENV_FILE="$SCRIPT_DIR/.env"

  # .env不存在则创建并写入默认内容
  if [ ! -f "$ENV_FILE" ]; then
    ROS_DOMAIN_ID_VAL="1"
    if [ -f "$SCRIPT_DIR/env.sh" ]; then
      ROS_DOMAIN_ID_VAL=$(grep -oP 'export\s+ROS_DOMAIN_ID=\K[0-9]+' "$SCRIPT_DIR/env.sh" || echo "1")
    fi
    cat > "$ENV_FILE" << EOF
PYTHONUNBUFFERED=1
ROS_DOMAIN_ID=${ROS_DOMAIN_ID_VAL}
AMENT_PREFIX_PATH=/opt/ros/humble
LD_LIBRARY_PATH=/opt/ros/humble/lib:\$LD_LIBRARY_PATH
EOF
    echo "已创建 $ENV_FILE"
  fi

  # 收集install下所有lib目录
  LIB_PATHS=""
  for lib_dir in "$SCRIPT_DIR"/install/*/lib; do
    if [ -d "$lib_dir" ]; then
      abs_path=$(cd "$lib_dir" && pwd)
      if [ -z "$LIB_PATHS" ]; then
        LIB_PATHS="$abs_path"
      else
        LIB_PATHS="$LIB_PATHS:$abs_path"
      fi
    fi
  done

  if [ -z "$LIB_PATHS" ]; then
    echo "警告: install下未找到lib目录，请先编译" >&2
  else
    # 提取现有LD_LIBRARY_PATH的基值
    OLD_LINE=$(grep '^LD_LIBRARY_PATH=' "$ENV_FILE" | head -1)
    OLD_BASE=$(echo "$OLD_LINE" | sed 's/^LD_LIBRARY_PATH=//' | sed 's/:\$LD_LIBRARY_PATH$//')

    if [ -n "$OLD_BASE" ]; then
      NEW_LINE="LD_LIBRARY_PATH=${LIB_PATHS}:${OLD_BASE}:\$LD_LIBRARY_PATH"
    else
      NEW_LINE="LD_LIBRARY_PATH=${LIB_PATHS}:\$LD_LIBRARY_PATH"
    fi

    sed -i "s|^LD_LIBRARY_PATH=.*|${NEW_LINE}|" "$ENV_FILE"

    echo "已更新 $ENV_FILE 中的 LD_LIBRARY_PATH:"
    echo "  $NEW_LINE"
  fi

  # 收集install下所有功能包路径，写入AMENT_PREFIX_PATH
  AMENT_PATHS=""
  for pkg_dir in "$SCRIPT_DIR"/install/*/; do
    if [ -d "$pkg_dir" ]; then
      abs_path=$(cd "$pkg_dir" && pwd)
      if [ -z "$AMENT_PATHS" ]; then
        AMENT_PATHS="$abs_path"
      else
        AMENT_PATHS="$AMENT_PATHS:$abs_path"
      fi
    fi
  done

  if [ -n "$AMENT_PATHS" ]; then
    OLD_LINE=$(grep '^AMENT_PREFIX_PATH=' "$ENV_FILE" | head -1)
    OLD_BASE=$(echo "$OLD_LINE" | sed 's/^AMENT_PREFIX_PATH=//' | sed 's/:\$AMENT_PREFIX_PATH$//')

    if [ -n "$OLD_BASE" ]; then
      NEW_LINE="AMENT_PREFIX_PATH=${AMENT_PATHS}:${OLD_BASE}:\$AMENT_PREFIX_PATH"
    else
      NEW_LINE="AMENT_PREFIX_PATH=${AMENT_PATHS}:\$AMENT_PREFIX_PATH"
    fi

    sed -i "s|^AMENT_PREFIX_PATH=.*|${NEW_LINE}|" "$ENV_FILE"

    echo "已更新 $ENV_FILE 中的 AMENT_PREFIX_PATH:"
    echo "  $NEW_LINE"
  fi
fi

# 清理锁文件
rm -f "$BUILD_LOCK_FILE"

echo "Done"
