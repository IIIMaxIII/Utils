#!/bin/bash

mount_points=(
    /mnt/chia_01 /mnt/chia_02 /mnt/chia_03 /mnt/chia_04
    /mnt/chia_05 /mnt/chia_06 /mnt/chia_07 /mnt/chia_08
    /mnt/chia_51 /mnt/chia_52 /mnt/chia_53 /mnt/chia_54
    /mnt/chia_55 /mnt/chia_56 /mnt/chia_57 /mnt/chia_58
)

# Функция для вывода разделительной линии
print_separator() {
    echo "-------------------------------------------------------------"
}

# Заголовок таблицы
print_separator
printf " %-12s  %-10s  %-35s \n" "Mount Point" "Files" "Fragmentation (extents:count)"
print_separator

# Функция для анализа каталога
analyze_directory() {
    local dir=$1
    declare -A extents_count
    local total_files=0

    # Обрабатываем каждый .fpt файл
    while IFS= read -r -d $'\0' fpt_file; do
        frag_info=$(filefrag -v "$fpt_file" 2>&1)
        
        if [[ "$frag_info" =~ ([0-9]+)\ extents?\ found ]]; then
            extents=${BASH_REMATCH[1]}
            ((extents_count[$extents]++))
            ((total_files++))
        fi
    done < <(find "$dir" -name "*.fpt" -type f -print0 2>/dev/null)

    # Формируем строку распределения
    if [ $total_files -gt 0 ]; then
        # Сортируем ключи по числовому значению
        sorted_extents=($(printf '%s\n' "${!extents_count[@]}" | sort -n))
        
        distribution=""
        for extents in "${sorted_extents[@]}"; do
            count=${extents_count[$extents]}
            distribution+="${extents}:${count} "
        done
        
        printf " %-12s  %-10s  %-35s \n" "$(basename "$dir")" "$total_files" "${distribution% }"
    else
        if [ -d "$dir" ]; then
            printf " %-12s  %-10s  %-35s \n" "$(basename "$dir")" "0" "No .fpt files found"
        else
            printf " %-12s  %-10s  %-35s \n" "$(basename "$dir")" "-" "Directory not mounted"
        fi
    fi
}

# Анализируем каждый каталог
for mp in "${mount_points[@]}"; do
    analyze_directory "$mp"
done

print_separator
