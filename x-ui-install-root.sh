#!/bin/bash
# X-UI 安装脚本 - MrChrootBSD Root 版本
# 适用于通过 MrChrootBSD 获取 root 后的 FreeBSD 环境

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
plain='\033[0m'

# ==================== 环境检测 ====================
detect_environment() {
    if [ "$(id -u)" = "0" ]; then
        echo -e "${green}当前以 root 权限运行${plain}"
        IS_ROOT=true
        ROOT_HOME="/root"
    else
        echo -e "${yellow}当前非 root 用户，部分功能可能受限${plain}"
        IS_ROOT=false
        ROOT_HOME="$HOME"
    fi
    
    # 检测是否在 MrChrootBSD 环境
    if [ -f "$HOME/.mrchroot_env" ]; then
        echo -e "${cyan}检测到 MrChrootBSD 环境${plain}"
        IS_MRCHROOT=true
    else
        IS_MRCHROOT=false
    fi
}

cd ~
cur_dir=$(pwd)

uname_output=$(uname -a)

# check os
if echo "$uname_output" | grep -Eqi "freebsd"; then
    release="freebsd"
elif echo "$uname_output" | grep -Eqi "linux"; then
    release="linux"
else
    echo -e "${red}未检测到支持的系统版本！${plain}\n" && exit 1
fi

arch="none"

if echo "$uname_output" | grep -Eqi 'x86_64|amd64|x64'; then
    arch="amd64"
elif echo "$uname_output" | grep -Eqi 'aarch64|arm64'; then
    arch="arm64"
else
    arch="amd64"
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo "系统: ${release}"
echo "架构: ${arch}"

# ==================== 端口管理函数 (Root 版本) ====================
# 在 root 环境下可以直接绑定端口，无需 devil

check_port() {
    local port=$1
    if command -v sockstat &>/dev/null; then
        sockstat -4 -l 2>/dev/null | grep -q ":$port " && return 1
    elif command -v netstat &>/dev/null; then
        netstat -an 2>/dev/null | grep -q "[:.]$port " && return 1
    elif command -v ss &>/dev/null; then
        ss -tlnp 2>/dev/null | grep -q ":$port " && return 1
    fi
    return 0
}

# 获取随机可用端口
get_random_port() {
    local min_port=${1:-10000}
    local max_port=${2:-65000}
    local max_attempts=50
    
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        local port=$((RANDOM % (max_port - min_port + 1) + min_port))
        
        if check_port $port; then
            echo "$port"
            return 0
        fi
        
        ((attempt++))
    done
    
    echo -e "${red}无法找到可用端口${plain}" >&2
    return 1
}

# ==================== 端口选择函数 ====================
choose_port() {
    local port_name=$1
    local default_port=$2
    
    echo "" >&2
    echo -e "${yellow}=== ${port_name} 端口配置 ===${plain}" >&2
    echo -e "  ${green}1.${plain} 手动指定端口" >&2
    echo -e "  ${green}2.${plain} 系统随机生成端口（推荐）" >&2
    echo "" >&2
    read -p "请选择 [1-2, 默认2]: " port_choice >&2
    port_choice=${port_choice:-2}
    
    local selected_port=""
    
    case "$port_choice" in
        1)
            read -p "请输入${port_name}端口 [${default_port}]: " selected_port >&2
            selected_port=${selected_port:-$default_port}
            
            if ! check_port "$selected_port"; then
                echo -e "${yellow}警告: 端口 $selected_port 可能已被占用${plain}" >&2
            fi
            ;;
        2)
            selected_port=$(get_random_port)
            if [[ -z "$selected_port" ]]; then
                echo -e "${red}随机端口获取失败${plain}" >&2
                return 1
            fi
            echo -e "${green}随机分配端口: ${selected_port}${plain}" >&2
            ;;
        *)
            selected_port=$(get_random_port)
            echo -e "${green}随机分配端口: ${selected_port}${plain}" >&2
            ;;
    esac
    
    echo "$selected_port"
    return 0
}

