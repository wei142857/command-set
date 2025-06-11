#!/bin/bash

# pidmon 安装脚本
# 功能: 安装进程监控命令，当指定进程结束时发送钉钉通知

echo "正在校验当前权限"
    
# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用sudo运行此脚本: sudo bash $0"
    exit 1
fi
echo "当前权限足够！"

echo "准备创建pidmon命令"

# 创建pidmon脚本
cat > /usr/local/bin/pidmon <<'EOF'
#!/bin/bash

# 静默后台运行逻辑
if [[ $- == *i* ]] && [[ -z "$NO_AUTO_BG" ]]; then
    NO_AUTO_BG=1 nohup "$0" "$@" >/dev/null 2>&1 &
    exit 0
fi

# 参数检查
if [ $# -lt 1 ]; then
    echo "用法: pidmon <PID> [进程描述]" >&2
    exit 1
fi

PID=$1
DESCRIPTION=${2:-"PID $PID 进程"}

# 读取配置文件
CONFIG_FILE="$HOME/.ding.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 配置文件 $CONFIG_FILE 不存在" >&2
    echo "请先创建配置文件，包含钉钉机器人webhook_url和可选的secret" >&2
    exit 1
fi
source "$CONFIG_FILE"

# 获取进程信息
if ! PROCESS_INFO=$(ps -p $PID -o cmd= 2>/dev/null); then
    [ -n "$webhook_url" ] && curl -sSX POST -H "Content-Type: application/json" -d \
    '{"msgtype":"text","text":{"content":"错误: 进程 '$PID' 不存在或无法访问"}}' "$webhook_url"
    exit 1
fi

START_TIME=$(ps -p $PID -o lstart=)
HOSTNAME=$(hostname)
INTERNAL_IP=$(hostname -I | awk '{print $1}')
MONITOR_START=$(date +%s)

# 监控进程
while kill -0 $PID 2>/dev/null; do
    sleep 10
done

# 计算总耗时
MONITOR_END=$(date +%s)
DURATION=$((MONITOR_END - MONITOR_START))

# 格式化耗时
if [ $DURATION -lt 60 ]; then
    DURATION_STR="${DURATION}秒"
elif [ $DURATION -lt 3600 ]; then
    minutes=$((DURATION / 60))
    seconds=$((DURATION % 60))
    DURATION_STR="${minutes}分${seconds}秒"
else
    hours=$((DURATION / 3600))
    minutes=$(( (DURATION % 3600) / 60 ))
    seconds=$((DURATION % 60))
    DURATION_STR="${hours}小时${minutes}分${seconds}秒"
fi

# 构建钉钉消息
MESSAGE=$(cat <<OUTER_EOF
{
    "msgtype": "markdown",
    "markdown": {
        "title": "进程结束通知",
        "text": "### 进程结束通知  \n  \
**主机**: $HOSTNAME  \n  \
**内网IP**: $INTERNAL_IP  \n  \
**进程描述**: $DESCRIPTION  \n  \
**进程命令**: \`$PROCESS_INFO\`  \n  \
**进程启动时间**: $START_TIME  \n  \
**监控持续时间**: $DURATION_STR  \n  \
**结束时间**: $(date "+%Y-%m-%d %H:%M:%S")"
    }
}
OUTER_EOF

# 如果有secret，生成签名
if [ -n "$secret" ]; then
    timestamp=$(date +%s%3N)
    sign=$(echo -ne "$timestamp\n$secret" | openssl dgst -sha256 -hmac "$secret" -binary | base64)
    webhook_url="${webhook_url}&timestamp=${timestamp}&sign=${sign}"
fi

# 发送钉钉通知
curl -s -X POST -H "Content-Type: application/json" -d "$MESSAGE" "$webhook_url"
EOF

echo "成功创建pidmon命令！"

echo "准备赋予pidmon命令执行权限"
# 设置权限
chmod +x /usr/local/bin/pidmon
echo "成功赋予pidmon命令执行权限！"

echo "准备创建~/.ding.conf"
# 创建示例配置文件（如果不存在）
if [ ! -f "$HOME/.ding.conf" ]; then
    cat > "$HOME/.ding.conf" <<EOF
# 钉钉机器人Webhook地址
webhook_url="https://oapi.dingtalk.com/robot/send?access_token=YOUR_ACCESS_TOKEN"

# 可选: 消息签名密钥
# secret="YOUR_SECRET"
EOF
    echo "已创建示例配置文件: $HOME/.ding.conf"
    echo "请编辑该文件配置你的钉钉机器人Webhook"
fi
echo "成功创建~/.ding.conf！"

echo "安装完成!"
echo "pidmon 命令已安装到 /usr/local/bin/pidmon"
echo "使用示例: pidmon 12345 \"重要数据处理进程\""
