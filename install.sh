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
GITHUB_REPO="875706361/x-ui_AI"
DOWNLOAD_BASE="https://github.com/${GITHUB_REPO}/releases/download"

# 检查 root
[[ $EUID -ne 0 ]] && echo -e "${red}Fatal error:${plain}please run this script with root privilege\n" && exit 1

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
    echo -e "${red}check system os failed,please contact with author!${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64"
else
    arch="amd64"
    echo -e "${red}fail to check system arch,will use default arch here: ${arch}${plain}"
fi

echo "架构: ${arch}"

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
        echo -e "${red}please use CentOS 7 or higher version${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}please use Ubuntu 16 or higher version${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}please use Debian 8 or higher version${plain}\n" && exit 1
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
    echo -e "${yellow}Install/update finished need to modify panel settings out of security${plain}"
    read -p "are you continue,if you type n will skip this at this time[y/n]": config_confirm
    if [[ x"${config_confirm}" == x"y" || x"${config_confirm}" == x"Y" ]]; then
        read -p "please set up your username:" config_account
        echo -e "${yellow}your username will be:${config_account}${plain}"
        read -p "please set up your password:" config_password
        echo -e "${yellow}your password will be:${config_password}${plain}"
        read -p "please set up the panel port:" config_port
        echo -e "${yellow}your panel port is:${config_port}${plain}"
        echo -e "${yellow}initializing,wait some time here...${plain}"
        /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password}
        echo -e "${yellow}account name and password set down!${plain}"
        /usr/local/x-ui/x-ui setting -port ${config_port}
        echo -e "${yellow}panel port set down!${plain}"
    else
        echo -e "${red}cancel...${plain}"
        if [[ ! -f "/etc/x-ui/x-ui.db" ]]; then
            local usernameTemp=$(head -c 6 /dev/urandom | base64)
            local passwordTemp=$(head -c 6 /dev/urandom | base64)
            local portTemp=$(echo $RANDOM)
            /usr/local/x-ui/x-ui setting -username ${usernameTemp} -password ${passwordTemp}
            /usr/local/x-ui/x-ui setting -port ${portTemp}
            echo -e "this is a fresh installation,will generate random login info for security concerns:"
            echo -e "###############################################"
            echo -e "${green}user name:${usernameTemp}${plain}"
            echo -e "${green}user password:${passwordTemp}${plain}"
            echo -e "${red}web port:${portTemp}${plain}"
            echo -e "###############################################"
            echo -e "${red}if you forgot your login info,you can type x-ui and then type 7 to check after installation${plain}"
        else
            echo -e "${red} this is your upgrade,will keep old settings,if you forgot your login info,you can type x-ui and then type 7 to check${plain}"
        fi
    fi
}

# 安装 x-ui
install_x-ui() {
    systemctl stop x-ui 2>/dev/null || true
    cd /usr/local/

    if [ $# == 0 ]; then
        # 获取最新版本
        last_version=$(curl -Ls "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}refresh x-ui version failed,it may due to Github API restriction,please try it later${plain}"
            exit 1
        fi
        echo -e "get x-ui latest version succeed:${last_version},begin to install..."
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz ${DOWNLOAD_BASE}/${last_version}/x-ui-v1.0.0-cpu-optimized-linux-${arch}.tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}download x-ui failed,please be sure that your server can access Github${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="${DOWNLOAD_BASE}/${last_version}/x-ui-v1.0.0-cpu-optimized-linux-${arch}.tar.gz"
        echo -e "begin to install x-ui v$1 ..."
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}download x-ui v$1 failed,please check the version exists${plain}"
            exit 1
        fi
    fi

    if [[ -e /usr/local/x-ui/ ]]; then
        rm /usr/local/x-ui/ -rf
    fi

    mkdir -p /usr/local/x-ui
    tar zxvf x-ui-linux-${arch}.tar.gz -C /usr/local/x-ui
    rm x-ui-linux-${arch}.tar.gz -f
    cd /usr/local/x-ui
    chmod +x x-ui xray-linux-${arch}
    # 创建 bin 目录并移动 xray
    mkdir -p bin
    mv xray-linux-${arch} bin/
    # 服务文件从仓库下载
    wget --no-check-certificate -O /etc/systemd/system/x-ui.service https://raw.githubusercontent.com/${GITHUB_REPO}/master/x-ui.service
    # 管理脚本从仓库下载
    wget --no-check-certificate -O /usr/local/x-ui/x-ui.sh https://raw.githubusercontent.com/${GITHUB_REPO}/master/x-ui.sh
    wget --no-check-certificate -O /usr/bin/x-ui https://raw.githubusercontent.com/${GITHUB_REPO}/master/x-ui.sh
    config_after_install
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
    echo -e "${green}x-ui v${last_version}${plain} install finished,it is working now..."
    echo -e ""
    echo -e "x-ui control menu usages: "
    echo -e "----------------------------------------------"
    echo -e "x-ui              - Enter     control menu"
    echo -e "x-ui start        - Start     x-ui "
    echo -e "x-ui stop         - Stop      x-ui "
    echo -e "x-ui restart      - Restart   x-ui "
    echo -e "x-ui enable       - Enable    x-ui on boot"
    echo -e "x-ui disable      - Disable   x-ui on boot"
    echo -e "x-ui log          - Show      x-ui logs"
    echo -e "x-ui update       - Update    x-ui"
    echo -e "x-ui install      - Install   x-ui"
    echo -e "x-ui uninstall    - Uninstall x-ui"
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
    echo_brick_red "Uninstall x-ui and its config done,please exit this terminal and re-login to take effect!"
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
        echo -e "${red}unknown parameter:$1${plain}"
        exit 1
        ;;
    esac
fi