# 安装后配置
config_after_install() {
    echo -e "${yellow}出于安全考虑，安装/更新完成后需要强制修改端口与账户密码${plain}"
    read -p "确认是否继续?[y/n]: " config_confirm
    if [[ x"${config_confirm}" == x"y" || x"${config_confirm}" == x"Y" ]]; then
        read -p "请设置您的账户名: " config_account
        echo -e "${yellow}您的账户名将设定为:${config_account}${plain}"
        read -p "请设置您的账户密码: " config_password
        echo -e "${yellow}您的账户密码将设定为:${config_password}${plain}"
        
        # 选择面板访问端口
        local panel_port=$(choose_port "面板访问" 54321)
        if [[ $? -ne 0 ]]; then
            echo -e "${red}端口配置失败${plain}"
            return 1
        fi
        
        # 选择流量监测端口
        local traffic_port=$(choose_port "流量监测" 54322)
        if [[ $? -ne 0 ]]; then
            echo -e "${red}端口配置失败${plain}"
            return 1
        fi
        
        echo -e "${yellow}确认设定,设定中${plain}"
        ./x-ui setting -username ${config_account} -password ${config_password}
        echo -e "${yellow}账户密码设定完成${plain}"
        ./x-ui setting -port ${panel_port}
        echo -e "${yellow}面板访问端口设定完成${plain}"
        ./x-ui setting -trafficport ${traffic_port}
        echo -e "${yellow}面板流量监测端口设定完成${plain}"
        
        # 保存端口信息
        echo "${panel_port}" > ~/x-ui/.panel_port
        echo "${traffic_port}" > ~/x-ui/.traffic_port
    else
        echo -e "${red}已取消,所有设置项均为默认设置,请及时修改${plain}"
        echo -e "如果是全新安装，默认网页端口为 ${green}54321${plain}，默认流量监测端口为 ${green}54322${plain}，用户名和密码默认都是 ${green}admin${plain}"
    fi
}

stop_x-ui() {
    # 设置你想要杀死的nohup进程的命令名
    xui_com="./x-ui run"
    xray_com="bin/xray-$release-$arch -c bin/config.json"
 
    # 使用pgrep查找进程ID
    PID=$(pgrep -f "$xray_com")
 
    # 检查是否找到了进程
    if [ ! -z "$PID" ]; then
        kill $PID
        if kill -0 $PID > /dev/null 2>&1; then
            kill -9 $PID
        fi
    fi
    
    # 使用pgrep查找进程ID
    PID=$(pgrep -f "$xui_com")
 
    # 检查是否找到了进程
    if [ ! -z "$PID" ]; then
        kill $PID
        if kill -0 $PID > /dev/null 2>&1; then
            kill -9 $PID
        fi
    fi
}

