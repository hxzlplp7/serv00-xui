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
    echo -e "${yellow}[DEG] $* ${plain}"
}

function LOGE() {
    echo -e "${red}[ERR] $* ${plain}"
}

function LOGI() {
    echo -e "${green}[INF] $* ${plain}"
}

cd ~
cur_dir=$(pwd)
uname_output=$(uname -a)
enable_str="nohup \.\\/x-ui run"

# 任意门配置目录
DOKODEMO_DIR="$HOME/x-ui/dokodemo"
DOKODEMO_CONFIG="$DOKODEMO_DIR/config.json"
DOKODEMO_RULES="$DOKODEMO_DIR/rules.json"

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

# ==================== 任意门功能 ====================

# 初始化任意门配置目录
init_dokodemo() {
    mkdir -p "$DOKODEMO_DIR"
    if [[ ! -f "$DOKODEMO_RULES" ]]; then
        echo '{"rules":[]}' > "$DOKODEMO_RULES"
    fi
}

# 获取服务器IP
get_server_ip() {
    local ip=""
    # 尝试获取公网IP
    ip=$(curl -s4 ifconfig.me 2>/dev/null || curl -s4 ip.sb 2>/dev/null || curl -s4 ipinfo.io/ip 2>/dev/null)
    if [[ -z "$ip" ]]; then
        # 获取本地IP
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    echo "$ip"
}

# 生成随机端口
generate_random_port() {
    local min=${1:-10000}
    local max=${2:-60000}
    echo $((RANDOM % (max - min + 1) + min))
}

# 检查端口是否被占用
is_port_used() {
    local port=$1
    if sockstat -l | grep -q ":$port " 2>/dev/null; then
        return 0
    fi
    return 1
}

# 获取可用端口
get_available_port() {
    local min=${1:-10000}
    local max=${2:-60000}
    local port
    local max_tries=100
    local tries=0
    
    while [[ $tries -lt $max_tries ]]; do
        port=$(generate_random_port $min $max)
        if ! is_port_used $port; then
            echo $port
            return 0
        fi
        ((tries++))
    done
    
    echo ""
    return 1
}

# 生成任意门Xray配置
generate_dokodemo_config() {
    local listen_port=$1
    local target_host=$2
    local target_port=$3
    local rule_tag=$4
    
    cat << EOF
{
    "tag": "$rule_tag",
    "listen": "0.0.0.0",
    "port": $listen_port,
    "protocol": "dokodemo-door",
    "settings": {
        "address": "$target_host",
        "port": $target_port,
        "network": "tcp,udp"
    },
    "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
    }
}
EOF
}

# 添加任意门规则到Xray配置
add_dokodemo_rule() {
    local listen_port=$1
    local target_host=$2
    local target_port=$3
    local original_link=$4
    local node_name=$5
    
    init_dokodemo
    
    local rule_tag="dokodemo_${listen_port}"
    local timestamp=$(date +%s)
    
    # 读取现有规则
    local rules_json=$(cat "$DOKODEMO_RULES")
    
    # 创建新规则
    local new_rule=$(cat << EOF
{
    "tag": "$rule_tag",
    "listen_port": $listen_port,
    "target_host": "$target_host",
    "target_port": $target_port,
    "original_link": "$original_link",
    "node_name": "$node_name",
    "created_at": $timestamp
}
EOF
)
    
    # 添加到规则列表
    echo "$rules_json" | sed "s/\"rules\":\[/\"rules\":[$new_rule,/" | sed 's/,\]/]/' > "$DOKODEMO_RULES"
    
    # 生成Xray配置片段
    generate_dokodemo_config "$listen_port" "$target_host" "$target_port" "$rule_tag" > "$DOKODEMO_DIR/${rule_tag}.json"
    
    LOGI "任意门规则已添加: 本地端口 $listen_port -> $target_host:$target_port"
}

