#!/bin/bash

# Colors for output
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Number of measurements
count=100

# Threshold values for load
highload=90  # high load
medload=70   # medium load

# Get list of all available GPUs
gpu_list=$(nvidia-smi --query-gpu=index --format=csv,noheader,nounits 2>/dev/null)

if [ -z "$gpu_list" ]; then
    echo -e "${RED}Error: Failed to get GPU list${NC}"
    exit 1
fi

gpu_count=$(echo "$gpu_list" | wc -l)
total_measurements=$((gpu_count * count))

echo
echo -e "Detected GPUs: $gpu_count"

# Arrays to store results
declare -a gpu_names
declare -a pcie_modes
declare -a max_speeds
declare -a avg_rx_values
declare -a avg_tx_values
declare -a avg_rx_percents
declare -a avg_tx_percents
declare -a high_load_rx_counts
declare -a high_load_tx_counts
declare -a med_load_rx_counts
declare -a med_load_tx_counts

# Function to determine color based on percentage
get_color() {
    local percent=$1
    if [ $percent -ge $highload ]; then
        echo -n "$RED"
    elif [ $percent -ge $medload ]; then
        echo -n "$YELLOW"
    else
        echo -n "$GREEN"
    fi
}

# Function for progress bar
progress_bar() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((current * width / total))
    local remaining=$((width - completed))

    printf "["
    printf "%${completed}s" | tr ' ' '='
    printf "%${remaining}s" | tr ' ' ' '
    printf "] %3d%%" $percentage
}

# Function to update overall progress
update_total_progress() {
    local current=$1
    local total=$2
    printf "\rTotal progress: %s" "$(progress_bar $current $total)"
}

# Function to collect data for a single GPU
collect_gpu_data() {
    local gpu_number=$1
    local count=$2

    # Get PCIe information
    pcie_info=$(nvidia-smi -i $gpu_number --query-gpu=pcie.link.gen.current,pcie.link.width.current --format=csv,noheader,nounits 2>/dev/null)

    if [ -z "$pcie_info" ]; then
        echo -e "${RED}Error: Failed to get PCIe info for GPU $gpu_number${NC}"
        return 1
    fi

    pcie_gen=$(echo $pcie_info | cut -d',' -f1 | tr -d ' ')
    pcie_width=$(echo $pcie_info | cut -d',' -f2 | tr -d ' ')

    # Determine max speed per lane based on PCIe generation
    case "$pcie_gen" in
        "1") max_speed_per_lane=250;;   # PCIe 1.0
        "2") max_speed_per_lane=500;;   # PCIe 2.0
        "3") max_speed_per_lane=985;;   # PCIe 3.0
        "4") max_speed_per_lane=1969;;  # PCIe 4.0
        "5") max_speed_per_lane=3938;;  # PCIe 5.0
        *) max_speed_per_lane=985;;     # Default to PCIe 3.0
    esac

    max_speed=$((max_speed_per_lane * pcie_width))
    high_threshold=$((max_speed * highload / 100))  # corrected to use highload variable
    med_threshold=$((max_speed * medload / 100))

    # Variables for statistics
    local total_rx=0
    local total_tx=0
    local high_load_rx=0
    local high_load_tx=0
    local med_load_rx=0
    local med_load_tx=0

    # Collect multiple measurements
    for ((i=1; i<=$count; i++)); do
        # Get GPU traffic data using nvidia-smi dmon
        result=$(nvidia-smi dmon -s t -c 1 -i $gpu_number 2>/dev/null | awk '/^[[:space:]]*[0-9]/{print $2,$3; exit}')

        if [ -n "$result" ]; then
            rx=$(echo $result | awk '{print $1}')
            tx=$(echo $result | awk '{print $2}')

            # Validate that values are numbers
            if [[ "$rx" =~ ^[0-9]+$ ]] && [[ "$tx" =~ ^[0-9]+$ ]]; then
                total_rx=$((total_rx + rx))
                total_tx=$((total_tx + tx))

                # Count high and medium load occurrences
                if [ $rx -ge $high_threshold ]; then
                    high_load_rx=$((high_load_rx + 1))
                elif [ $rx -ge $med_threshold ]; then
                    med_load_rx=$((med_load_rx + 1))
                fi

                if [ $tx -ge $high_threshold ]; then
                    high_load_tx=$((high_load_tx + 1))
                elif [ $tx -ge $med_threshold ]; then
                    med_load_tx=$((med_load_tx + 1))
                fi
            fi
        fi
        
        # Update overall progress every 1%
        current_total=$(( (gpu_index * count) + i ))
        if (( current_total % (total_measurements / 100 + 1) == 0 )) || (( current_total == total_measurements )); then
            update_total_progress $current_total $total_measurements
        fi
    done

    # Calculate average values
    local avg_rx=$((total_rx / count))
    local avg_tx=$((total_tx / count))
    local avg_rx_percent=$((avg_rx * 100 / max_speed))
    local avg_tx_percent=$((avg_tx * 100 / max_speed))

    # Store results in arrays
    gpu_names+=("GPU $gpu_number")
    pcie_modes+=("Gen $pcie_gen x$pcie_width")
    max_speeds+=("$max_speed")
    avg_rx_values+=("$avg_rx")
    avg_tx_values+=("$avg_tx")
    avg_rx_percents+=("$avg_rx_percent")
    avg_tx_percents+=("$avg_tx_percent")
    high_load_rx_counts+=("$high_load_rx")
    high_load_tx_counts+=("$high_load_tx")
    med_load_rx_counts+=("$med_load_rx")
    med_load_tx_counts+=("$med_load_tx")
}

# Collect data from all GPUs
gpu_index=0
for gpu in $gpu_list; do
    collect_gpu_data $gpu $count
    ((gpu_index++))
    sleep 1  # Small delay between GPU measurements
done

# Finish progress bar
update_total_progress $total_measurements $total_measurements
echo " - Done"
echo

# Display final results table
printf "${WHITE}%-8s | %-12s | %-10s | %-14s | %-14s | %-14s | %-14s${NC}\n" \
       "GPU" "PCIe Mode" "Max(MB/s)" "RX(MB/s)" "TX(MB/s)" "Load >${medload}%" "Load >${highload}%"
echo "---------|--------------|------------|----------------|----------------|----------------|----------------"

# Display data for each GPU
for i in "${!gpu_names[@]}"; do
    rx_color=$(get_color ${avg_rx_percents[$i]})
    tx_color=$(get_color ${avg_tx_percents[$i]})

    printf "%-8s | %-12s | %-10s | ${rx_color}%-14s${NC} | ${tx_color}%-14s${NC} | ${YELLOW}%-14s${NC} | ${RED}%-14s${NC}\n" \
           "${gpu_names[$i]}" \
           "${pcie_modes[$i]}" \
           "${max_speeds[$i]}" \
           "${avg_rx_values[$i]} (${avg_rx_percents[$i]}%)" \
           "${avg_tx_values[$i]} (${avg_tx_percents[$i]}%)" \
           "RX:${med_load_rx_counts[$i]}/TX:${med_load_tx_counts[$i]}" \
           "RX:${high_load_rx_counts[$i]}/TX:${high_load_tx_counts[$i]}"
done