install_x-ui() {
    detect_environment
    stop_x-ui

    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/hxzlplp7/serv00-xui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        wget -N --no-check-certificate -O x-ui-${release}-${arch}.tar.gz https://github.com/hxzlplp7/serv00-xui/releases/latest/download/x-ui-${release}-${arch}.tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 x-ui 失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/vaxilu/x-ui/releases/latest/download/x-ui-${release}-${arch}.tar.gz"
        echo -e "开始安装 x-ui v$1"
        wget -N --no-check-certificate -O x-ui-${release}-${arch}.tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 x-ui v$1 失败，请确保此版本存在${plain}"
            exit 1
        fi
    fi

    if [[ -e ./x-ui/ ]]; then
        rm -rf ./x-ui/
    fi

    tar zxvf x-ui-${release}-${arch}.tar.gz
    rm -f x-ui-${release}-${arch}.tar.gz
    cd x-ui
    
    # 兼容旧版本命名
    if [[ -f xui-release && ! -f x-ui ]]; then
        mv xui-release x-ui
        echo -e "${green}已将 xui-release 重命名为 x-ui${plain}"
    fi
    if [[ -f xui && ! -f x-ui ]]; then
        mv xui x-ui
        echo -e "${green}已将 xui 重命名为 x-ui${plain}"
    fi
    
    chmod +x x-ui bin/xray-${release}-${arch}
    cp x-ui.sh ../x-ui.sh
    chmod +x ../x-ui.sh
    chmod +x x-ui.sh
    
    config_after_install
    
    # 创建快捷命令
    echo -e "${yellow}正在创建 x-ui 快捷命令...${plain}"
    
    if [ "$IS_ROOT" = true ]; then
        # Root 环境下安装到系统目录
        cat > /usr/local/bin/x-ui << 'SHORTCUT'
#!/bin/bash
~/x-ui.sh "$@"
SHORTCUT
        chmod +x /usr/local/bin/x-ui
        echo -e "${green}快捷命令安装到 /usr/local/bin/x-ui${plain}"
    else
        # 非 root 安装到用户目录
        mkdir -p ~/bin
        cat > ~/bin/x-ui << 'SHORTCUT'
#!/bin/bash
~/x-ui.sh "$@"
SHORTCUT
        chmod +x ~/bin/x-ui
        
        # 添加 ~/bin 到 PATH
        shell_rc=""
        if [[ -f ~/.bashrc ]]; then
            shell_rc=~/.bashrc
        elif [[ -f ~/.profile ]]; then
            shell_rc=~/.profile
        elif [[ -f ~/.shrc ]]; then
            shell_rc=~/.shrc
        fi
        
        if [[ -n "$shell_rc" ]]; then
            if ! grep -q 'export PATH=.*\$HOME/bin' "$shell_rc" 2>/dev/null; then
                echo 'export PATH="$HOME/bin:$PATH"' >> "$shell_rc"
                echo -e "${green}已将 ~/bin 添加到 PATH${plain}"
            fi
        fi
        
        export PATH="$HOME/bin:$PATH"
    fi
    
    echo -e "${green}x-ui 快捷命令创建成功！${plain}"
    
    # 标记 MrChrootBSD 环境
    if [ "$IS_MRCHROOT" = true ]; then
        echo "mrchroot" > ~/x-ui/.env_type
    elif [ "$IS_ROOT" = true ]; then
        echo "root" > ~/x-ui/.env_type
    else
        echo "user" > ~/x-ui/.env_type
    fi
    
    # 创建 xray 保活脚本
    echo -e "${yellow}正在创建 xray 保活脚本...${plain}"
    cat > ~/x-ui/xray_keepalive.sh << 'XRAY_KEEPALIVE'
#!/bin/bash

# xray 保活脚本 - Root 版本
cd ~/x-ui

# 检测系统架构
uname_output=$(uname -a)
if echo "$uname_output" | grep -Eqi "freebsd"; then
    release="freebsd"
else
    release="linux"
fi

if echo "$uname_output" | grep -Eqi 'x86_64|amd64|x64'; then
    arch="amd64"
elif echo "$uname_output" | grep -Eqi 'aarch64|arm64'; then
    arch="arm64"
else
    arch="amd64"
fi

XRAY_BIN="bin/xray-${release}-${arch}"
XRAY_CONFIG="bin/config.json"

# 检查 xray 二进制文件是否存在
if [[ ! -f "$XRAY_BIN" ]]; then
    echo "$(date): xray 二进制文件不存在: $XRAY_BIN" >> xray_keepalive.log
    exit 1
fi

# 检查配置文件是否存在
if [[ ! -f "$XRAY_CONFIG" ]]; then
    echo "$(date): xray 配置文件不存在，可能还没有添加入站规则" >> xray_keepalive.log
    exit 0
fi

# 检查 xray 进程是否在运行
if ! pgrep -f "$XRAY_BIN" > /dev/null; then
    echo "$(date): xray 未运行，正在启动..." >> xray_keepalive.log
    nohup ./$XRAY_BIN -c $XRAY_CONFIG > xray.log 2>&1 &
    sleep 2
    
    if pgrep -f "$XRAY_BIN" > /dev/null; then
        echo "$(date): xray 启动成功" >> xray_keepalive.log
    else
        echo "$(date): xray 启动失败" >> xray_keepalive.log
    fi
fi
XRAY_KEEPALIVE
    chmod +x ~/x-ui/xray_keepalive.sh
    echo -e "${green}xray 保活脚本创建成功${plain}"
    
    # 设置定时任务
    setup_crontab
    
    # 启动 x-ui 面板
    nohup ./x-ui run > ./x-ui.log 2>&1 &
    sleep 2
    
    # 启动 xray（如果有配置文件）
    if [[ -f bin/config.json ]]; then
        echo -e "${yellow}正在启动 xray...${plain}"
        nohup ./bin/xray-${release}-${arch} -c bin/config.json > xray.log 2>&1 &
        sleep 2
        if pgrep -f "xray-${release}-${arch}" > /dev/null; then
            echo -e "${green}xray 启动成功${plain}"
        else
            echo -e "${yellow}xray 启动失败，请在面板中添加入站规则后会自动启动${plain}"
        fi
    else
        echo -e "${yellow}未检测到 xray 配置文件，请在面板中添加入站规则${plain}"
    fi
    
    echo -e "${green}x-ui v${last_version}${plain} 安装完成，面板已启动"
    echo -e ""
    echo -e "${cyan}x-ui 快捷命令使用方法:${plain}"
    echo -e "----------------------------------------------"
    echo -e "${green}x-ui${plain}                - 显示管理菜单"
    echo -e "${green}x-ui start${plain}          - 启动 x-ui 面板"
    echo -e "${green}x-ui stop${plain}           - 停止 x-ui 面板"
    echo -e "${green}x-ui restart${plain}        - 重启 x-ui 面板"
    echo -e "${green}x-ui status${plain}         - 查看 x-ui 状态"
    echo -e "----------------------------------------------"
    
    # 显示面板访问信息
    local panel_port=$(cat ~/x-ui/.panel_port 2>/dev/null || echo "54321")
    local my_ip=$(curl -s4m5 ip.sb 2>/dev/null || curl -s4m5 ifconfig.me 2>/dev/null || echo "YOUR_IP")
    echo -e ""
    echo -e "${cyan}面板访问地址:${plain}"
    echo -e "  http://${my_ip}:${panel_port}"
    echo -e ""
    
    if [ "$IS_MRCHROOT" = true ]; then
        echo -e "${yellow}提示: 当前在 MrChrootBSD 环境中运行${plain}"
    fi
}