# 生成中转后的节点链接
generate_relay_link() {
    local original_link=$1
    local relay_port=$2
    local server_ip=$(get_server_ip)
    
    local parsed=$(parse_node "$original_link")
    if [[ -z "$parsed" ]]; then
        echo ""
        return
    fi
    
    local protocol=$(echo "$parsed" | cut -d'|' -f1)
    local original_host=$(echo "$parsed" | cut -d'|' -f2)
    local original_port=$(echo "$parsed" | cut -d'|' -f3)
    local node_name=$(echo "$parsed" | cut -d'|' -f4)
    
    # 替换host和port为中转服务器
    local new_link=""
    
    case "$protocol" in
        vless)
            local userinfo=$(echo "$parsed" | cut -d'|' -f5)
            local params=$(echo "$parsed" | cut -d'|' -f6)
            new_link="vless://${userinfo}@${server_ip}:${relay_port}"
            if [[ -n "$params" && "$params" != "$userinfo" ]]; then
                new_link="${new_link}?${params}"
            fi
            new_link="${new_link}#[中转]${node_name}"
            ;;
        vmess)
            local decoded=$(echo "$parsed" | cut -d'|' -f5-)
            # 替换地址和端口
            decoded=$(echo "$decoded" | sed "s/\"add\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"add\":\"$server_ip\"/")
            decoded=$(echo "$decoded" | sed "s/\"port\"[[:space:]]*:[[:space:]]*[0-9]*/\"port\":$relay_port/")
            decoded=$(echo "$decoded" | sed "s/\"ps\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"ps\":\"[中转]$node_name\"/")
            new_link="vmess://$(echo -n "$decoded" | base64 | tr -d '\n')"
            ;;
        trojan)
            local password=$(echo "$parsed" | cut -d'|' -f5)
            local params=$(echo "$parsed" | cut -d'|' -f6)
            new_link="trojan://${password}@${server_ip}:${relay_port}"
            if [[ -n "$params" && "$params" != "$password" ]]; then
                new_link="${new_link}?${params}"
            fi
            new_link="${new_link}#[中转]${node_name}"
            ;;
        ss)
            # 对于SS，需要保留原始的加密信息
            local content="${original_link#ss://}"
            local name="${content##*#}"
            content="${content%#*}"
            if [[ "$content" == *"@"* ]]; then
                local encoded="${content%%@*}"
                new_link="ss://${encoded}@${server_ip}:${relay_port}#[中转]${node_name}"
            else
                new_link="$original_link"
            fi
            ;;
        hysteria2)
            local password=$(echo "$parsed" | cut -d'|' -f5)
            local params=$(echo "$parsed" | cut -d'|' -f6)
            new_link="hysteria2://${password}@${server_ip}:${relay_port}"
            if [[ -n "$params" && "$params" != "$password" ]]; then
                new_link="${new_link}?${params}"
            fi
            new_link="${new_link}#[中转]${node_name}"
            ;;
        tuic)
            local userinfo=$(echo "$parsed" | cut -d'|' -f5)
            local params=$(echo "$parsed" | cut -d'|' -f6)
            new_link="tuic://${userinfo}@${server_ip}:${relay_port}"
            if [[ -n "$params" && "$params" != "$userinfo" ]]; then
                new_link="${new_link}?${params}"
            fi
            new_link="${new_link}#[中转]${node_name}"
            ;;
        socks)
            new_link="socks://${server_ip}:${relay_port}#[中转]${node_name}"
            ;;
        http)
            new_link="http://${server_ip}:${relay_port}#[中转]${node_name}"
            ;;
        anytls)
            local password=$(echo "$parsed" | cut -d'|' -f5)
            local params=$(echo "$parsed" | cut -d'|' -f6)
            new_link="anytls://${password}@${server_ip}:${relay_port}"
            if [[ -n "$params" && "$params" != "$password" ]]; then
                new_link="${new_link}?${params}"
            fi
            new_link="${new_link}#[中转]${node_name}"
            ;;
        *)
            new_link=""
            ;;
    esac
    
    echo "$new_link"
}

