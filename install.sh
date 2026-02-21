#!/bin/bash

# x-ui 安装脚本
# 原版修改：从 875706361/x-ui_AI 仓库下载安装

set -e

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
plain='\033[0m'

# 仓库配置
# 官方发布仓库（用于下载压缩包）
RELEASE_REPO="FranzKafkaYu/x-ui"
# 脚本仓库（用于下载配置文件）
SCRIPT_REPO="875706361/x-ui_AI"
DOWNLOAD_BASE="https://github.com/${RELEASE_REPO}/releases/download"

# 检查 root
[[ $EUID -ne 0 ]] && echo -e "${red}致命错误：请使用 root 权限运行此脚本${plain}\n" && exit 1

# 检测系统
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}检查系统操作系统失败，请联系作者！${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64"
else
    arch="amd64"
    echo -e "${red}检查系统架构失败，将使用默认架构：${arch}${plain}"
fi

echo "系统架构: ${arch}"

# 检测系统版本
os_version=""
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本${plain}\n" && exit 1
    fi
fi

# 安装基础依赖
install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install wget curl tar -y
    else
        apt install wget curl tar -y
    fi
}

# 安装后配置
config_after_install() {
    echo -e "${yellow}安装/更新完成，出于安全考虑需要修改面板设置${plain}"
    read -p "是否继续，输入 n 将跳过此次设置[y/n]": config_confirm
    if [[ x"${config_confirm}" == x"y" || x"${config_confirm}" == x"Y" ]]; then
        read -p "请设置用户名:" config_account
        echo -e "${yellow}您的用户名将是:${config_account}${plain}"
        read -p "请设置密码:" config_password
        echo -e "${yellow}您的密码将是:${config_password}${plain}"
        read -p "请设置面板端口:" config_port
        echo -e "${yellow}您的面板端口是:${config_port}${plain}"
        echo -e "${yellow}正在初始化，请稍候...${plain}"
        /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password}
        echo -e "${yellow}账号和密码设置完成！${plain}"
        /usr/local/x-ui/x-ui setting -port ${config_port}
        echo -e "${yellow}面板端口设置完成！${plain}"
    else
        echo -e "${red}已取消...${plain}"
        if [[ ! -f "/etc/x-ui/x-ui.db" ]]; then
            local usernameTemp=$(head -c 6 /dev/urandom | base64)
            local passwordTemp=$(head -c 6 /dev/urandom | base64)
            local portTemp=$(echo $RANDOM)
            /usr/local/x-ui/x-ui setting -username ${usernameTemp} -password ${passwordTemp}
            /usr/local/x-ui/x-ui setting -port ${portTemp}
            echo -e "这是全新安装，将生成随机登录信息以确保安全："
            echo -e "###############################################"
            echo -e "${green}用户名:${usernameTemp}${plain}"
            echo -e "${green}密码:${passwordTemp}${plain}"
            echo -e "${red}面板端口:${portTemp}${plain}"
            echo -e "###############################################"
            echo -e "${red}如果您忘记了登录信息，安装后可以输入 x-ui 然后选择 7 查看${plain}"
        else
            echo -e "${red}这是您的升级，将保留原有设置，如果您忘记了登录信息，可以输入 x-ui 然后选择 7 查看${plain}"
        fi
    fi
}

# 安装 x-ui
install_x-ui() {
    systemctl stop x-ui 2>/dev/null || true
    cd /usr/local/

    if [ $# == 0 ]; then
        # 获取最新版本
        last_version=$(curl -Ls "https://api.github.com/repos/${RELEASE_REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}获取 x-ui 版本失败，可能是由于 Github API 限制，请稍后重试${plain}"
            exit 1
        fi
        echo -e "获取 x-ui 最新版本成功:${last_version}，开始安装..."
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz ${DOWNLOAD_BASE}/${last_version}/x-ui-linux-${arch}.tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 x-ui 失败，请确保您的服务器可以访问 Github${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="${DOWNLOAD_BASE}/${last_version}/x-ui-linux-${arch}.tar.gz"
        echo -e "开始安装 x-ui v$1 ..."
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 x-ui v$1 失败，请检查版本是否存在${plain}"
            exit 1
        fi
    fi

    if [[ -e /usr/local/x-ui/ ]]; then
        rm /usr/local/x-ui/ -rf
    fi

    mkdir -p /usr/local/x-ui
    tar zxvf x-ui-linux-${arch}.tar.gz -C /usr/local/x-ui --strip-components=1
    rm x-ui-linux-${arch}.tar.gz -f
    cd /usr/local/x-ui
    chmod +x x-ui x-ui.sh bin/xray-linux-${arch}
    # 使用官方压缩包中的服务文件和管理脚本
    if [ -f "/usr/local/x-ui/x-ui.service" ]; then
        cp /usr/local/x-ui/x-ui.service /etc/systemd/system/x-ui.service
    fi
    # 使用优化后的管理脚本（从脚本仓库下载）
    wget --no-check-certificate -O /usr/local/x-ui/x-ui.sh https://raw.githubusercontent.com/${SCRIPT_REPO}/main/x-ui.sh
    wget --no-check-certificate -O /usr/bin/x-ui https://raw.githubusercontent.com/${SCRIPT_REPO}/main/x-ui.sh
    chmod +x /usr/local/x-ui/x-ui.sh
    chmod +x /usr/bin/x-ui
    config_after_install
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
    echo -e "${green}x-ui v${last_version}${plain} 安装完成，正在运行中..."
    echo -e ""
    echo -e "x-ui 控制菜单使用方法："
    echo -e "----------------------------------------------"
    echo -e "x-ui           - 进入控制菜单"
    echo -e "x-ui start     - 启动 x-ui"
    echo -e "x-ui stop      - 停止 x-ui"
    echo -e "x-ui restart   - 重启 x-ui"
    echo -e "x-ui enable    - 设置开机自启"
    echo -e "x-ui disable   - 取消开机自启"
    echo -e "x-ui log       - 查看 x-ui 日志"
    echo -e "x-ui update    - 更新 x-ui"
    echo -e "x-ui install   - 安装 x-ui"
    echo -e "x-ui uninstall - 卸载 x-ui"
    echo -e "----------------------------------------------"
}

# 卸载 x-ui
echo_brick_red() {
    echo -e "\033[1;38;5;196m$1\033[0m"
}

uninstall_x-ui() {
    systemctl stop x-ui
    systemctl disable x-ui
    rm /etc/systemd/system/x-ui.service -f
    systemctl daemon-reload
    systemctl reset-failed
    rm /etc/x-ui/ -rf
    rm /usr/local/x-ui/ -rf
    rm /usr/bin/x-ui -f
    echo ""
    echo_brick_red "x-ui 及其配置已卸载，请退出当前终端并重新登录以生效！"
    echo ""
}

# 主程序
if [[ $# == 0 ]]; then
    install_base
    install_x-ui
else
    case $1 in
    install)
        install_base
        install_x-ui
        ;;
    uninstall)
        uninstall_x-ui
        ;;
    update)
        install_base
        install_x-ui
        ;;
    *)
        echo -e "${red}未知参数:$1${plain}"
        exit 1
        ;;
    esac
fi
