#!/bin/bash

# Настройки только для IPv4
SETTINGS=(
    "net.core.default_qdisc=fq"
    "net.ipv4.tcp_congestion_control=bbr"
)

CONFIG_FILE="/etc/sysctl.conf"

# Проверяем root
if [[ $EUID -ne 0 ]]; then
    echo "Требуются root-права. Запустите с sudo!" >&2
    exit 1
fi

# Добавляем настройки если их нет
for setting in "${SETTINGS[@]}"; do
    if ! grep -q "^${setting}" "$CONFIG_FILE"; then
        echo "$setting" | sudo tee -a "$CONFIG_FILE"
        echo "Добавлено: $setting"
    fi
done

# Применяем изменения
echo "Применяем настройки..."
sudo sysctl -p

# Проверяем BBR
echo -e "\nПроверка:"
echo "net.ipv4.tcp_congestion_control = $(sysctl -n net.ipv4.tcp_congestion_control)"
echo "net.core.default_qdisc = $(sysctl -n net.core.default_qdisc)"

# Загружаем модуль если нужно
if ! lsmod | grep -q tcp_bbr; then
    echo "Загружаем модуль tcp_bbr..."
    sudo modprobe tcp_bbr
    echo "tcp_bbr" | sudo tee /etc/modules-load.d/bbr.conf >/dev/null
fi

echo -e "\nГотово! BBR активирован для IPv4."
