#!/bin/bash
set -euo pipefail

# chmod +x install-vlmcsd.sh
# sudo ./install-vlmcsd.sh

# 检测系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION_ID=$VERSION_ID
    else
        echo "Unsupported operating system. Cannot find /etc/os-release."
        exit 1
    fi
}

# 安装必要的依赖项
install_dependencies() {
    case "$OS" in
        ubuntu|debian|deepin)
            echo "Detected $OS. Using apt for package management."
            apt update && apt install -y wget curl systemd tar ;;
        centos|rhel|fedora|ol)
            echo "Detected $OS. Using yum/dnf for package management."
            yum update -y || dnf update -y
            yum install -y wget curl systemd tar || dnf install -y wget curl systemd tar ;;
        *)
            echo "Unsupported OS: $OS"
            exit 1 ;;
    esac
}

# 管理防火墙
manage_firewall() {
    case "$OS" in
        ubuntu|debian|deepin)
            if command -v ufw &> /dev/null; then
                ufw disable || echo "UFW is not running or disabled."
            fi ;;
        centos|rhel|fedora|ol)
            if systemctl is-active --quiet firewalld; then
                systemctl stop firewalld.service
                systemctl disable firewalld.service
            else
                echo "firewalld is not running."
            fi ;;
        *)
            echo "Unsupported OS for firewall management: $OS" ;;
    esac
}

# 设置时区为亚洲/上海
set_timezone() {
    echo "Setting timezone to Asia/Shanghai."
    timedatectl set-timezone Asia/Shanghai || echo "Failed to set timezone."
}

# 创建vlmcsd用户和组
create_user_and_group() {
    if ! getent group kms >/dev/null; then
        groupadd kms
    fi

    if ! id -u vlmcsd >/dev/null 2>&1; then
        useradd -r -M -G kms vlmcsd
    fi
}

# 下载并安装vlmcsd
install_vlmcsd() {
    TMP_DIR="/tmp/vlmcsd"
    mkdir -p "$TMP_DIR"
    cd "$TMP_DIR"

    if [ ! -f binaries.tar.gz ]; then
        wget https://github.com/Wind4/vlmcsd/releases/download/svn1113/binaries.tar.gz
    fi

    tar zxvf binaries.tar.gz
    cp ./binaries/Linux/intel/static/vlmcsd-x64-musl-static /usr/local/bin/vlmcsd
    chmod +x /usr/local/bin/vlmcsd
    chown vlmcsd:vlmcsd /usr/local/bin/vlmcsd
}

# 创建日志目录和PID文件
setup_logs_and_pid() {
    LOG_DIR="/var/log/vlmcsd"
    mkdir -p "$LOG_DIR"
    chown vlmcsd:vlmcsd "$LOG_DIR"
    su - vlmcsd -c "touch $LOG_DIR/vlmcsd.pid"
}

# 创建systemd服务文件
create_systemd_service() {
    cat > /lib/systemd/system/vlmcsd.service <<EOF
[Unit]
Description=vlmcsd KMS emulator service
After=network-online.target

[Service]
Type=forking
User=vlmcsd
PIDFile=$LOG_DIR/vlmcsd.pid
ExecStart=/usr/local/bin/vlmcsd -p $LOG_DIR/vlmcsd.pid -L 0.0.0.0 -l $LOG_DIR/vlmcsd.log -d
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s QUIT \$MAINPID

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable vlmcsd
    systemctl start vlmcsd
    systemctl status vlmcsd --no-pager
}

# 主流程
echo "Detecting operating system..."
detect_os
echo "Detected OS: $OS $VERSION_ID"

echo "Installing dependencies..."
install_dependencies
echo "Managing firewall..."
manage_firewall
echo "Setting timezone..."
set_timezone
echo "Creating user and group for vlmcsd..."
create_user_and_group
echo "Downloading and installing vlmcsd..."
install_vlmcsd
echo "Setting up logs and PID..."
setup_logs_and_pid
echo "Creating systemd service..."
create_systemd_service

echo "Installation complete. You may reboot the system if necessary."

