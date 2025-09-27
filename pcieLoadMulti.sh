#!/bin/bash

# Цвета для вывода
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Количество измерений
count=100  # Уменьшим для теста

# Получаем список всех доступных GPU
gpu_list=$(nvidia-smi --query-gpu=index --format=csv,noheader,nounits 2>/dev/null)

if [ -z "$gpu_list" ]; then
    echo -e "${RED}Ошибка: Не удалось получить список GPU${NC}"
    exit 1
fi

echo
echo -e "${CYAN}Обнаружено GPU: $(echo "$gpu_list" | wc -l)${NC}"
echo

# Функция для мониторинга одной карты
monitor_gpu() {
    local gpu_number=$1
    local count=$2

    echo -e "${CYAN}Мониторинг PCIe для GPU $gpu_number${NC}"

    # Получаем информацию о PCIe
    pcie_info=$(nvidia-smi -i $gpu_number --query-gpu=pcie.link.gen.current,pcie.link.width.current --format=csv,noheader,nounits 2>/dev/null)

    if [ -z "$pcie_info" ]; then
        echo -e "${RED}Ошибка: Не удалось получить информацию о GPU $gpu_number${NC}"
        echo
        return 1
    fi

    pcie_gen=$(echo $pcie_info | cut -d',' -f1 | tr -d ' ')
    pcie_width=$(echo $pcie_info | cut -d',' -f2 | tr -d ' ')

    # Максимальная пропускная способность
    case "$pcie_gen" in
        "1") max_speed_per_lane=250;;
        "2") max_speed_per_lane=500;;
        "3") max_speed_per_lane=985;;
        "4") max_speed_per_lane=1969;;
        "5") max_speed_per_lane=3938;;
        *) max_speed_per_lane=985;;
    esac

    max_speed=$((max_speed_per_lane * pcie_width))
    threshold=$((max_speed * 90 / 100))

    echo -e "Текущий режим PCIe: ${GREEN}Gen $pcie_gen, x$pcie_width${NC}"
    echo -e "Максимальная пропускная способность: ${GREEN}$max_speed MB/s${NC}"

    # Переменные для статистики
    local total_rx=0
    local total_tx=0
    local high_load_rx=0
    local high_load_tx=0

    for ((i=1; i<=$count; i++)); do
        result=$(nvidia-smi dmon -s t -c 1 -i $gpu_number 2>/dev/null | awk '/^[[:space:]]*[0-9]/{print $2,$3; exit}')

        if [ -n "$result" ]; then
            rx=$(echo $result | awk '{print $1}')
            tx=$(echo $result | awk '{print $2}')

            if [[ "$rx" =~ ^[0-9]+$ ]] && [[ "$tx" =~ ^[0-9]+$ ]]; then
                total_rx=$((total_rx + rx))
                total_tx=$((total_tx + tx))

                # Проверяем близость к максимальной пропускной способности
                if [ $rx -ge $threshold ]; then
                    high_load_rx=$((high_load_rx + 1))
                fi

                if [ $tx -ge $threshold ]; then
                    high_load_tx=$((high_load_tx + 1))
                fi

                # Прогресс-бар
                if (( i % 10 == 0 )); then
                    echo -ne "Замер: $i/$count...\r"
                fi
            fi
        fi
    done

    echo -e "Замер: $count/$100% завершено"
    # Вычисляем статистику
    local avg_rx=$((total_rx / count))
    local avg_tx=$((total_tx / count))
    local avg_rx_percent=$((avg_rx * 100 / max_speed))
    local avg_tx_percent=$((avg_tx * 100 / max_speed))
    local high_rx_percent=$((high_load_rx * 100 / count))
    local high_tx_percent=$((high_load_tx * 100 / count))

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

    echo -e "${WHITE}Средняя пропускная способность:${NC}"
    echo -e "  Прием:  ${avg_rx_color}$avg_rx MB/s${NC} (${avg_rx_color}$avg_rx_percent%${NC})"
    echo -e "  Передача: ${avg_tx_color}$avg_tx MB/s${NC} (${avg_tx_color}$avg_tx_percent%${NC})"
    echo -e "${WHITE}Замеры с высокой нагрузкой:${NC}"
    echo -e "  Прием:  ${RED}$high_load_rx${NC} из $count (${RED}$high_rx_percent%${NC})"
    echo -e "  Передача: ${RED}$high_load_tx${NC} из $count (${RED}$high_tx_percent%${NC})"
    echo
}

# Мониторим все доступные GPU
for gpu in $gpu_list; do
    monitor_gpu $gpu $count
    # Пауза между картами
    sleep 2
done

# Цветовая легенда
echo -e "${GREEN}Зеленый${NC} - нормальная нагрузка"
echo -e "${YELLOW}Желтый${NC} - средняя нагрузка (≥70%)"
echo -e "${RED}Красный${NC} - высокая нагрузка (≥90%)"
