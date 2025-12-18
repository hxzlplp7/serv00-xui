#!/bin/sh

set -e

echo "🛠️ 开始构建 x-ui FreeBSD amd64 版本..."

# 检查 Go 是否已安装
if ! command -v go > /dev/null 2>&1; then
  echo "❌ Go 未安装，请先执行：pkg install go"
  exit 1
fi

# 清理旧目录
rm -rf build
mkdir -p build/x-ui

# 构建主程序
echo "⚙️ 编译 Go 程序..."
GOOS=freebsd GOARCH=amd64 go build -o build/x-ui/x-ui -v main.go

# 复制脚本文件
echo "📦 拷贝脚本文件..."
cp x-ui.sh build/x-ui/x-ui.sh

# 下载 Xray 核心及规则文件
echo "🌐 下载 Xray 核心及规则（从官方仓库 github.com/xtls/xray-core）..."
cd build/x-ui
mkdir bin
cd bin

# 从官方仓库下载最新版本
XRAY_REPO="https://github.com/xtls/xray-core"
echo "📥 下载 Xray FreeBSD 64位版本..."
fetch ${XRAY_REPO}/releases/latest/download/Xray-freebsd-64.zip

if [ ! -f "Xray-freebsd-64.zip" ]; then
  echo "❌ Xray 下载失败"
  exit 1
fi

unzip -q Xray-freebsd-64.zip
rm -f Xray-freebsd-64.zip geoip.dat geosite.dat

# 下载最新规则文件
echo "📥 下载规则文件..."
fetch https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
fetch https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat

# 重命名 xray 二进制文件
mv xray xray-freebsd-amd64

# 显示版本信息
echo "ℹ️ Xray 版本信息:"
./xray-freebsd-amd64 version | head -n 1 || echo "  (无法获取版本信息)"

cd ../..

# 打包为 tar.gz
echo "📦 创建归档文件..."
tar -zcvf x-ui-freebsd-amd64.tar.gz x-ui

echo "✅ 构建完成：build/x-ui-freebsd-amd64.tar.gz"
