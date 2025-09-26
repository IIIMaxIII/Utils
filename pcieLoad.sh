#!/bin/bash

GPU_NUMBER=0

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Количество измерений
count=100

echo -e "${CYAN}=== Мониторинг PCIe для GPU $GPU_NUMBER ===${NC}"
echo

# Получаем информацию о PCIe
pcie_info=$(nvidia-smi -i $GPU_NUMBER --query-gpu=pcie.link.gen.current,pcie.lin
pcie_gen=$(echo $pcie_info | cut -d',' -f1 | tr -d ' ')
pcie_width=$(echo $pcie_info | cut -d',' -f2 | tr -d ' ')

# Максимальная пропускная способность
case "$pcie_gen" in
    "1") max_speed_per_lane=250;;
    "2") max_speed_per_lane=500;;..
    "3") max_speed_per_lane=985;;
    "4") max_speed_per_lane=1969;;
    "5") max_speed_per_lane=3938;;
    *) max_speed_per_lane=985;;
esac

max_speed=$((max_speed_per_lane * pcie_width))
threshold=$((max_speed * 90 / 100))

echo -e "Текущий режим PCIe: ${YELLOW}Gen$pcie_gen x$pcie_width${NC}"
echo -e "Максимальная пропускная способность: ${YELLOW}$max_speed MB/s${NC}"
echo

echo -e "${CYAN}Замер пропускной способности PCIe ($count измерений)...${NC}"
echo

# Переменные для статистики
total_rx=0
total_tx=0
high_load_rx=0
high_load_tx=0

echo -e "${BLUE}Измерения:${NC}"
echo -e "${BLUE}№    Прием (MB/s)   Передача (MB/s)${NC}"

for ((i=1; i<=$count; i++)); do
    result=$(nvidia-smi dmon -s t -c 1 -i $GPU_NUMBER 2>/dev/null | awk '/^[[:sp

    if [ -n "$result" ]; then
        rx=$(echo $result | awk '{print $1}')
        tx=$(echo $result | awk '{print $2}')

        if [[ "$rx" =~ ^[0-9]+$ ]] && [[ "$tx" =~ ^[0-9]+$ ]]; then
            total_rx=$((total_rx + rx))
            total_tx=$((total_tx + tx))

            # Определяем цвет для значений
            if [ $rx -ge $threshold ]; then
                rx_color=$RED
                high_load_rx=$((high_load_rx + 1))
            elif [ $rx -ge $((threshold * 70 / 100)) ]; then
                rx_color=$YELLOW
            else
                rx_color=$GREEN
            fi

            if [ $tx -ge $threshold ]; then
                tx_color=$RED
                high_load_tx=$((high_load_tx + 1))
            elif [ $tx -ge $((threshold * 70 / 100)) ]; then
                tx_color=$YELLOW
            else
                tx_color=$GREEN
            fi

            printf "${NC}%-3d  ${rx_color}%-12d${NC}  ${tx_color}%-12d${NC}\n" "
        else
            printf "${NC}%-3d  %-12s  %-12s\n" "$i" "error" "error"
        fi
    else
        printf "${NC}%-3d  %-12s  %-12s\n" "$i" "no_data" "no_data"
    fi
done

# Вычисляем статистику
avg_rx=$((total_rx / count))
avg_tx=$((total_tx / count))
avg_rx_percent=$((avg_rx * 100 / max_speed))
avg_tx_percent=$((avg_tx * 100 / max_speed))
high_rx_percent=$((high_load_rx * 100 / count))
high_tx_percent=$((high_load_tx * 100 / count))

# Определяем цвет для средних значений
if [ $avg_rx_percent -ge 90 ]; then
    avg_rx_color=$RED
elif [ $avg_rx_percent -ge 70 ]; then
    avg_rx_color=$YELLOW
else
    avg_rx_color=$GREEN
fi

if [ $avg_tx_percent -ge 90 ]; then
    avg_tx_color=$RED
elif [ $avg_tx_percent -ge 70 ]; then
    avg_tx_color=$YELLOW
else
    avg_tx_color=$GREEN
fi

echo
echo -e "${CYAN}=== РЕЗУЛЬТАТЫ ===${NC}"
echo -e "Количество измерений: ${YELLOW}$count${NC}"
echo -e "Средняя пропускная способность:"
echo -e "  Прием:  ${avg_rx_color}$avg_rx MB/s${NC} (${avg_rx_color}$avg_rx_perc
echo -e "  Передача: ${avg_tx_color}$avg_tx MB/s${NC} (${avg_tx_color}$avg_tx_pe
echo
echo -e "Замеры с высокой нагрузкой (≥90% от макс.):"
echo -e "  Прием:  ${RED}$high_load_rx${NC} из $count (${RED}$high_rx_percent%${
echo -e "  Передача: ${RED}$high_load_tx${NC} из $count (${RED}$high_tx_percent%

# Цветовая легенда
echo
echo -e "${GREEN}Зеленый${NC} - нормальная нагрузка"
echo -e "${YELLOW}Желтый${NC} - средняя нагрузка (≥70%)"
echo -e "${RED}Красный${NC} - высокая нагрузка (≥90%)"
