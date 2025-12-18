# serv00-xui

基于 serv00 免费服务器的 x-ui FreeBSD 版本，支持多协议多用户的 Xray 面板，本版本支持 FreeBSD 非 root 安装。

## ✨ 新功能

### 🎯 Serv00/HostUno 智能支持

- **自动检测系统类型**: 智能识别 Serv00 或 HostUno 环境
- **Devil 端口管理**: 自动使用 `devil` 命令添加和管理端口
- **端口类型识别**: 自动识别 TCP/UDP 协议类型并添加相应端口
- **智能端口分配**: 支持手动指定或系统随机生成端口
- **端口添加重试**: 自动重试机制，确保端口成功添加
- **端口数量控制**: Serv00 限制 3 个端口，HostUno 无限制



### ⚡ x-ui 快捷命令

安装后可直接使用 `x-ui` 命令管理面板，无需输入完整路径！

## 📋 功能介绍

- 系统状态监控
- 支持多用户多协议，网页可视化操作
- 支持的协议：vmess、vless、trojan、shadowsocks、socks、http
- 支持配置更多传输配置
- 流量统计，限制流量，限制到期时间
- 可自定义 xray 配置模板
- 支持 https 访问面板（自备域名 + ssl 证书）
- **Serv00/HostUno 智能支持** (新增) ✨
- **x-ui 快捷命令** (新增) ✨
- 更多高级配置项，详见面板

## 🛠️ 安装 & 升级

### 标准安装 (Serv00/HostUno 非 Root 环境)

在安装前，请先准备好用户名，密码和两个端口（面板访问端口和流量监控端口）！

```bash
wget -O x-ui.sh -N --no-check-certificate https://raw.githubusercontent.com/hxzlplp7/serv00-xui/main/x-ui.sh && chmod +x x-ui.sh && ./x-ui.sh
```

### MrChrootBSD Root 版本安装 🆕

通过 MrChrootBSD 获取伪 root 权限后，可以在 chroot 环境中以 root 身份安装和运行 X-UI：

```bash
# 方式一：使用一键安装脚本（推荐）
curl -sL https://raw.githubusercontent.com/hxzlplp7/GostXray/main/setup-mrchroot.sh -o setup.sh
chmod +x setup.sh && ./setup.sh

# 安装完成后使用快捷命令
source ~/.profile
xui-root install  # 在 chroot root 环境中安装 X-UI
xui-root          # 运行 X-UI 管理菜单
```

```bash
# 方式二：手动安装
# 1. 先安装 MrChrootBSD 并配置 chroot 环境
# 2. 下载 Root 版本安装脚本到 chroot 环境
curl -sL https://raw.githubusercontent.com/hxzlplp7/serv00-xui/main/x-ui-install-root.sh -o ~/chroot/root/x-ui-install.sh

# 3. 进入 chroot 并安装
./mrchroot ~/chroot /root/x-ui-install.sh
```

> 🔥 **MrChrootBSD Root 版本特点:**
> - 在 chroot 环境中以 **root 权限**运行
> - **无需 devil 端口管理**，可直接绑定任意端口
> - 支持安装到系统目录
> - 可使用 pkg 安装额外依赖
> - **适合需要更完整 Linux 环境的用户**

## 📖 使用方法

### 📋 菜单管理界面

运行 `x-ui` 或 `~/x-ui.sh` 后会显示：

```
  x-ui 面板管理脚本 (增强版)
  0. 退出脚本
————————————————
  1. 安装 x-ui
  2. 更新 x-ui
  3. 卸载 x-ui
————————————————
  4. 重置用户名密码
  5. 重置面板设置
  6. 设置面板访问端口
  7. 查看当前面板设置
————————————————
  8. 启动 x-ui
  9. 停止 x-ui
  10. 重启 x-ui
  11. 查看 x-ui 状态
  12. 设置流量监测端口
————————————————
  13. 设置 x-ui 开机自启
  14. 取消 x-ui 开机自启
————————————————
  15. 查看运行日志
  16. 清空日志
————————————————
 
面板状态: 已运行
是否开机自启: 是
xray 状态: 运行

请输入选择 [0-16]:
```

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
```

> 💡 如果 `x-ui` 命令不可用，请执行 `source ~/.bashrc` 或重新登录终端。

### 完整路径方式

```bash
~/x-ui.sh              # 显示管理菜单
~/x-ui.sh start        # 启动 x-ui 面板
```

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
