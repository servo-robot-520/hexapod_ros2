#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ============================================================
# 参数解析
# ============================================================
ACTION=""

usage() {
    echo "Usage: ws_tools service <-i|-r> [-h]"
    echo "  -i    Install and enable the systemd service"
    echo "  -r    Disable and remove the systemd service"
    echo "  -h    Show this help message"
    exit 0
}

shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)
            ACTION="install"
            shift
            ;;
        -r)
            ACTION="remove"
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

if [[ -z "$ACTION" ]]; then
    echo "Error: -i or -r is required"
    usage
fi

# ============================================================
# 查找 bringup 目录
# ============================================================
BRINGUP_DIR=""
for d in "$SCRIPT_DIR/src"/*_bringup; do
    [[ -d "$d" ]] && BRINGUP_DIR="$d" && break
done

if [[ -z "$BRINGUP_DIR" ]]; then
    echo "Error: no *_bringup directory found under src/."
    exit 1
fi

BRINGUP_NAME="$(basename "$BRINGUP_DIR")"
BRINGUP_NAME="${BRINGUP_NAME%_bringup}"

SERVICE_NAME="${BRINGUP_NAME}"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# ============================================================
# 移除服务
# ============================================================
if [[ "$ACTION" == "remove" ]]; then
    if [[ ! -f "$SERVICE_FILE" ]]; then
        echo "Service '$SERVICE_NAME' is not installed."
        exit 0
    fi
    echo "Removing service: $SERVICE_NAME"
    sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    sudo systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    sudo rm -f "$SERVICE_FILE"
    sudo systemctl daemon-reload
    echo "Service '$SERVICE_NAME' removed."
    exit 0
fi

# ============================================================
# 安装服务
# ============================================================
LAUNCH_FILE="$BRINGUP_DIR/launch/${BRINGUP_NAME}.launch.py"
if [[ ! -f "$LAUNCH_FILE" ]]; then
    echo "Error: $LAUNCH_FILE not found."
    exit 1
fi

ROS_DOMAIN_ID=""
if [[ -f "$SCRIPT_DIR/env.sh" ]]; then
    ROS_DOMAIN_ID=$(grep -oP 'export\s+ROS_DOMAIN_ID=\K[0-9]+' "$SCRIPT_DIR/env.sh")
fi
ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"

echo "ROS_DOMAIN_ID: $ROS_DOMAIN_ID"
echo "Creating systemd service: $SERVICE_NAME"
sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=ROS2 Launch ${BRINGUP_NAME}
After=network.target

[Service]
Type=simple
User=$(whoami)
Environment=ROS_DOMAIN_ID=${ROS_DOMAIN_ID}
ExecStart=/bin/bash -c 'source ${SCRIPT_DIR}/env.sh && ros2 launch ${BRINGUP_NAME} ${BRINGUP_NAME}.launch.py'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
echo "Service '$SERVICE_NAME' enabled. Use 'sudo systemctl start $SERVICE_NAME' to start."
