#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
plain='\033[0m'

cd ~
cur_dir=$(pwd)

uname_output=$(uname -a)

# check os
if echo "$uname_output" | grep -Eqi "freebsd"; then
    release="freebsd"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
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

echo "架构: ${arch}"

# ==================== 系统类型检测 ====================
detect_system_type() {
    # 检测是 serv00 还是 hostuno
    if [[ -f /usr/home/.system_type ]]; then
        cat /usr/home/.system_type
    elif command -v devil >/dev/null 2>&1; then
        # 通过 devil 命令判断
        local devil_output=$(devil --help 2>&1)
        if echo "$devil_output" | grep -qi "serv00"; then
            echo "serv00"
        elif echo "$devil_output" | grep -qi "hostuno"; then
            echo "hostuno"
        else
            # 默认按 serv00 处理
            echo "serv00"
        fi
    else
        echo "unknown"
    fi
}

SYSTEM_TYPE=$(detect_system_type)
echo -e "${cyan}检测到系统类型: ${SYSTEM_TYPE}${plain}"

# ==================== Devil 端口管理函数 ====================

# 检查端口是否已被 devil 添加
check_devil_port() {
    local port=$1
    local port_type=$2  # tcp 或 udp
    
    if ! command -v devil >/dev/null 2>&1; then
        return 1
    fi
    
    # 检查端口是否已添加
    devil port list | grep -q "${port_type} ${port}"
    return $?
}

# 使用 devil 添加端口，支持重试
add_devil_port() {
    local port=$1
    local port_type=$2  # tcp 或 udp
    local description=$3
    local max_retries=${4:-5}
    
    if ! command -v devil >/dev/null 2>&1; then
        echo -e "${yellow}devil 命令不可用，跳过端口添加${plain}" >&2
        return 0
    fi
    
    # 如果已经添加过，直接返回成功
    if check_devil_port "$port" "$port_type"; then
        echo -e "${green}✓ 端口 ${port_type}/${port} 已存在${plain}" >&2
        return 0
    fi
    
    local retry=0
    while [ $retry -lt $max_retries ]; do
        echo -e "${yellow}正在添加端口 ${port_type}/${port}... (尝试 $((retry+1))/${max_retries})${plain}" >&2
        
        # 执行 devil port add
        local result=$(devil port add ${port_type} ${port} "${description}" 2>&1)
        
        if [[ $? -eq 0 ]] || echo "$result" | grep -qi "success\|successfully\|已添加"; then
            echo -e "${green}✓ 端口 ${port_type}/${port} 添加成功${plain}" >&2
            return 0
        elif echo "$result" | grep -qi "already\|exists\|已存在"; then
            echo -e "${green}✓ 端口 ${port_type}/${port} 已存在${plain}" >&2
            return 0
        else
            echo -e "${red}✗ 添加失败: $result${plain}" >&2
            ((retry++))
            if [ $retry -lt $max_retries ]; then
                sleep 1
            fi
        fi
    done
    
    echo -e "${red}端口 ${port_type}/${port} 添加失败，已重试 ${max_retries} 次${plain}" >&2
    return 1
}

# 获取随机可用端口并添加到 devil
get_random_devil_port() {
    local port_type=$1  # tcp 或 udp
    local description=$2
    local min_port=${3:-10000}
    local max_port=${4:-65000}
    local max_attempts=50
    
    if ! command -v devil >/dev/null 2>&1; then
        # 如果没有 devil 命令，直接返回随机端口
        echo $((RANDOM % (max_port - min_port + 1) + min_port))
        return 0
    fi
    
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        local port=$((RANDOM % (max_port - min_port + 1) + min_port))
        
        # 检查端口是否被占用
        if ! sockstat -l | grep -q ":$port "; then
            # 尝试添加端口
            if add_devil_port "$port" "$port_type" "$description"; then
                echo "$port"
                return 0
            fi
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
    local port_type=${3:-tcp}  # tcp 或 udp
    
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
            
            # 使用 devil 添加端口
            if ! add_devil_port "$selected_port" "$port_type" "x-ui ${port_name}"; then
                echo -e "${red}端口添加失败，是否重新选择? [y/n]${plain}" >&2
                read -p "" retry >&2
                if [[ "$retry" == "y" || "$retry" == "Y" ]]; then
                    choose_port "$port_name" "$default_port" "$port_type"
                    return $?
                else
                    return 1
                fi
            fi
            ;;
        2)
            selected_port=$(get_random_devil_port "$port_type" "x-ui ${port_name}")
            if [[ -z "$selected_port" ]]; then
                echo -e "${red}随机端口获取失败${plain}" >&2
                return 1
            fi
            echo -e "${green}随机分配端口: ${selected_port}${plain}" >&2
            ;;
        *)
            selected_port=$(get_random_devil_port "$port_type" "x-ui ${port_name}")
            echo -e "${green}随机分配端口: ${selected_port}${plain}" >&2
            ;;
    esac
    
    echo "$selected_port"
    return 0
}

