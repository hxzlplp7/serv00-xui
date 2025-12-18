#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
purple='\033[0;35m'
cyan='\033[0;36m'
plain='\033[0m'

#Add some basic function here
function LOGD() {
    echo -e "${yellow}[DEG] $* ${plain}" >&2
}

function LOGE() {
    echo -e "${red}[ERR] $* ${plain}" >&2
}

function LOGI() {
    echo -e "${green}[INF] $* ${plain}" >&2
}

cd ~
cur_dir=$(pwd)
uname_output=$(uname -a)
enable_str="nohup \.\\/x-ui run"



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

# ==================== 基础函数 ====================

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -p "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "是否重启面板，重启面板也会重启 xray" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

# ==================== 系统类型检测 ====================

# 检测系统类型 (serv00 / hostuno / unknown)
detect_system_type() {
    if [[ -f ~/x-ui/.system_type ]]; then
        cat ~/x-ui/.system_type
    elif command -v devil >/dev/null 2>&1; then
        local devil_output=$(devil --help 2>&1)
        if echo "$devil_output" | grep -qi "serv00"; then
            echo "serv00"
        elif echo "$devil_output" | grep -qi "hostuno"; then
            echo "hostuno"
        else
            echo "serv00"
        fi
    else
        echo "unknown"
    fi
}

SYSTEM_TYPE=$(detect_system_type)

# ==================== Devil 端口管理函数 ====================

# 检查端口是否已被 devil 添加
check_devil_port() {
    local port=$1
    local port_type=$2  # tcp 或 udp
    
    if ! command -v devil >/dev/null 2>&1; then
        return 1
    fi
    
    devil port list 2>/dev/null | grep -q "${port_type} ${port}"
    return $?
}

# 使用 devil 添加端口，支持重试
add_devil_port() {
    local port=$1
    local port_type=$2  # tcp 或 udp
    local description=$3
    local max_retries=${4:-5}
    
    if ! command -v devil >/dev/null 2>&1; then
        LOGD "devil 命令不可用，跳过端口添加"
        return 0
    fi
    
    # 如果已经添加过，直接返回成功
    if check_devil_port "$port" "$port_type"; then
        LOGI "端口 ${port_type}/${port} 已存在"
        return 0
    fi
    
    local retry=0
    while [ $retry -lt $max_retries ]; do
        LOGD "正在添加端口 ${port_type}/${port}... (尝试 $((retry+1))/$max_retries)"
        
        # 执行 devil port add 并捕获输出和退出码
        local result=$(devil port add ${port_type} ${port} "${description}" 2>&1)
        local exit_code=$?
        
        # 显示 devil 命令的原始输出（用于调试）
        if [[ -n "$result" ]]; then
            LOGD "Devil 命令输出: $result"
        fi
        
        if [[ $exit_code -eq 0 ]]; then
            LOGI "✓ 端口 ${port_type}/${port} 添加成功"
            return 0
        elif echo "$result" | grep -qi "success\|successfully\|已添加"; then
            LOGI "✓ 端口 ${port_type}/${port} 添加成功"
            return 0
        elif echo "$result" | grep -qi "already\|exists\|已存在"; then
            LOGI "✓ 端口 ${port_type}/${port} 已存在"
            return 0
        else
            LOGE "✗ 添加失败 (退出码: $exit_code): $result"
            ((retry++))
            if [ $retry -lt $max_retries ]; then
                sleep 1
            fi
        fi
    done
    
    LOGE "端口 ${port_type}/${port} 添加失败，已重试 ${max_retries} 次"
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
        if ! sockstat -l 2>/dev/null | grep -q ":$port "; then
            # 尝试添加端口
            if add_devil_port "$port" "$port_type" "$description"; then
                echo "$port"
                return 0
            fi
        fi
        
        ((attempt++))
    done
    
    LOGE "无法找到可用端口"
    return 1
}

# 检测协议类型 (tcp/udp/both)
detect_protocol_type() {
    local protocol=$1
    
    case "$protocol" in
        hysteria2|hy2|tuic|quic)
            echo "udp"
            ;;
        vless|vmess|trojan|ss|shadowsocks|socks|http|https|anytls)
            echo "tcp"
            ;;
        *)
            # 默认 TCP
            echo "tcp"
            ;;
    esac
}

before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp
    show_menu
}

