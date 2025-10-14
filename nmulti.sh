#!/bin/bash

accountname="megamax.${HOSTNAME}"
GPU_COUNT=1
THREADS=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --gpu)
      GPU_COUNT="$2"
      shift 2
      ;;
    --threads)
      THREADS="$2"
      shift 2
      ;;
    *)
      echo "Неизвестный параметр: $1"
      exit 1
      ;;
  esac
done

WORKDIR="$(cd "$(dirname "$0")" && pwd)"
cd "$WORKDIR"

TOTAL_CORES=$(nproc)

for i in $(seq 0 $((GPU_COUNT-1))); do
    screen -S "neptune-gpu$i" -X quit >/dev/null 2>&1
done
sleep 2

for i in $(seq 0 $((GPU_COUNT-1))); do
    touch "$WORKDIR/neptune-gpu$i.log"
done

for i in $(seq 0 $((GPU_COUNT-1))); do
    if [ -n "$THREADS" ]; then
        START_CORE=$((i * THREADS))
        END_CORE=$(( (i + 1) * THREADS - 1 ))
        
        if [ $END_CORE -ge $TOTAL_CORES ]; then
            echo "Ошибка: Недостаточно ядер CPU. Запрошено $((GPU_COUNT * THREADS)), доступно $TOTAL_CORES"
            exit 1
        fi
        
        AFFINITY="$START_CORE-$END_CORE"
        
        CUDA_VISIBLE_DEVICES=$i screen -dmS "neptune-gpu$i" bash -c "
            echo \"Запуск на GPU $i (CUDA_VISIBLE_DEVICES=$i, taskset $AFFINITY)\" >> '$WORKDIR/neptune-gpu$i.log'
            taskset -c $AFFINITY ./dr_neptune_prover --pool stratum+tcp://neptune.drpool.io:30127 --cuda 0 --worker '${accountname}-gpu$i' 2>&1 | tee -a '$WORKDIR/neptune-gpu$i.log'
        "
        echo "Запущен процесс для GPU $i:"
        echo "  CUDA_VISIBLE_DEVICES: $i"
        echo "  CPU Affinity: $AFFINITY"
    else
        CUDA_VISIBLE_DEVICES=$i screen -dmS "neptune-gpu$i" bash -c "
            echo \"Запуск на GPU $i (CUDA_VISIBLE_DEVICES=$i, без taskset)\" >> '$WORKDIR/neptune-gpu$i.log'
            ./dr_neptune_prover --pool stratum+tcp://neptune.drpool.io:30127 --cuda 0 --worker '${accountname}-gpu$i' 2>&1 | tee -a '$WORKDIR/neptune-gpu$i.log'
        "
        echo "Запущен процесс для GPU $i:"
        echo "  CUDA_VISIBLE_DEVICES: $i"
        echo "  CPU Affinity: не задано"
    fi
    echo ""
done

sleep 3

echo "Статус запуска:"
echo "==============="

ALL_RUNNING=true
for i in $(seq 0 $((GPU_COUNT-1))); do
    log_file="$WORKDIR/neptune-gpu$i.log"
    if [ -f "$log_file" ]; then
        lines=$(wc -l < "$log_file")
        echo "GPU $i: ✅ Лог создан - $log_file"
        echo "       Размер: $lines строк"
        if [ $lines -gt 1 ]; then
            echo "       Последние строки:"
            tail -2 "$log_file" | sed 's/^/         /'
        else
            echo "       Лог пуст - возможно процесс не запустился"
            ALL_RUNNING=false
        fi
    else
        echo "GPU $i: ❌ ВНИМАНИЕ - Лог файл не создан: $log_file"
        ALL_RUNNING=false
    fi
    echo ""
done

echo "Управление:"
for i in $(seq 0 $((GPU_COUNT-1))); do
    echo "GPU $i: screen -r neptune-gpu$i"
done

echo ""
echo "Просмотр логов:"
for i in $(seq 0 $((GPU_COUNT-1))); do
    echo "GPU $i: tail -f $WORKDIR/neptune-gpu$i.log"
done

echo ""
screen -list | grep neptune

if [ "$ALL_RUNNING" = true ]; then
    echo "✅ Все процессы успешно запущены!"
else
    echo "⚠️  Некоторые процессы могли не запуститься. Проверьте логи выше."
fi
