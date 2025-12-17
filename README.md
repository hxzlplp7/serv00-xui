# serv00-xui

基于 serv00 免费服务器的 x-ui FreeBSD 版本，支持多协议多用户的 Xray 面板，本版本支持 FreeBSD 非 root 安装。

## ✨ 新功能

### 🚀 Xray 任意门中转

支持一键配置任意门 (Dokodemo-door) 端口中转功能：

- **多协议支持**: 自动识别 VLESS、VMess、Trojan、Shadowsocks、Hysteria2、TUIC、Socks、HTTP 等协议节点
- **自定义端口**: 支持随机端口、指定范围随机、手动指定三种方式
- **自动生成链接**: 输入原始节点链接，自动生成中转后的节点链接
- **规则管理**: 支持添加、查看、删除中转规则

### ⚡ x-ui 快捷命令

安装后可直接使用 `x-ui` 命令管理面板，无需输入完整路径！

## 📋 功能介绍

- 系统状态监控
- 支持多用户多协议，网页可视化操作
- 支持的协议：vmess、vless、trojan、shadowsocks、dokodemo-door、socks、http
- 支持配置更多传输配置
- 流量统计，限制流量，限制到期时间
- 可自定义 xray 配置模板
- 支持 https 访问面板（自备域名 + ssl 证书）
- **Xray 任意门中转** (新增)
- **x-ui 快捷命令** (新增)
- 更多高级配置项，详见面板

## 🛠️ 安装 & 升级

在安装前，请先准备好用户名，密码和两个端口（面板访问端口和流量监控端口）！

```bash
wget -O x-ui.sh -N --no-check-certificate https://raw.githubusercontent.com/hxzlplp7/serv00-xui/main/x-ui.sh && chmod +x x-ui.sh && ./x-ui.sh
```

## 📖 使用方法

### 快捷命令（推荐）

安装完成后，可以直接使用 `x-ui` 命令：

```bash
x-ui              # 显示管理菜单
x-ui start        # 启动 x-ui 面板
x-ui stop         # 停止 x-ui 面板
x-ui restart      # 重启 x-ui 面板
x-ui status       # 查看 x-ui 状态
x-ui enable       # 设置 x-ui 开机自启
x-ui disable      # 取消 x-ui 开机自启
x-ui update       # 更新 x-ui 面板
x-ui install      # 安装 x-ui 面板
x-ui uninstall    # 卸载 x-ui 面板
x-ui dokodemo     # 任意门中转菜单
```

> 💡 如果 `x-ui` 命令不可用，请执行 `source ~/.bashrc` 或重新登录终端。

### 完整路径方式

```bash
~/x-ui.sh              # 显示管理菜单
~/x-ui.sh start        # 启动 x-ui 面板
```

### 任意门中转使用

1. 运行 `x-ui` 进入管理菜单
2. 选择 `15. Xray 任意门中转`
3. 选择 `4. 快速中转节点`
4. 粘贴你的节点链接（支持 vless/vmess/trojan/ss/hy2/tuic/socks/http）
5. 选择端口分配方式
6. 脚本会自动解析节点并生成中转配置和新的节点链接
7. 在 x-ui 面板中按照提示添加入站规则

#### 支持的节点格式

| 协议 | 链接格式示例 |
|------|-------------|
| VLESS | `vless://uuid@host:port?params#name` |
| VMess | `vmess://base64...` |
| Trojan | `trojan://password@host:port?params#name` |
| Shadowsocks | `ss://base64@host:port#name` |
| Hysteria2 | `hysteria2://password@host:port?params#name` |
| TUIC | `tuic://uuid:password@host:port?params#name` |
| Socks | `socks://host:port` 或 `socks5://user:pass@host:port` |
| HTTP | `http://host:port` |

## 📦 手动安装 & 升级

1. 从 [Releases](https://github.com/hxzlplp7/serv00-xui/releases) 下载最新压缩包（一般选择 `amd64` 架构）
2. 将压缩包上传到服务器的 `/home/[username]` 目录下

```bash
cd ~
rm -rf ./x-ui
tar zxvf x-ui-freebsd-amd64.tar.gz
chmod +x x-ui/x-ui x-ui/bin/xray-freebsd-* x-ui/x-ui.sh
cp x-ui/x-ui.sh ./x-ui.sh
cd x-ui
crontab -l > x-ui.cron
echo "0 0 * * * cd ~/x-ui && cat /dev/null > x-ui.log" >> x-ui.cron
echo "@reboot cd ~/x-ui && nohup ./x-ui run > ./x-ui.log 2>&1 &" >> x-ui.cron
crontab x-ui.cron
rm x-ui.cron
nohup ./x-ui run > ./x-ui.log 2>&1 &
```

## 🔐 SSL 证书申请

建议使用 Cloudflare 15 年证书

## 💻 建议系统

- FreeBSD 14+

## 🙏 感谢

- [parentalclash/x-ui-freebsd](https://github.com/parentalclash/x-ui-freebsd)
- [vaxilu/x-ui](https://github.com/vaxilu/x-ui)
- [amclubs/am-serv00-x-ui](https://github.com/amclubs/am-serv00-x-ui)

## ⚠️ 免责声明

1. 该项目设计和开发仅供学习、研究和安全测试目的。请于下载后 24 小时内删除，不得用作任何商业用途，文字、数据及图片均有所属版权，如转载须注明来源。
2. 使用本程序必须遵守部署服务器所在地区的法律、所在国家和用户所在国家的法律法规。对任何人或团体使用该项目时产生的任何后果由使用者承担。
3. 作者不对使用该项目可能引起的任何直接或间接损害负责。作者保留随时更新免责声明的权利，且不另行通知。