# ==================== URL解码函数 ====================
urldecode() {
    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

# ==================== Base64解码函数 ====================
base64_decode() {
    local input="$1"
    # 添加padding
    local padding=$((4 - ${#input} % 4))
    if [[ $padding -ne 4 ]]; then
        for ((i=0; i<padding; i++)); do
            input="${input}="
        done
    fi
    echo "$input" | base64 -d 2>/dev/null
}

# ==================== 解析节点链接函数 ====================

# 解析VLESS链接
parse_vless() {
    local link="$1"
    # vless://uuid@host:port?params#name
    local content="${link#vless://}"
    local name="${content##*#}"
    name=$(urldecode "$name")
    content="${content%#*}"
    
    local userinfo="${content%%@*}"
    local rest="${content#*@}"
    local hostport="${rest%%\?*}"
    local params="${rest#*\?}"
    
    local host="${hostport%:*}"
    local port="${hostport##*:}"
    
    echo "vless|$host|$port|$name|$userinfo|$params"
}

# 解析VMess链接
parse_vmess() {
    local link="$1"
    local content="${link#vmess://}"
    local decoded=$(base64_decode "$content")
    
    if [[ -z "$decoded" ]]; then
        echo ""
        return
    fi
    
    # 从JSON提取信息
    local host=$(echo "$decoded" | grep -o '"add"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*": *"\([^"]*\)".*/\1/')
    local port=$(echo "$decoded" | grep -o '"port"[[:space:]]*:[[:space:]]*[^,}]*' | head -1 | sed 's/.*: *\([0-9]*\).*/\1/')
    local name=$(echo "$decoded" | grep -o '"ps"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*": *"\([^"]*\)".*/\1/')
    
    echo "vmess|$host|$port|$name|$decoded"
}

# 解析Trojan链接
parse_trojan() {
    local link="$1"
    # trojan://password@host:port?params#name
    local content="${link#trojan://}"
    local name="${content##*#}"
    name=$(urldecode "$name")
    content="${content%#*}"
    
    local password="${content%%@*}"
    local rest="${content#*@}"
    local hostport="${rest%%\?*}"
    local params="${rest#*\?}"
    
    local host="${hostport%:*}"
    local port="${hostport##*:}"
    
    echo "trojan|$host|$port|$name|$password|$params"
}

# 解析Shadowsocks链接
parse_shadowsocks() {
    local link="$1"
    # ss://base64(method:password)@host:port#name 或
    # ss://base64(method:password@host:port)#name
    local content="${link#ss://}"
    local name="${content##*#}"
    name=$(urldecode "$name")
    content="${content%#*}"
    
    local host=""
    local port=""
    
    if [[ "$content" == *"@"* ]]; then
        # 新格式: base64@host:port
        local encoded="${content%%@*}"
        local hostport="${content#*@}"
        host="${hostport%:*}"
        port="${hostport##*:}"
    else
        # 旧格式: 全部base64编码
        local decoded=$(base64_decode "$content")
        host=$(echo "$decoded" | grep -oE '[^@]+$' | cut -d: -f1)
        port=$(echo "$decoded" | grep -oE '[^@]+$' | cut -d: -f2)
    fi
    
    echo "ss|$host|$port|$name"
}

# 解析Hysteria2链接
parse_hysteria2() {
    local link="$1"
    # hysteria2://password@host:port?params#name
    local content="${link#hysteria2://}"
    content="${content#hy2://}"
    local name="${content##*#}"
    name=$(urldecode "$name")
    content="${content%#*}"
    
    local password="${content%%@*}"
    local rest="${content#*@}"
    local hostport="${rest%%\?*}"
    local params="${rest#*\?}"
    
    local host="${hostport%:*}"
    local port="${hostport##*:}"
    
    echo "hysteria2|$host|$port|$name|$password|$params"
}

# 解析TUIC链接
parse_tuic() {
    local link="$1"
    # tuic://uuid:password@host:port?params#name
    local content="${link#tuic://}"
    local name="${content##*#}"
    name=$(urldecode "$name")
    content="${content%#*}"
    
    local userinfo="${content%%@*}"
    local rest="${content#*@}"
    local hostport="${rest%%\?*}"
    local params="${rest#*\?}"
    
    local host="${hostport%:*}"
    local port="${hostport##*:}"
    
    echo "tuic|$host|$port|$name|$userinfo|$params"
}

# 解析Socks链接
parse_socks() {
    local link="$1"
    # socks://base64(user:pass)@host:port#name 或
    # socks5://user:pass@host:port
    local content="${link#socks://}"
    content="${content#socks5://}"
    local name="${content##*#}"
    name=$(urldecode "$name")
    content="${content%#*}"
    
    local host=""
    local port=""
    
    if [[ "$content" == *"@"* ]]; then
        local hostport="${content#*@}"
        host="${hostport%:*}"
        port="${hostport##*:}"
    else
        host="${content%:*}"
        port="${content##*:}"
    fi
    
    echo "socks|$host|$port|$name"
}

# 解析HTTP代理链接
parse_http() {
    local link="$1"
    # http://user:pass@host:port 或 http://host:port
    local content="${link#http://}"
    content="${content#https://}"
    local name="${content##*#}"
    name=$(urldecode "$name")
    content="${content%#*}"
    
    local host=""
    local port=""
    
    if [[ "$content" == *"@"* ]]; then
        local hostport="${content#*@}"
        host="${hostport%:*}"
        port="${hostport##*:}"
    else
        host="${content%:*}"
        port="${content##*:}"
    fi
    
    echo "http|$host|$port|$name"
}

# 解析AnyTLS链接
parse_anytls() {
    local link="$1"
    # anytls://password@host:port?params#name
    local content="${link#anytls://}"
    local name="${content##*#}"
    name=$(urldecode "$name")
    content="${content%#*}"
    
    local password="${content%%@*}"
    local rest="${content#*@}"
    local hostport="${rest%%\?*}"
    local params="${rest#*\?}"
    
    local host="${hostport%:*}"
    local port="${hostport##*:}"
    
    echo "anytls|$host|$port|$name|$password|$params"
}

# 自动识别并解析节点
parse_node() {
    local link="$1"
    
    if [[ "$link" == vless://* ]]; then
        parse_vless "$link"
    elif [[ "$link" == vmess://* ]]; then
        parse_vmess "$link"
    elif [[ "$link" == trojan://* ]]; then
        parse_trojan "$link"
    elif [[ "$link" == ss://* ]]; then
        parse_shadowsocks "$link"
    elif [[ "$link" == hysteria2://* ]] || [[ "$link" == hy2://* ]]; then
        parse_hysteria2 "$link"
    elif [[ "$link" == tuic://* ]]; then
        parse_tuic "$link"
    elif [[ "$link" == anytls://* ]]; then
        parse_anytls "$link"
    elif [[ "$link" == socks://* ]] || [[ "$link" == socks5://* ]]; then
        parse_socks "$link"
    elif [[ "$link" == http://* ]] || [[ "$link" == https://* ]]; then
        parse_http "$link"
    else
        echo ""
    fi
}

# ==================== 原有功能函数 ====================

update() {
    confirm "本功能会强制重装当前最新版，数据不会丢失，是否继续?" "n"
    if [[ $? != 0 ]]; then
        LOGE "已取消"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    cd ~
    wget -N --no-check-certificate -O x-ui-install.sh https://raw.githubusercontent.com/hxzlplp7/serv00-xui/main/x-ui-install.sh
    chmod +x x-ui-install.sh
    ./x-ui-install.sh
    if [[ $? == 0 ]]; then
        LOGI "更新完成，已自动重启面板 "
        exit 0
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

install() {
    cd ~
    wget -N --no-check-certificate -O x-ui-install.sh https://raw.githubusercontent.com/hxzlplp7/serv00-xui/main/x-ui-install.sh
    chmod +x x-ui-install.sh
    ./x-ui-install.sh
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

uninstall() {
    confirm "确定要卸载面板吗,xray 也会卸载?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    
    # 停止服务
    stop_x-ui
    
    # 删除 devil 端口
    if command -v devil >/dev/null 2>&1; then
        echo ""
        LOGI "正在清理 devil 端口..."
        
        local all_ports=""
        
        # 读取面板访问端口
        if [[ -f "$HOME/x-ui/.panel_port" ]]; then
            local panel_port=$(cat "$HOME/x-ui/.panel_port" 2>/dev/null)
            if [[ -n "$panel_port" ]]; then
                all_ports="$all_ports $panel_port"
                LOGD "面板访问端口: $panel_port"
            fi
        fi
        
        # 读取流量监测端口
        if [[ -f "$HOME/x-ui/.traffic_port" ]]; then
            local traffic_port=$(cat "$HOME/x-ui/.traffic_port" 2>/dev/null)
            if [[ -n "$traffic_port" ]]; then
                all_ports="$all_ports $traffic_port"
                LOGD "流量监测端口: $traffic_port"
            fi
        fi
        
        # 从数据库中读取所有入站端口
        local db_path="$HOME/x-ui/x-ui.db"
        if [[ -f "$db_path" ]]; then
            local inbound_ports=$(sqlite3 "$db_path" "SELECT DISTINCT port FROM inbounds;" 2>/dev/null | tr '\n' ' ')
            if [[ -n "$inbound_ports" ]]; then
                all_ports="$all_ports $inbound_ports"
                LOGD "入站端口: $inbound_ports"
            fi
        fi
        
        # 去重端口列表
        all_ports=$(echo "$all_ports" | tr ' ' '\n' | sort -u | tr '\n' ' ')
        
        if [[ -n "$all_ports" ]]; then
            LOGI "发现以下端口: $all_ports"
            confirm "是否删除这些 devil 端口?" "y"
            if [[ $? == 0 ]]; then
                for port in $all_ports; do
                    # 尝试删除 TCP 端口
                    if devil port list 2>/dev/null | grep -q "tcp $port"; then
                        LOGD "删除 TCP 端口: $port"
                        devil port del tcp $port 2>/dev/null && LOGI "✓ TCP/$port 已删除" || LOGD "TCP/$port 删除失败"
                    fi
                    
                    # 尝试删除 UDP 端口
                    if devil port list 2>/dev/null | grep -q "udp $port"; then
                        LOGD "删除 UDP 端口: $port"
                        devil port del udp $port 2>/dev/null && LOGI "✓ UDP/$port 已删除" || LOGD "UDP/$port 删除失败"
                    fi
                done
            else
                LOGD "跳过端口删除"
            fi
        else
            LOGD "未发现需要删除的端口"
        fi
        echo ""
    fi
    
    # 删除定时任务
    crontab -l > x-ui.cron 2>/dev/null
    sed -i "" "/x-ui.log/d" x-ui.cron 2>/dev/null
    sed -i "" "/xray/d" x-ui.cron 2>/dev/null
    sed -i "" "/x-ui run/d" x-ui.cron 2>/dev/null
    crontab x-ui.cron
    rm x-ui.cron
    
    # 删除文件
    cd ~
    rm -rf ~/x-ui/
    
    # 删除快捷命令
    if [[ -f ~/bin/x-ui ]]; then
        rm -f ~/bin/x-ui
        LOGI "已删除快捷命令 ~/bin/x-ui"
    fi
    
    # 删除主脚本文件
    if [[ -f ~/x-ui.sh ]]; then
        rm -f ~/x-ui.sh
        LOGI "已删除脚本 ~/x-ui.sh"
    fi

    echo ""
    echo -e "卸载成功，如果你想删除此脚本，则退出脚本后运行 ${green}rm ~/x-ui.sh -f${plain} 进行删除"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

reset_user() {
    confirm "确定要将用户名和密码重置为 admin 吗" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    ~/x-ui/x-ui setting -username admin -password admin
    echo -e "用户名和密码已重置为 ${green}admin${plain}，现在请重启面板"
    confirm_restart
}

reset_config() {
    confirm "确定要重置所有面板设置吗，账号数据不会丢失，用户名和密码不会改变" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    ~/x-ui/x-ui setting -reset
    echo -e "所有面板设置已重置为默认值，现在请重启面板，并使用默认的 ${green}54321${plain} 端口访问面板"
    confirm_restart
}

check_config() {
    info=$(~/x-ui/x-ui setting -show true)
    if [[ $? != 0 ]]; then
        LOGE "get current settings error,please check logs"
        show_menu
    fi
    LOGI "${info}"
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

set_port() {
    echo && echo -n -e "输入端口号[1-65535]: " && read port
    if [[ -z "${port}" ]]; then
        LOGD "已取消"
        before_show_menu
    else
        ~/x-ui/x-ui setting -port ${port}
        echo -e "设置面板访问端口完毕，现在请重启面板，并使用新设置的端口 ${green}${port}${plain} 访问面板"
        confirm_restart
    fi
}

set_traffic_port() {
    echo && echo -n -e "输入流量监测端口号[1-65535]: " && read trafficport
    if [[ -z "${trafficport}" ]]; then
        LOGD "已取消"
        before_show_menu
    else
        ~/x-ui/x-ui setting -trafficport ${trafficport}
        echo -e "设置流量监测端口完毕，现在请重启面板，并使用新设置的端口 ${green}${trafficport}${plain} 访问面板"
        confirm_restart
    fi
}


start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        LOGI "面板已运行，无需再次启动，如需重启请选择重启"
    else
        cd ~/x-ui
        nohup ./x-ui run > ./x-ui.log 2>&1 &
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            LOGI "x-ui 启动成功"
        else
            LOGE "面板启动失败，可能是因为启动时间超过了两秒，请稍后查看日志信息"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    check_status
    if [[ $? == 1 ]]; then
        echo ""
        LOGI "面板已停止，无需再次停止"
    else
        stop_x-ui
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            LOGI "x-ui 与 xray 停止成功"
        else
            LOGE "面板停止失败，可能是因为停止时间超过了两秒，请稍后查看日志信息"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    stop 0
    start 0
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        LOGI "x-ui 与 xray 重启成功"
    else
        LOGE "面板重启失败，可能是因为启动时间超过了两秒，请稍后查看日志信息"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    COMMAND_NAME="./x-ui run"
    PID=$(pgrep -f "$COMMAND_NAME")
 
    # 检查是否找到了进程
    if [ ! -z "$PID" ]; then
        LOGI "x-ui 运行中"
    else
        LOGI "x-ui 没有运行"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    crontab -l > x-ui.cron
    sed -i "" "/$enable_str/d" x-ui.cron
    echo "@reboot cd $cur_dir/x-ui && nohup ./x-ui run > ./x-ui.log 2>&1 &" >> x-ui.cron
    crontab x-ui.cron
    rm x-ui.cron
    if [[ $? == 0 ]]; then
        LOGI "x-ui 设置开机自启成功"
    else
        LOGE "x-ui 设置开机自启失败"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    crontab -l > x-ui.cron
    sed -i "" "/$enable_str/d" x-ui.cron
    crontab x-ui.cron
    rm x-ui.cron
    if [[ $? == 0 ]]; then
        LOGI "x-ui 取消开机自启成功"
    else
        LOGE "x-ui 取消开机自启失败"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# 查看运行日志
show_log() {
    echo -e "${green}========== x-ui 运行日志 ==========${plain}"
    echo -e "${yellow}日志文件位置: ~/x-ui/x-ui.log${plain}"
    echo ""
    
    if [[ -f ~/x-ui/x-ui.log ]]; then
        echo -e "${cyan}--- 最近 50 行日志 ---${plain}"
        tail -n 50 ~/x-ui/x-ui.log
        echo ""
        echo -e "${cyan}--- 日志结束 ---${plain}"
    else
        LOGE "日志文件不存在"
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# 清空日志
clear_log() {
    confirm "确定要清空日志吗?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    
    if [[ -f ~/x-ui/x-ui.log ]]; then
        cat /dev/null > ~/x-ui/x-ui.log
        LOGI "日志已清空"
    else
        LOGE "日志文件不存在"
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

update_shell() {
    wget -O ~/x-ui.sh -N --no-check-certificate https://raw.githubusercontent.com/hxzlplp7/serv00-xui/main/x-ui.sh
    if [[ $? != 0 ]]; then
        echo ""
        LOGE "下载脚本失败，请检查本机能否连接 Github"
        before_show_menu
    else
        chmod +x ~/x-ui.sh
        LOGI "升级脚本成功，请重新运行脚本" && exit 0
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f ~/x-ui/x-ui ]]; then
        return 2
    fi
    COMMAND_NAME="./x-ui run"
    PID=$(pgrep -f "$COMMAND_NAME")
 
    # 检查是否找到了进程
    if [ ! -z "$PID" ]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    cron_str=$(crontab -l)
 
    # 检查grep的退出状态码
    if echo "$cron_str" | grep -Eqi "$enable_str"; then
        return 0
    else
        return 1
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        LOGE "面板已安装，请不要重复安装"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        LOGE "请先安装面板"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
    0)
        echo -e "面板状态: ${green}已运行${plain}"
        show_enable_status
        ;;
    1)
        echo -e "面板状态: ${yellow}未运行${plain}"
        show_enable_status
        ;;
    2)
        echo -e "面板状态: ${red}未安装${plain}"
        ;;
    esac
    show_xray_status
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "是否开机自启: ${green}是${plain}"
    else
        echo -e "是否开机自启: ${red}否${plain}"
    fi
}

check_xray_status() {
    count=$(ps -aux | grep "xray-${release}" | grep -v "grep" | wc -l)
    if [[ count -ne 0 ]]; then
        return 0
    else
        return 1
    fi
}

show_xray_status() {
    check_xray_status
    if [[ $? == 0 ]]; then
        echo -e "xray 状态: ${green}运行${plain}"
    else
        echo -e "xray 状态: ${red}未运行${plain}"
    fi
}

show_usage() {
    echo "x-ui 管理脚本使用方法: "
    echo "------------------------------------------"
    echo "/home/${USER}/x-ui.sh              - 显示管理菜单 (功能更多)"
    echo "/home/${USER}/x-ui.sh start        - 启动 x-ui 面板"
    echo "/home/${USER}/x-ui.sh stop         - 停止 x-ui 面板"
    echo "/home/${USER}/x-ui.sh restart      - 重启 x-ui 面板"
    echo "/home/${USER}/x-ui.sh status       - 查看 x-ui 状态"
    echo "/home/${USER}/x-ui.sh enable       - 设置 x-ui 开机自启"
    echo "/home/${USER}/x-ui.sh disable      - 取消 x-ui 开机自启"
    echo "/home/${USER}/x-ui.sh update       - 更新 x-ui 面板"
    echo "/home/${USER}/x-ui.sh install      - 安装 x-ui 面板"
    echo "/home/${USER}/x-ui.sh uninstall    - 卸载 x-ui 面板"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${green}x-ui 面板管理脚本${plain} ${yellow}(增强版)${plain}
  ${green}0.${plain} 退出脚本
————————————————
  ${green}1.${plain} 安装 x-ui
  ${green}2.${plain} 更新 x-ui
  ${green}3.${plain} 卸载 x-ui
————————————————
  ${green}4.${plain} 重置用户名密码
  ${green}5.${plain} 重置面板设置
  ${green}6.${plain} 设置面板访问端口
  ${green}7.${plain} 查看当前面板设置
————————————————
  ${green}8.${plain} 启动 x-ui
  ${green}9.${plain} 停止 x-ui
  ${green}10.${plain} 重启 x-ui
  ${green}11.${plain} 查看 x-ui 状态
  ${green}12.${plain} 设置流量监测端口
————————————————
  ${green}13.${plain} 设置 x-ui 开机自启
  ${green}14.${plain} 取消 x-ui 开机自启
————————————————
  ${green}15.${plain} 查看运行日志
  ${green}16.${plain} 清空日志
————————————————
 "
    show_status
    echo && read -p "请输入选择 [0-16]: " num

    case "${num}" in
    0)
        exit 0
        ;;
    1)
        check_uninstall && install
        ;;
    2)
        check_install && update
        ;;
    3)
        check_install && uninstall
        ;;
    4)
        check_install && reset_user
        ;;
    5)
        check_install && reset_config
        ;;
    6)
        check_install && set_port
        ;;
    7)
        check_install && check_config
        ;;
    8)
        check_install && start
        ;;
    9)
        check_install && stop
        ;;
    10)
        check_install && restart
        ;;
    11)
        check_install && status
        ;;
    12)
        check_install && set_traffic_port
        ;;
    13)
        check_install && enable
        ;;
    14)
        check_install && disable
        ;;
    15)
        check_install && show_log
        ;;
    16)
        check_install && clear_log
        ;;
    *)
        LOGE "请输入正确的数字 [0-16]"
        ;;
    esac
}

if [[ $# > 0 ]]; then
    case $1 in
    "start")
        check_install 0 && start 0
        ;;
    "stop")
        check_install 0 && stop 0
        ;;
    "restart")
        check_install 0 && restart 0
        ;;
    "status")
        check_install 0 && status 0
        ;;
    "enable")
        check_install 0 && enable 0
        ;;
    "disable")
        check_install 0 && disable 0
        ;;
    "update")
        check_install 0 && update 0
        ;;
    "install")
        check_uninstall 0 && install 0
        ;;
    "uninstall")
        check_install 0 && uninstall 0
        ;;
    *) show_usage ;;
    esac
else
    show_menu
fi