#This function will be called when user installed x-ui out of sercurity
config_after_install() {
    echo -e "${yellow}出于安全考虑，安装/更新完成后需要强制修改端口与账户密码${plain}"
    read -p "确认是否继续?[y/n]: " config_confirm
    if [[ x"${config_confirm}" == x"y" || x"${config_confirm}" == x"Y" ]]; then
        read -p "请设置您的账户名: " config_account
        echo -e "${yellow}您的账户名将设定为:${config_account}${plain}"
        read -p "请设置您的账户密码: " config_password
        echo -e "${yellow}您的账户密码将设定为:${config_password}${plain}"
        
        # 选择面板访问端口
        local panel_port=$(choose_port "面板访问" 54321 "tcp")
        if [[ $? -ne 0 ]]; then
            echo -e "${red}端口配置失败${plain}"
            return 1
        fi
        
        # 选择流量监测端口
        local traffic_port=$(choose_port "流量监测" 54322 "tcp")
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
        echo -e "请自行确保此端口没有被其他程序占用，${yellow}并且确保 54321 和 54322 端口已放行${plain}"
        echo -e "若想将 54321 和 54322 修改为其它端口，输入 x-ui 命令进行修改，同样也要确保你修改的端口也是放行的"
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
        # 找到了进程，杀死它
        kill $PID
    
        # 可选：检查进程是否已经被杀死
        if kill -0 $PID > /dev/null 2>&1; then
            kill -9 $PID
        fi
    fi
    # 使用pgrep查找进程ID
    PID=$(pgrep -f "$xui_com")
 
    # 检查是否找到了进程
    if [ ! -z "$PID" ]; then
        # 找到了进程，杀死它
        kill $PID
    
        # 可选：检查进程是否已经被杀死
        if kill -0 $PID > /dev/null 2>&1; then
            kill -9 $PID
        fi
    fi
}

install_x-ui() {
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
    # 兼容旧版本：如果二进制文件名为 xui-release，则重命名为 x-ui
    if [[ -f xui-release && ! -f x-ui ]]; then
        mv xui-release x-ui
        echo -e "${green}已将 xui-release 重命名为 x-ui${plain}"
    fi
    # 兼容另一种可能的命名：xui
    if [[ -f xui && ! -f x-ui ]]; then
        mv xui x-ui
        echo -e "${green}已将 xui 重命名为 x-ui${plain}"
    fi
    chmod +x x-ui bin/xray-${release}-${arch}
    #cp -f x-ui.service /etc/systemd/system/
    cp x-ui.sh ../x-ui.sh
    chmod +x ../x-ui.sh
    chmod +x x-ui.sh
    config_after_install
    #echo -e ""
    #echo -e "如果是更新面板，则按你之前的方式访问面板"
    #echo -e ""
    crontab -l > x-ui.cron
    sed -i "" "/x-ui.log/d" x-ui.cron
    echo "0 0 * * * cd $cur_dir/x-ui && cat /dev/null > x-ui.log" >> x-ui.cron
    echo "@reboot cd $cur_dir/x-ui && nohup ./x-ui run > ./x-ui.log 2>&1 &" >> x-ui.cron
    crontab x-ui.cron
    rm x-ui.cron
    
    # 创建快捷命令
    echo -e "${yellow}正在创建 x-ui 快捷命令...${plain}"
    mkdir -p ~/bin
    cat > ~/bin/x-ui << 'SHORTCUT'
#!/bin/bash
~/x-ui.sh "$@"
SHORTCUT
    chmod +x ~/bin/x-ui
    
    # 添加 ~/bin 到 PATH（如果还没有）
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
    
    # 临时添加到当前会话
    export PATH="$HOME/bin:$PATH"
    
    # 保存系统类型
    echo "$SYSTEM_TYPE" > ~/x-ui/.system_type
    
    echo -e "${green}x-ui 快捷命令创建成功！${plain}"
    
    # 创建 xray 保活脚本
    echo -e "${yellow}正在创建 xray 保活脚本...${plain}"
    cat > ~/x-ui/xray_keepalive.sh << 'XRAY_KEEPALIVE'
#!/bin/bash

# xray 保活脚本
cd ~/x-ui

# 检测系统架构
uname_output=$(uname -a)
if echo "$uname_output" | grep -Eqi "freebsd"; then
    release="freebsd"
else
    release="freebsd"
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
    
    # 添加定时任务
    echo -e "${yellow}正在设置定时任务...${plain}"
    crontab -l > x-ui.cron 2>/dev/null || true
    
    # 删除旧的任务
    sed -i "" "/x-ui.log/d" x-ui.cron 2>/dev/null || true
    sed -i "" "/xray_keepalive/d" x-ui.cron 2>/dev/null || true
    sed -i "" "/x-ui run/d" x-ui.cron 2>/dev/null || true
    
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
    
    echo -e "${green}x-ui v${last_version}${plain} 安装完成，面板已启动，"
    echo -e ""
    echo -e "${cyan}x-ui 快捷命令使用方法:${plain}"
    echo -e "----------------------------------------------"
    echo -e "${green}x-ui${plain}                - 显示管理菜单 (功能更多)"
    echo -e "${green}x-ui start${plain}          - 启动 x-ui 面板"
    echo -e "${green}x-ui stop${plain}           - 停止 x-ui 面板"
    echo -e "${green}x-ui restart${plain}        - 重启 x-ui 面板"
    echo -e "${green}x-ui status${plain}         - 查看 x-ui 状态"
    echo -e "${green}x-ui enable${plain}         - 设置 x-ui 开机自启"
    echo -e "${green}x-ui disable${plain}        - 取消 x-ui 开机自启"
    echo -e "${green}x-ui update${plain}         - 更新 x-ui 面板"
    echo -e "${green}x-ui install${plain}        - 安装 x-ui 面板"
    echo -e "${green}x-ui uninstall${plain}      - 卸载 x-ui 面板"
    echo -e "----------------------------------------------"
    echo -e "${yellow}提示: 如果 x-ui 命令不可用，请执行: source ~/.bashrc 或重新登录${plain}"
    echo -e "${cyan}提示: xray 保活脚本已设置，每分钟自动检查并启动 xray${plain}"
}

echo -e "${green}开始安装${plain}"
#install_base
install_x-ui $1