# 设置定时任务
setup_crontab() {
    echo -e "${yellow}正在设置定时任务...${plain}"
    
    # 获取当前 crontab
    crontab -l > x-ui.cron 2>/dev/null || true
    
    # 删除旧的任务
    sed -i '' "/x-ui.log/d" x-ui.cron 2>/dev/null || sed -i "/x-ui.log/d" x-ui.cron 2>/dev/null || true
    sed -i '' "/xray_keepalive/d" x-ui.cron 2>/dev/null || sed -i "/xray_keepalive/d" x-ui.cron 2>/dev/null || true
    sed -i '' "/x-ui run/d" x-ui.cron 2>/dev/null || sed -i "/x-ui run/d" x-ui.cron 2>/dev/null || true
    
    # 添加新任务
    echo "# x-ui 日志清理" >> x-ui.cron
    echo "0 0 * * * cd $cur_dir/x-ui && cat /dev/null > x-ui.log" >> x-ui.cron
    echo "0 0 * * * cd $cur_dir/x-ui && cat /dev/null > xray.log" >> x-ui.cron
    echo "0 0 * * * cd $cur_dir/x-ui && cat /dev/null > xray_keepalive.log" >> x-ui.cron
    echo "" >> x-ui.cron
    echo "# x-ui 面板开机自启" >> x-ui.cron
    echo "@reboot cd $cur_dir/x-ui && nohup ./x-ui run > ./x-ui.log 2>&1 &" >> x-ui.cron
    echo "" >> x-ui.cron
    echo "# xray 保活（每分钟检查一次）" >> x-ui.cron
    echo "*/1 * * * * cd $cur_dir/x-ui && ./xray_keepalive.sh" >> x-ui.cron
    
    crontab x-ui.cron
    rm x-ui.cron
    echo -e "${green}定时任务设置完成${plain}"
}

echo -e "${green}开始安装 (Root 版本)${plain}"
install_x-ui $1