# 刷新Xray配置（整合所有任意门规则）
refresh_xray_config() {
    local xray_config="$HOME/x-ui/bin/config.json"
    
    if [[ ! -f "$xray_config" ]]; then
        LOGE "Xray配置文件不存在"
        return 1
    fi
    
    # 这里需要根据实际情况将任意门规则添加到Xray配置中
    # 由于x-ui面板会自动管理配置，这里主要用于展示规则
    LOGI "任意门规则已更新，请通过面板配置入站规则"
}

# 显示所有任意门规则
show_dokodemo_rules() {
    init_dokodemo
    
    if [[ ! -f "$DOKODEMO_RULES" ]]; then
        LOGI "暂无任意门规则"
        return
    fi
    
    echo ""
    echo -e "${green}========== 任意门中转规则列表 ==========${plain}"
    echo ""
    
    local rules=$(cat "$DOKODEMO_RULES")
    local count=$(echo "$rules" | grep -o '"tag"' | wc -l)
    
    if [[ $count -eq 0 ]]; then
        LOGI "暂无任意门规则"
        return
    fi
    
    # 简单的规则显示
    local i=1
    while IFS= read -r line; do
        if [[ "$line" == *"listen_port"* ]]; then
            local port=$(echo "$line" | grep -o '"listen_port"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*')
            local host=$(echo "$line" | grep -o '"target_host"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
            local tport=$(echo "$line" | grep -o '"target_port"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*')
            local name=$(echo "$line" | grep -o '"node_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
            
            if [[ -n "$port" ]]; then
                echo -e "${cyan}[$i]${plain} ${green}$name${plain}"
                echo -e "    本地端口: ${yellow}$port${plain} -> 目标: ${yellow}$host:$tport${plain}"
                echo ""
                ((i++))
            fi
        fi
    done < "$DOKODEMO_RULES"
    
    echo -e "${green}========================================${plain}"
}

# 删除任意门规则
delete_dokodemo_rule() {
    show_dokodemo_rules
    
    echo && read -p "请输入要删除的规则端口号: " del_port
    
    if [[ -z "$del_port" ]]; then
        LOGD "已取消"
        return
    fi
    
    local rule_file="$DOKODEMO_DIR/dokodemo_${del_port}.json"
    if [[ -f "$rule_file" ]]; then
        rm -f "$rule_file"
        LOGI "规则文件已删除"
    fi
    
    # 从规则列表中移除
    if [[ -f "$DOKODEMO_RULES" ]]; then
        # 简单处理：重建规则文件
        local temp_file=$(mktemp)
        grep -v "\"listen_port\": $del_port" "$DOKODEMO_RULES" > "$temp_file" 2>/dev/null
        mv "$temp_file" "$DOKODEMO_RULES"
        LOGI "端口 $del_port 的任意门规则已删除"
    fi
}

# 任意门中转主菜单
dokodemo_menu() {
    echo -e "
  ${green}Xray 任意门中转管理${plain}
  ${green}0.${plain} 返回主菜单
————————————————
  ${green}1.${plain} 添加中转规则
  ${green}2.${plain} 查看所有规则
  ${green}3.${plain} 删除中转规则
  ${green}4.${plain} 快速中转节点
————————————————
"
    echo && read -p "请输入选择 [0-4]: " dokodemo_num
    
    case "${dokodemo_num}" in
    0)
        show_menu
        ;;
    1)
        add_dokodemo_manual
        ;;
    2)
        show_dokodemo_rules
        before_show_menu
        ;;
    3)
        delete_dokodemo_rule
        before_show_menu
        ;;
    4)
        quick_relay_node
        ;;
    *)
        LOGE "请输入正确的数字 [0-4]"
        dokodemo_menu
        ;;
    esac
}

