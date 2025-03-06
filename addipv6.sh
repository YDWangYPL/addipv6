#!/bin/bash

echo "====================================="
echo "欢迎使用 ADD IPv6 管理工具"
echo "作者: Joey"
echo "博客: joeyblog.net"
echo "TG群: https://t.me/+ft-zI76oovgwNmRh"
echo "提醒: 合理使用"
echo "====================================="

if [ "$(id -u)" -ne 0 ]; then
    echo "请以root权限执行此脚本。"
    exit 1
fi

function choose_interface() {
    GLOBAL_IPV6_INTERFACES=()
    for iface in $(ip -o link show | awk -F': ' '{print $2}'); do
        if ip -6 addr show dev "$iface" scope global | grep -q 'inet6'; then
            GLOBAL_IPV6_INTERFACES+=("$iface")
        fi
    done
    if [ ${#GLOBAL_IPV6_INTERFACES[@]} -eq 0 ]; then
        echo "未检测到具有全局 IPv6 地址的网卡，请检查 VPS 的网络配置。"
        exit 1
    fi
    if [ ${#GLOBAL_IPV6_INTERFACES[@]} -eq 1 ]; then
        SELECTED_IFACE="${GLOBAL_IPV6_INTERFACES[0]}"
    else
        echo "检测到以下具有全局 IPv6 地址的网卡："
        for i in "${!GLOBAL_IPV6_INTERFACES[@]}"; do
            echo "$((i+1)). ${GLOBAL_IPV6_INTERFACES[$i]}"
        done
        read -p "请选择要使用的网卡编号: " choice
        if ! [[ "$choice" =~ ^[1-9][0-9]*$ ]] || [ "$choice" -gt "${#GLOBAL_IPV6_INTERFACES[@]}" ]; then
            echo "选择无效。"
            exit 1
        fi
        SELECTED_IFACE="${GLOBAL_IPV6_INTERFACES[$((choice-1))]}"
    fi
    echo "选择的网卡为：$SELECTED_IFACE"
}

function manage_default_ipv6() {
    choose_interface
    echo "检测到以下IPv6地址（全局范围）："
    mapfile -t ipv6_list < <(ip -6 addr show dev "$SELECTED_IFACE" scope global | awk '/inet6/ {print $2}')
    if [ ${#ipv6_list[@]} -eq 0 ]; then
        echo "网卡 $SELECTED_IFACE 上未检测到全局IPv6地址。"
        exit 1
    fi
    for i in "${!ipv6_list[@]}"; do
        echo "$((i+1)). ${ipv6_list[$i]}"
    done
    read -p "请输入要设置为出口的IPv6地址对应的序号: " addr_choice
    if ! [[ "$addr_choice" =~ ^[0-9]+$ ]] || [ "$addr_choice" -gt "${#ipv6_list[@]}" ] || [ "$addr_choice" -lt 1 ]; then
        echo "选择无效。"
        exit 1
    fi
    SELECTED_ENTRY="${ipv6_list[$((addr_choice-1))]}"
    SELECTED_IP=$(echo "$SELECTED_ENTRY" | cut -d'/' -f1)
    echo "选择的默认出口IPv6地址为：$SELECTED_IP"
    
    GATEWAY=$(ip -6 route show default dev "$SELECTED_IFACE" | awk '/default/ {print $3}' | head -n1)
    if [ -z "$GATEWAY" ]; then
        GATEWAY=$(ip -6 route show dev "$SELECTED_IFACE" | awk '/via/ {print $3}' | head -n1)
    fi
    
    if [ -z "$GATEWAY" ]; then
        echo "未检测到默认IPv6网关，请检查系统路由配置。"
        exit 1
    fi
    echo "检测到默认IPv6网关为：$GATEWAY"
    
    ip -6 route add default via "$GATEWAY" dev "$SELECTED_IFACE" src "$SELECTED_IP" onlink || \
    ip -6 route change default via "$GATEWAY" dev "$SELECTED_IFACE" src "$SELECTED_IP" onlink
    
    if [ $? -eq 0 ]; then
        echo "默认出口IPv6地址更新成功，出站流量将使用 $SELECTED_IP 作为源地址。"
    else
        echo "更新默认出口IPv6地址失败，请检查系统路由配置。"
    fi
    
    read -p "是否将此配置写入 /etc/rc.local 以避免重启后失效？(y/n): " persist_choice
    if [[ "$persist_choice" =~ ^[Yy]$ ]]; then
        if [ ! -f /etc/rc.local ]; then
            echo "#!/bin/bash" > /etc/rc.local
            chmod +x /etc/rc.local
        fi
        grep -qxF "ip -6 route add default via \"$GATEWAY\" dev \"$SELECTED_IFACE\" src \"$SELECTED_IP\" onlink" /etc/rc.local || \
        echo "ip -6 route add default via \"$GATEWAY\" dev \"$SELECTED_IFACE\" src \"$SELECTED_IP\" onlink" >> /etc/rc.local
        echo "配置已写入 /etc/rc.local 。"
    fi
}

echo "请选择功能："
echo "1. 添加随机 IPv6 地址"
echo "2. 管理默认出口 IPv6 地址"
echo "3. 一键删除全部添加的IPv6地址"
echo "4. 只保留当前出口默认的IPv6地址 (删除其它全部)"
read -p "请输入选择 (1, 2, 3 或 4): " choice_option

case "$choice_option" in
    1)
        add_random_ipv6
        ;;
    2)
        manage_default_ipv6
        ;;
    3)
        delete_all_ipv6
        ;;
    4)
        delete_except_default_ipv6
        ;;
    *)
        echo "无效的选择。"
        exit 1
        ;;
esac
