#!/bin/bash

# ding 命令安装脚本
# 功能: 安装 ding 命令，用于执行任务后发送钉钉通知

# 检查是否以root运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用sudo运行此脚本"
    exit 1
fi

echo "准备创建ding命令"

# 创建 ding 命令脚本
cat > /usr/local/bin/ding <<'EOF'
#!/bin/bash

# ding命令脚本
# 用法: nohup ding <command> [args...] > output.log &

# 获取命令开始时间
start_time=$(date +%s)

# 执行原始命令
"$@"
exit_code=$?

# 获取命令结束时间和耗时
end_time=$(date +%s)
duration=$((end_time - start_time))

# 读取配置文件
config_file="$HOME/.ding.conf"
if [ -f "$config_file" ]; then
    source "$config_file"
else
    echo "Config file $config_file not found"
    echo "请先创建配置文件 ~/.ding.conf"
    echo "包含 webhook_url 和可选的 secret"
    exit 1
fi

# 获取主机信息
hostname=$(hostname)
# 获取内网IP
internal_ip=$(ip -o -4 addr show | awk '{print $4}' | cut -d'/' -f1 | grep -v '127.0.0.1' | head -n1)
if [ -z "$internal_ip" ]; then
    for interface in eth0 ens33 enp0s3 enp0s8; do
        internal_ip=$(ip -o -4 addr show dev $interface 2>/dev/null | awk '{print $4}' | cut -d'/' -f1)
        [ -n "$internal_ip" ] && break
    done
fi
if [ -z "$internal_ip" ]; then
    internal_ip=$(hostname -I | awk '{print $1}')
fi

# 准备消息内容
current_time=$(date "+%Y-%m-%d %H:%M:%S")
command_line="$*"

if [ $exit_code -eq 0 ]; then
    status="✅ 成功"
else
    status="❌ 失败 (退出码: $exit_code)"
fi

# 格式化耗时
if [ $duration -lt 60 ]; then
    duration_str="${duration}秒"
elif [ $duration -lt 3600 ]; then
    minutes=$((duration / 60))
    seconds=$((duration % 60))
    duration_str="${minutes}分${seconds}秒"
else
    hours=$((duration / 3600))
    minutes=$(( (duration % 3600) / 60 ))
    seconds=$((duration % 60))
    duration_str="${hours}小时${minutes}分${seconds}秒"
fi

# 构建钉钉消息JSON
message=$(cat <<OUTER_EOF
{
    "msgtype": "markdown",
    "markdown": {
        "title": "任务完成通知",
        "text": "### 任务完成通知  \n  \
**主机**: $hostname  \n  \
**内网IP**: $internal_ip  \n  \
**状态**: $status  \n  \
**开始时间**: $current_time  \n  \
**耗时**: $duration_str  \n  \
**执行的命令**: \`$command_line\`  \n  \
**工作目录**: \`$(pwd)\`"
    }
}
OUTER_EOF
)

# 如果有secret，生成签名
if [ -n "$secret" ]; then
    timestamp=$(date +%s%3N)
    sign=$(echo -ne "$timestamp\n$secret" | openssl dgst -sha256 -hmac "$secret" -binary | base64)
    webhook_url="${webhook_url}&timestamp=${timestamp}&sign=${sign}"
fi

# 发送钉钉通知
response=$(curl -s -X POST -H "Content-Type: application/json" -d "$message" "$webhook_url")

exit $exit_code
EOF

echo "ding命令创建成功！"
echo "准备赋予ding命令执行权限"
# 设置权限
chmod +x /usr/local/bin/ding
echo "赋予ding命令执行权限成功！"

echo "准备创建~/.ding.conf文件"
# 创建配置目录和示例配置文件
if [ ! -f "$HOME/.ding.conf" ]; then
    cat > "$HOME/.ding.conf" <<EOF
# 钉钉机器人Webhook地址
webhook_url=""

# 可选: 消息签名密钥
secret=""
EOF
fi
echo "成功创建~/.ding.conf文件！"

echo "安装完成!"
echo "ding 命令已安装到 /usr/local/bin/ding"
echo "请编辑 ~/.ding.conf 配置你的钉钉机器人Webhook"
echo "使用示例: nohup ding tar -cf backup.tar ./ > backup.log &"
EOF