# 手动添加任意门规则
add_dokodemo_manual() {
    echo ""
    echo -e "${yellow}添加任意门中转规则${plain}"
    echo ""
    
    # 输入目标地址
    read -p "请输入目标服务器地址: " target_host
    if [[ -z "$target_host" ]]; then
        LOGE "目标地址不能为空"
        before_show_menu
        return
    fi
    
    # 输入目标端口
    read -p "请输入目标端口: " target_port
    if [[ -z "$target_port" ]]; then
        LOGE "目标端口不能为空"
        before_show_menu
        return
    fi
    
    # 选择本地端口
    echo ""
    echo -e "请选择本地监听端口方式:"
    echo -e "  ${green}1.${plain} 随机生成端口"
    echo -e "  ${green}2.${plain} 指定端口范围随机"
    echo -e "  ${green}3.${plain} 手动指定端口"
    echo ""
    read -p "请选择 [1-3]: " port_choice
    
    local listen_port=""
    
    case "${port_choice}" in
    1)
        listen_port=$(get_available_port 10000 60000)
        if [[ -z "$listen_port" ]]; then
            LOGE "无法找到可用端口"
            before_show_menu
            return
        fi
        LOGI "随机分配端口: $listen_port"
        ;;
    2)
        read -p "请输入端口范围最小值 [默认10000]: " min_port
        read -p "请输入端口范围最大值 [默认60000]: " max_port
        min_port=${min_port:-10000}
        max_port=${max_port:-60000}
        listen_port=$(get_available_port $min_port $max_port)
        if [[ -z "$listen_port" ]]; then
            LOGE "在指定范围内无法找到可用端口"
            before_show_menu
            return
        fi
        LOGI "在范围 $min_port-$max_port 内随机分配端口: $listen_port"
        ;;
    3)
        read -p "请输入本地监听端口: " listen_port
        if [[ -z "$listen_port" ]]; then
            LOGE "端口不能为空"
            before_show_menu
            return
        fi
        if is_port_used $listen_port; then
            LOGE "端口 $listen_port 已被占用"
            before_show_menu
            return
        fi
        ;;
    *)
        listen_port=$(get_available_port 10000 60000)
        ;;
    esac
    
    # 输入节点名称
    read -p "请输入规则名称 [可选]: " rule_name
    rule_name=${rule_name:-"中转规则_$listen_port"}
    
    # 添加规则
    add_dokodemo_rule "$listen_port" "$target_host" "$target_port" "" "$rule_name"
    
    echo ""
    echo -e "${green}========== 任意门规则添加成功 ==========${plain}"
    echo -e "本地监听端口: ${yellow}$listen_port${plain}"
    echo -e "目标地址: ${yellow}$target_host:$target_port${plain}"
    echo -e "${green}========================================${plain}"
    echo ""
    echo -e "${yellow}请在x-ui面板中添加对应的入站规则:${plain}"
    echo -e "协议: ${cyan}dokodemo-door${plain}"
    echo -e "端口: ${cyan}$listen_port${plain}"
    echo -e "目标地址: ${cyan}$target_host${plain}"
    echo -e "目标端口: ${cyan}$target_port${plain}"
    echo ""
    
    before_show_menu
}

# 快速中转节点
quick_relay_node() {
    echo ""
    echo -e "${green}========== 快速节点中转 ==========${plain}"
    echo -e "${yellow}支持的协议: vless, vmess, trojan, ss, hysteria2, tuic, anytls, socks, http${plain}"
    echo ""
    
    read -p "请粘贴节点链接: " node_link
    
    if [[ -z "$node_link" ]]; then
        LOGE "节点链接不能为空"
        before_show_menu
        return
    fi
    
    # 解析节点
    local parsed=$(parse_node "$node_link")
    
    if [[ -z "$parsed" ]]; then
        LOGE "无法识别的节点格式"
        before_show_menu
        return
    fi
    
    local protocol=$(echo "$parsed" | cut -d'|' -f1)
    local target_host=$(echo "$parsed" | cut -d'|' -f2)
    local target_port=$(echo "$parsed" | cut -d'|' -f3)
    local node_name=$(echo "$parsed" | cut -d'|' -f4)
    
    echo ""
    echo -e "${green}节点解析成功:${plain}"
    echo -e "  协议: ${cyan}$protocol${plain}"
    echo -e "  地址: ${cyan}$target_host${plain}"
    echo -e "  端口: ${cyan}$target_port${plain}"
    echo -e "  名称: ${cyan}$node_name${plain}"
    echo ""
    
    # 选择本地端口
    echo -e "请选择本地监听端口方式:"
    echo -e "  ${green}1.${plain} 随机生成端口"
    echo -e "  ${green}2.${plain} 指定端口范围随机"
    echo -e "  ${green}3.${plain} 手动指定端口"
    echo ""
    read -p "请选择 [1-3, 默认1]: " port_choice
    port_choice=${port_choice:-1}
    
    local listen_port=""
    
    case "${port_choice}" in
    1)
        listen_port=$(get_available_port 10000 60000)
        ;;
    2)
        read -p "请输入端口范围最小值 [默认10000]: " min_port
        read -p "请输入端口范围最大值 [默认60000]: " max_port
        min_port=${min_port:-10000}
        max_port=${max_port:-60000}
        listen_port=$(get_available_port $min_port $max_port)
        ;;
    3)
        read -p "请输入本地监听端口: " listen_port
        if is_port_used $listen_port; then
            LOGE "端口 $listen_port 已被占用"
            before_show_menu
            return
        fi
        ;;
    *)
        listen_port=$(get_available_port 10000 60000)
        ;;
    esac
    
    if [[ -z "$listen_port" ]]; then
        LOGE "无法找到可用端口"
        before_show_menu
        return
    fi
    
    # 添加规则
    add_dokodemo_rule "$listen_port" "$target_host" "$target_port" "$node_link" "$node_name"
    
    # 生成中转后的链接
    local relay_link=$(generate_relay_link "$node_link" "$listen_port")
    local server_ip=$(get_server_ip)
    
    echo ""
    echo -e "${green}╔══════════════════════════════════════════════════════════╗${plain}"
    echo -e "${green}║           任意门中转配置完成                              ║${plain}"
    echo -e "${green}╚══════════════════════════════════════════════════════════╝${plain}"
    echo ""
    echo -e "${yellow}原始节点:${plain}"
    echo -e "  ${cyan}$node_link${plain}"
    echo ""
    echo -e "${yellow}中转信息:${plain}"
    echo -e "  服务器IP: ${cyan}$server_ip${plain}"
    echo -e "  监听端口: ${cyan}$listen_port${plain}"
    echo -e "  目标地址: ${cyan}$target_host:$target_port${plain}"
    echo ""
    
    if [[ -n "$relay_link" ]]; then
        echo -e "${green}中转后的节点链接:${plain}"
        echo -e "${cyan}$relay_link${plain}"
        echo ""
    fi
    
    echo -e "${yellow}请在x-ui面板中添加以下入站规则:${plain}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  协议: ${green}dokodemo-door${plain}"
    echo -e "  监听IP: ${green}0.0.0.0${plain} (或留空)"
    echo -e "  端口: ${green}$listen_port${plain}"
    echo -e "  目标地址: ${green}$target_host${plain}"
    echo -e "  目标端口: ${green}$target_port${plain}"
    echo -e "  网络: ${green}tcp,udp${plain}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    before_show_menu
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
    stop_x-ui
    crontab -l > x-ui.cron
    sed -i "" "/x-ui.log/d" x-ui.cron
    crontab x-ui.cron
    rm x-ui.cron
    cd ~
    rm -rf ~/x-ui/

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
  ${green}16.${plain} 查看运行日志
  ${green}17.${plain} 清空日志
————————————————
  ${cyan}15.${plain} ${cyan}Xray 任意门中转${plain} ${yellow}[新功能]${plain}
————————————————
 "
    show_status
    echo && read -p "请输入选择 [0-17]: " num

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
        dokodemo_menu
        ;;
    16)
        check_install && show_log
        ;;
    17)
        check_install && clear_log
        ;;
    *)
        LOGE "请输入正确的数字 [0-17]"
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
    "dokodemo")
        dokodemo_menu
        ;;
    *) show_usage ;;
    esac
else
    show_menu
fi
