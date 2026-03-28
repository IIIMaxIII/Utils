#!/usr/bin/env bash
#ln -s /hive/bin/motd /etc/update-motd.d/00-my-motd
source colors

set -o pipefail

source /etc/environment
[[ -f $RIG_CONF ]] && source $RIG_CONF
[[ -e /hive/etc/gpu.ids ]] && source /hive/etc/gpu.ids

HELLO_OK="/tmp/.hive-hello-ok"

# 1/4 of 4GB
LOW_RAM=1000
# 1/8 of 4GB
VERY_LOW_RAM=500

LOW_DISK=2000
VERY_LOW_DISK=1000

CORE_HIGH_TEMP=70
CORE_VERY_HIGH_TEMP=80

MEM_HIGH_TEMP=90
MEM_VERY_HIGH_TEMP=100

MAX_VBIOS_LEN=30

WATCH_REFRESH=2

SEP=" · "

echo ""

# hook Ctrl+C
trap "echo $NOCOLOR; exit 0" SIGINT

pretty_uptime() {
	local t=`awk '{print int($1)}' /proc/uptime`
	local d=$((t/60/60/24))
	local h=$((t/60/60%24))
	local m=$((t/60%60))
	local s=$((t%60))
	local u=
	if [[ $d -gt 0 ]]; then
		[[ $d -eq 1 ]] && u+="$d day " || u+="$d days "
	fi
	if [[ $h -gt 0 ]]; then
		[[ $h -eq 1 ]] && u+="$h hour " || u+="$h hours "
	fi
	if [[ $m -gt 0 ]]; then
		[[ $m -eq 1 ]] && u+="$m minute " || u+="$m minutes "
	fi
	if [[ $d -eq 0 && $h -eq 0 ]]; then
		[[ $s -eq 1 ]] && u+="$s second" || u+="$s seconds"
	fi
	echo $u
}


cpus=`nproc --all`

sys_la() {
    read lavg[0] lavg[1] lavg[2] procs < /proc/loadavg
    local color=
    echo -n "${SEP}LA"
    
    for la in "${lavg[@]}"; do
        if [[ ${la%.*} -le $cpus ]]; then
            color=$WHITE
        elif [[ ${la%.*} -gt $(( cpus*2 )) ]]; then
            color=$BRED
        else
            color=$BYELLOW
        fi
        echo -n " $color$la$NOCOLOR"
    done
    
    local cpu_temp=$(cpu-temp)
    
    if [[ $cpu_temp -le 50 ]]; then
        cpu_color=$WHITE
    elif [[ $temp -le 70 ]]; then
        cpu_color=$BYELLOW
    else
        cpu_color=$BRED
    fi
    
    echo -n " · $cpu_color$cpu_temp$NOCOLOR°C"
}

function sysinfo_high_la() {
	read la[0] la[1] la[2] procs < /proc/loadavg
	[[ ${la[0]%.*} -le $(( cpus + 10 )) ]] && return 0
	read host_name sys_name < <( uname -rn )
	echo -n "${BCYAN}$host_name$NOCOLOR${SEP}${BPURPLE}$sys_name$NOCOLOR${SEP}ID ${RIG_ID:-n/a}$NOCOLOR"
	sys_la
	echo "${SEP}up $(pretty_uptime)"
	echo -e "\n${BYELLOW}Warning: High LA detected!$NOCOLOR (use ${WHITE}motd help${NOCOLOR} to override)\n"
	return 1
}


# check for high LA
if [[ -z "$1" ]]; then
	sysinfo_high_la || exit 0
fi

[[ `id -u 2>/dev/null` -eq 0 ]] && NEEDSUDO= || NEEDSUDO="sudo"

# check for running hive-replace session
if $NEEDSUDO pgrep -f hive-replace >/dev/null && $NEEDSUDO timeout 1 screen -ls replace >/dev/null; then
	echo "${BYELLOW}Hive-replace session is running, resuming${NOCOLOR}"
	read -t 2 -n 1
	$NEEDSUDO bash -c "exec screen -x -S replace"
fi


# old "classic" motd
if [[ "$1" == "old" ]]; then
	echo -n `uname -sr`
	echo  "   ${YELLOW}H `dpkg -s hive | grep '^Version: ' | sed 's/Version: //'`${NOCOLOR}"
	[[ -z $WORKER_NAME ]] && WORKER_NAME=$(hostname)
	echo  ${CYAN}$WORKER_NAME${NOCOLOR}

	echo -n ${PURPLE}
	#ifconfig | grep -v "127.0.0.1" | grep "inet addr" | sed -E 's/^[[:space:]]+//'
	ip addr show | grep -v "127.0.0.1" | grep "inet .*/" | sed -E 's/^[[:space:]]+//'
	echo $NOCOLOR

	df -h /

	echo ""

	uptime

	echo  ""

	#echo "AMD GPU: `/hive/sbin/gpu-detect AMD`"
	#echo "NVIDIA GPU: `/hive/sbin/gpu-detect NVIDIA`"
	#echo ""

	/hive/sbin/gpu-detect list

	echo ""

	helpme

	echo ""
	exit
fi

# OS Image version. Currently the the same as Ubuntu distro version
image_version=$(lsb_release -rs)

# AMD OCL and module version
[[ -f /opt/amdgpu/VERSION ]] && amd_ocl_version="$( < /opt/amdgpu/VERSION )"
amd_kernel=`modinfo amdgpu |grep ^version: | sed -e 's/version://' -e 's/^[[:space:]]*//'`
amd_version=`dpkg -s amdgpu-pro 2>&1 | grep '^Version: ' | sed 's/Version: //' | awk -F'-' '{print $1}'`
[[ -z $amd_version ]] && amd_version=`dpkg -s amdgpu 2>&1 | grep '^Version: ' | sed 's/Version: //' | awk -F'-' '{print $1}'`
#if there is no driver but only OpenCL
[[ -z $amd_ocl_version ]] && amd_ocl_version=`dpkg -s opencl-amdgpu-pro-icd 2>&1 | grep '^Version: ' | sed 's/Version: //' | awk -F'-' '{print $1}'`
[[ -z $amd_kernel ]] && amd_kernel="kernel"
[[ -z $amd_version ]] && amd_version="$amd_ocl_version ($amd_kernel)"

# Intel OCL and module version
intel_ocl_version=$(dpkg-query --showformat='${Version}' --show intel-opencl-icd  2>/dev/null)
intel_kernel=$(modinfo -F version i915)

#if [[ $intel_ocl_version == "" ]]; then
#    intel_version="N/A"
#else
   [[ -n $intel_kernel ]] && intel_version="$intel_ocl_version ($intel_kernel)" || intel_version=$intel_ocl_version
#fi

gpu_types=0
gpu_count_amd=$(gpu-detect AMD)
gpu_count_nvidia=$(gpu-detect NVIDIA)
gpu_count_intel=$(gpu-detect INTEL)

[[ $gpu_count_amd -gt 0 ]]    && gpu_types=$((gpu_types+1))
[[ $gpu_count_nvidia -gt 0 ]] && gpu_types=$((gpu_types+1))
[[ $gpu_count_intel -gt 0 ]]  && gpu_types=$((gpu_types+1))
[[ $gpu_types -ge 2 && $gpu_count_intel -gt 0 && -n $intel_version ]] && ui_new_style=1 || ui_new_style=0

sys_name=$(uname -r)
[[ $(echo $sys_name | cut -f3 -d. | cut -f1 -d- ) == "0" ]] && sys_name+=" $(uname -v | cut -f1 -d. )"
cols=`tput cols`

sys_info1() {
#	echo -n "K ${BPURPLE}$sys_name${NOCOLOR}"
#	echo -n "${SEP}D ${BPURPLE}${image_version}$NOCOLOR"
#	echo -n "$SEP${BYELLOW}H $WHITE$(dpkg -s hive | grep -oP "^Version: \K.*$")$NOCOLOR"

	echo -n "${BYELLOW}H $WHITE$(dpkg -s hive | grep -oP "^Version: \K.*$")$NOCOLOR"
	echo -n "${SEP}K ${BPURPLE}$sys_name${NOCOLOR}"
	echo -n "${SEP}D ${WHITE}${image_version}$NOCOLOR"

   if [[ $ui_new_style -eq 0 ]]; then
	if [[ $gpu_count_nvidia -gt 0 ]]; then
		nv_version=`nvidia-smi --help 2>&1 | head -n 1 | grep -oP "v\K[0-9\.]+"`
		[[ ! -z $nv_version ]] && echo -n "$SEP${BGREEN}N $WHITE$nv_version$NOCOLOR"
	fi
	
	[[ $gpu_count_amd -gt 0 ]] && echo -n "$SEP${BRED}A $WHITE${amd_version}$NOCOLOR"
	[[ $gpu_count_intel -gt 0 && -n $intel_version ]] && echo -n "$SEP${CYAN}I $WHITE${intel_version}$NOCOLOR"
   fi
	if [[ $cols -lt 80 ]]; then
		# short uptime with secs
		local upt=`awk '{printf "%dd %02dh %02dm %02ds", $1/24/3600, $1/3600%24, $1/60%60, $1%60}' /proc/uptime`
		echo "${SEP}up $upt"
	else
		# uptime with secs
		echo "${SEP}up $(pretty_uptime)"
	fi
   if [[ $ui_new_style -gt 0 ]]; then
       echo -n "GPU"
	if [[ $gpu_count_nvidia -gt 0 ]]; then
		nv_version=`nvidia-smi --help 2>&1 | head -n 1 | grep -oP "v\K[0-9\.]+"`
		[[ ! -z $nv_version ]] && echo -n "$SEP${BGREEN}N $WHITE$nv_version$NOCOLOR"
	fi
	[[ $gpu_count_amd -gt 0 ]] && echo -n "$SEP${BRED}A $WHITE${amd_version}$NOCOLOR"
	[[ $gpu_count_intel -gt 0 ]] && echo -n "$SEP${CYAN}I $WHITE${intel_version}$NOCOLOR"
        echo
   fi
}


sys_info2() {
	echo -n "$BCYAN$(hostname)$NOCOLOR"
	echo -n "${SEP}ID ${RIG_ID:-n/a}$NOCOLOR"

	sys_la

	local mem=()
	#mem=(`free -b | grep 'Mem' | awk '{pcent=int(100*$7/$2+0.5); total=int(10*$2/2^30+0.5)/10; avail_gb=int(10*$7/2^30+0.5)/10; avail_mb=int($7/2^20); printf "%.1fG %.1fG %d %d", total, avail_gb, avail_mb, pcent}'`)
	mem=(`free -h --si | grep 'Mem' | awk '{print $2" "$7}'`)
	mem+=(`free -b | grep 'Mem' | awk '{pcent=int(100*$7/$2+0.5); avail=int($7/2^20); print avail" "pcent}'`)
	local color=$WHITE
	if [[ ${mem[2]} -lt $VERY_LOW_RAM ]]; then
		color=$BRED
	elif [[ ${mem[2]} -lt $LOW_RAM ]]; then
		color=$BYELLOW
	fi
	local swap=`free -h --si | grep 'Swap' | awk '{if ($2!="0B") print $2}'`
	[[ ! -z $swap ]] && swap="${SEP}Swap $WHITE$swap$NOCOLOR"
	echo "${SEP}RAM $WHITE${mem[0]}$NOCOLOR  available $color${mem[1]}$NOCOLOR ($color${mem[3]}%$NOCOLOR)$swap"
}


sys_info_compact() {
	echo -n "$BCYAN$(hostname)$NOCOLOR"

	sys_la

	local mem=()
	mem+=(`free -b | grep 'Mem' | awk '{pcent=int(100*$7/$2+0.5); avail=int($7/2^20); avail_gb=int(10*$7/2^30+0.5)/10; print 0" "avail_gb" "avail" "pcent}'`)
	local color=$WHITE
	if [[ ${mem[2]} -lt $VERY_LOW_RAM ]]; then
		color=$BRED
	elif [[ ${mem[2]} -lt $LOW_RAM ]]; then
		color=$BYELLOW
	fi
	echo -n "${SEP}AVL $color${mem[1]}G$NOCOLOR ($color${mem[3]}%$NOCOLOR)"

	# short uptime with secs
	local upt=`awk '{printf "%dd %02dh %02dm %02ds", $1/24/3600, $1/3600%24, $1/60%60, $1%60}' /proc/uptime`
	echo "${SEP}up $upt$NOCOLOR"
}


net_info() {
	local networks=(`networkctl --no-legend | grep -v "loopback" | awk '{print $2}'`)
	for net in "${networks[@]}"; do
		local nstat=`networkctl status $net`
		echo -n "$WHITE$net$NOCOLOR"
		state=`echo "$nstat" | grep -oP " State: \K.*(?= \()"`
		local color=
		if [[ $state =~ routable ]]; then
			color=$BGREEN
		elif [[ $state =~ no-carrier ]]; then
			color=$BRED
		elif [[ $state =~ carrier ]]; then
			color=$BYELLOW
		elif [[ $state =~ dormant ]]; then
			color=$BPURPLE
		fi
		echo -n "  $color$state$NOCOLOR"
		dns=`echo "$nstat" | grep -Pazo "DNS: \K[0-9\.\s]+" | tr '\n' ' ' | tr -d '\0' | awk '{$1=$1};1'`
		ips=`echo "$nstat" | grep -Pazo "  Address: \K[0-9\.\s]+" | tr '\n' ' ' | tr -d '\0' | awk '{$1=$1};1'`
		gw=`echo "$nstat" | grep -Pazo " Gateway: \K[0-9\.\s]+" | tr '\n' ' ' | tr -d '\0' | awk '{$1=$1};1'`
		driver=`echo "$nstat" | grep "Driver:" | awk -F ': ' '{print $2}'`
		[[ ! -z $ips ]] && echo -n "  ip $WHITE$ips$NOCOLOR"
		[[ ! -z $gw ]] && echo -n "  gw $WHITE$gw$NOCOLOR"
		[[ ! -z $dns ]] && echo -n "  dns $WHITE$dns$NOCOLOR"
		[[ ! -z $driver ]] && echo -n "$SEP$driver"
		echo ""
	done

#● 2: eth0
#       Link File: /lib/systemd/network/99-default.link
#    Network File: /etc/systemd/network/20-ethernet.network
#            Type: ether
#           State: routable (configured)
#            Path: pci-0000:00:1f.6
#          Driver: e1000e
#          Vendor: Intel Corporation
#           Model: Ethernet Connection (2) I219-V
#      HW Address: 70:85:c2:71:3b:84 (ASRock Incorporation)
#         Address: 192.168.1.6
#         Gateway: 192.168.1.1
#             DNS: 192.168.1.1
#                  1.1.1.1
}


disk_model=
blk_dev=`mountpoint -d /` &&
	disk_dev=`lsblk -no PKNAME /dev/block/$blk_dev 2>/dev/null` &&
		disk_model=`lsblk -no VENDOR,MODEL,SIZE /dev/$disk_dev 2>/dev/null | head -n 1 | awk '{$1=$1};1'`

disk_info() {
	local disk=()
	disk=(`df -h --output=source,size,used,avail / | tail -n 1`)
	disk+=(`df / --output=size,avail / | tail -n 1 | awk '{pcent=int(100*$2/$1+0.5); avail=int($2/1024); print pcent" "avail}'`)
	echo -n "$WHITE${disk[0]/\/dev\/}$NOCOLOR  total $WHITE${disk[1]}$NOCOLOR  used $WHITE${disk[2]}$NOCOLOR"
	local color=$WHITE
	if [[ ${disk[5]} -le $VERY_LOW_DISK ]]; then
		color=$BRED
	elif [[ ${disk[5]} -le $LOW_DISK ]]; then
		color=$BYELLOW
	fi
	[[ ! -z $disk_model ]] && disk_model="$SEP$disk_model"
	echo "  free $color${disk[3]}$NOCOLOR ($color${disk[4]}%$NOCOLOR)$disk_model"
}


sys_check() {
	local MSG=()
	#if [[ ! -f $RIG_CONF ]]; then
	#	MSG+=("${BRED}Warning: $RIG_CONF not found$NOCOLOR")
	#else
	#	[[ -z $RIG_ID ]] && MSG+=("${BRED}Error: no RIG_ID in rig.conf$NOCOLOR")
	#	[[ -z $RIG_PASSWD ]] &&  MSG+=("${BRED}Error: no RIG_PASSWD in rig.conf$NOCOLOR")
	#	[[ -z $HIVE_HOST_URL ]] &&  MSG+=("${BRED}Error: no HIVE_HOST_URL in rig.conf$NOCOLOR")
	#	[[ -z $WORKER_NAME ]] &&  MSG+=("${BRED}Error: no WORKER_NAME in rig.conf$NOCOLOR")
	#fi
	[[ -f /hive-config/.DISKLESS_AMD && $(grep "/ " /proc/mounts | awk '{print $1}') == tmpfs ]] &&
		MSG+=("${BYELLOW}Warning: This is diskless rig!$NOCOLOR")

	[[ $MAINTENANCE -eq 1 ]] && MSG+=("${BYELLOW}Warning: Maintenance mode is enabled (with drivers loading)$NOCOLOR")
	[[ $MAINTENANCE -eq 2 ]] && MSG+=("${BYELLOW}Warning: Maintenance mode is enabled (without drivers loading)$NOCOLOR")

	[[ ${#MSG[@]} -eq 0 ]] && return
	echo ""
	for msg in "${MSG[@]}"; do
		echo "$msg"
	done
}


color_printf() {
	local pad=$1
	local str="$2"
	local wocolors=`echo "$str" | sed 's/\x1b\[[0-9;]*m//g'`
	local len=$(( $pad + ${#str} - ${#wocolors} ))
	printf "%-${len}b" "$str"
}


# reread gpu_detect only on change
gpu_detect_time=0
gpu_detect_maxlen=0
gpu_detect_maxlen_novbios=0
BUSID=()

gpu_detect() {
	#[[ ! -f $GPU_DETECT_JSON ]] && return 1
	local ts=`stat -c %Y $GPU_DETECT_JSON 2>/dev/null`
	[[ -z $ts ]] && return 1
	[[ $gpu_detect_time -eq $ts ]] && return 0
	gpu_detect_time=$ts
	local gpu_detect_json="$(< $GPU_DETECT_JSON)"

	BUSID=()
	gpu_detect_maxlen=0
	gpu_detect_maxlen_novbios=0

	local gpu_index
	local nv_idx=-1
	local amd_idx=-1
	local intel_idx=-1
	local idx=-1
	while IFS=";" read busid brand vendor mem vbios name; do
		((idx++))
		BUSID[idx]="$busid"
		BRAND[idx]="$brand"
		VENDOR[idx]="$vendor"
		RAM[idx]="${mem:+ }$mem"
		VBIOS[idx]="$vbios"
		NAME[idx]="$name"

		if [[ "$brand" == "amd" || "$vendor" == "AMD" ]]; then
			COLOR[idx]=$RED
			[[ "$brand" != "amd" ]] && GPU_INDEX[idx]="-" || GPU_INDEX[idx]=$((++amd_idx))

		elif [[ "$brand" == "nvidia" || "$vendor" == "NVIDIA" ]]; then
			COLOR[idx]=$GREEN
			[[ "$brand" != "nvidia" ]] && GPU_INDEX[idx]="-" || GPU_INDEX[idx]=$((++nv_idx))
		elif [[ "$brand" == "intel" || "$vendor" == "INTEL" ]]; then
			COLOR[idx]=$CYAN
			[[ "$brand" != "intel" ]] && GPU_INDEX[idx]="-" || GPU_INDEX[idx]=$((++intel_idx))
		else
			COLOR[idx]=$YELLOW
			GPU_INDEX[idx]=""
			continue
		fi

		# get max strings length
		len=$(( ${#NAME[idx]} + ${#RAM[idx]} + 14 )) # name + mem + static
		[[ $len -gt $gpu_detect_maxlen_novbios ]] && gpu_detect_maxlen_novbios=$len
		# limit long vbios
		[[ ${#VBIOS[idx]} -gt $MAX_VBIOS_LEN ]] &&
			VBIOS[idx]="${VBIOS[idx]::$((MAX_VBIOS_LEN-2))}.."
		# + vbios
		len=$(( len + ${#VBIOS[idx]} + 3 ))
		[[ $len -gt $gpu_detect_maxlen ]] && gpu_detect_maxlen=$len

	done < <( echo "$gpu_detect_json" | jq -r -c '.[] | (.busid+";"+.brand+";"+.vendor+";"+.mem+";"+.vbios+";"+.name)' 2>/dev/null )

	[[ ${#BUSID[@]} -eq 0 ]] && return 1
	return 0
}


last_gpu_info=
last_gpu_detect_time=
last_gpu_stats_time=
gpu_stats=

gpu_info() {
	[[ ! -f $GPU_DETECT_JSON ]] && return 1

	gpu_detect || return

	local gpu_stats_time=0
	if [[ -f $GPU_STATS_JSON ]]; then
		gpu_stats_time=`stat --printf %Y $GPU_STATS_JSON`
		if [[ $gpu_stats_time -le $(( `date +%s` - 30 )) ]]; then
			gpu_stats=
		elif [[ $gpu_stats_time -ne $last_gpu_stats_time ]]; then
			readarray -t gpu_stats < <( jq --slurp -r -c '.[] | .busids, .temp, .fan, .power, if .mtemp then .mtemp else empty end | join(" ")' $GPU_STATS_JSON 2>/dev/null )
		fi
	fi

	if [[ ! -z $last_gpu_stats_time && ! -z $last_gpu_detect_time &&
		$last_gpu_stats_time -eq $gpu_stats_time && $last_gpu_detect_time -eq $gpu_detect_time ]]; then
		if [[ ! -z $1 ]]; then
			local -n ref=$1
			ref+="$last_gpu_info"
		else
			echo -n "$last_gpu_info"
		fi
		return 0
	fi
	last_gpu_detect_time=$gpu_detect_time
	last_gpu_stats_time=$gpu_stats_time

	last_gpu_info=
	local -n result=last_gpu_info
	local busids=(${gpu_stats[0]})
	local temps=(${gpu_stats[1]})
	local fans=(${gpu_stats[2]})
	local powers=(${gpu_stats[3]})
	local mtemps=(${gpu_stats[4]})
	#readarray -t mtemps < <( echo "${gpu_stats[4]// /$'\n'}" )

	[[ "${#mtemps[@]}" -gt 0 ]] && local show_mem_temp=1 || local show_mem_temp=0

	local maxlen=gpu_detect_maxlen
	# cut vbios if it does not fit in line
	local show_vbios=1
	[[ $(( maxlen + 20 )) -gt $cols ]] && maxlen=gpu_detect_maxlen_novbios && show_vbios=0

	local index
	local idx
	for(( idx=0; idx < ${#BUSID[@]}; idx++ )); do
		local output=
		local vbios="${VBIOS[idx]}"
		if [[ $show_vbios -ne 1 || -z "$vbios" ]]; then
			vbios=
		elif [[ "${BRAND[idx]}" == "cpu" ]]; then
			vbios="$SEP${BYELLOW}$vbios"
		else
			vbios="$SEP${GRAY}$vbios"
		fi
		output=`printf "%b%2s%b" "${COLOR[idx]}" "${GPU_INDEX[idx]}" "$NOCOLOR ${BUSID[idx]} ${COLOR[idx]}${NAME[idx]}$NOCOLOR${RAM[idx]}$vbios$NOCOLOR"`
		result+=`color_printf "$maxlen" "$output"`

		[[ "${busids[idx]}" != "${BUSID[idx]}" || ${powers[idx]} -eq 0 ]] && result+=$'\n' && continue

		local color=$WHITE
		if [[ ${temps[idx]} -ge 999 ]]; then
			temps[idx]="???"
			color=$BPURPLE
		elif [[ ${temps[idx]} -ge $CORE_VERY_HIGH_TEMP ]]; then
			color=$BRED
		elif [[ ${temps[idx]} -ge $CORE_HIGH_TEMP ]]; then
			color=$BYELLOW
		fi
		result+=`printf "%b%3s%b°C " "$color" "${temps[idx]}" "$NOCOLOR"`

		if [[ $show_mem_temp -eq 1 ]]; then
			local mcolor=$WHITE
			if [[ ${mtemps[idx]} -ge 999 ]]; then
				mtemps[idx]="???"
				mcolor=$BPURPLE
			elif [[ ${mtemps[idx]} -ge $MEM_VERY_HIGH_TEMP ]]; then
				mcolor=$BRED
			elif [[ ${mtemps[idx]} -ge $MEM_HIGH_TEMP ]]; then
				mcolor=$BYELLOW
			fi
			result+=`printf "%b%3s%b°C " "$mcolor" "${mtemps[idx]:---}" "$NOCOLOR"`
		fi

		[[ ${powers[idx]} -gt 999 ]] && powers[idx]="???"
		result+=`printf "%b%4s %b%% %b%4s %bW" "$WHITE" "${fans[idx]}" "$NOCOLOR" "$WHITE" "${powers[idx]}" "$NOCOLOR"`
		result+=$'\n'
	done

	if [[ ! -z $1 ]]; then
		local -n ref=$1
		ref+="$result"
	else
		echo -n "$result"
	fi
	return 0
}


gpu_compact() {
	[[ ! -f $GPU_DETECT_JSON ]] && return 1

	local gpu_stats=
	[[ -f $GPU_STATS_JSON && `stat --printf %Y $GPU_STATS_JSON` -gt $(( `date +%s` - 30 )) ]] &&
		readarray -t gpu_stats < <( jq --slurp -r -c '.[] | .brand, .busids, .temp, .fan, .power, if .mtemp then .mtemp else empty end | join(" ")' $GPU_STATS_JSON 2>/dev/null )

	local brands=(${gpu_stats[0]})
	local busids=(${gpu_stats[1]})
	local temps=(${gpu_stats[2]})
	local fans=(${gpu_stats[3]})
	local powers=(${gpu_stats[4]})
	local mtemps=(${gpu_stats[5]})
	#readarray -t mtemps < <( echo "${gpu_stats[5]// /$'\n'}" )

	# skip internal gpu
	[[ ${brands[0]} == "cpu" && ${busids[0]} =~ 00:* ]] && local first_idx=1 || local first_idx=0

	[[ "${#mtemps[@]}" -gt 0 ]] && local show_mem_temp=1 || local show_mem_temp=0

	[[ ! -z $1 ]] && local -n result=$1 || local result=
	local idx
	local step=6
	local last_idx=${#busids[@]}
	local amount=$(( (cols - 1)/step ))
	[[ $(( amount - last_idx + first_idx )) -lt 0 ]] && last_idx=$(( amount + 1 ))
	[[ $first_idx -ge $last_idx ]] && return 1

	while true
	do
		for((idx=first_idx; idx<last_idx; idx++)); do
			local color=$YELLOW
			if [[ ${brands[idx]} == "nvidia" ]]; then
				color=$GREEN
			elif [[ ${brands[idx]} == "amd" ]]; then
				color=$RED
			elif [[ ${brands[idx]} == "intel" ]]; then
				color=$CYAN
			fi
			result+=`printf "%b%${step}s%b" "$color" "${busids[idx]/\.0}" "$NOCOLOR"`
		done
		result+=$'\n'

		for((idx=first_idx; idx<last_idx; idx++)); do
			local color=$WHITE
			if [[ ${temps[idx]} -ge 999 ]]; then
				temps[idx]="???"
				color=$BPURPLE
			elif [[ ${temps[idx]} -ge $CORE_VERY_HIGH_TEMP ]]; then
				color=$BRED
			elif [[ ${temps[idx]} -ge $CORE_HIGH_TEMP ]]; then
				color=$BYELLOW
			fi
			result+=`printf "%b%$((step-2))s%b°C" "$color" "${temps[idx]}" "$NOCOLOR"`
		done
		result+=$'\n'

		if [[ $show_mem_temp -eq 1 ]]; then
			for((idx=first_idx; idx<last_idx; idx++)); do
				local color=$WHITE
				if [[ ${mtemps[idx]} -ge 999 ]]; then
					mtemps[idx]="???"
					color=$BPURPLE
				elif [[ ${mtemps[idx]} -ge $MEM_VERY_HIGH_TEMP ]]; then
					color=$BRED
				elif [[ ${mtemps[idx]} -ge $MEM_HIGH_TEMP ]]; then
					color=$BYELLOW
				fi
				result+=`printf "%b%$((step-2))s%b°C" "$color" "${mtemps[idx]:---}" "$NOCOLOR"`
			done
			result+=$'\n'
		fi

		for((idx=first_idx; idx<last_idx; idx++)); do
			result+=`printf "%b%$((step-2))s%b %%" "$WHITE" "${fans[idx]}" "$NOCOLOR"`
		done
		result+=$'\n'

		for((idx=first_idx; idx<last_idx; idx++)); do
			[[ ${powers[idx]} -gt 999 ]] && powers[idx]="???"
			result+=`printf "%b%$((step-2))s%b W" "$WHITE" "${powers[idx]}" "$NOCOLOR"`
		done
		result+=$'\n'

		[[ $last_idx -ge ${#busids[@]} ]] && break
		last_idx=$(( last_idx + amount ))
		first_idx=$(( first_idx + amount ))
		[[ $last_idx -gt ${#busids[@]} ]] && last_idx=${#busids[@]}
		result+=$'\n'
	done
	[[ -z $1 ]] && echo -n "$result"
	return 0
}


# reread only on change
rig_conf_time=0
rig_conf_update() {
	local ts=`stat -c %Y $RIG_CONF 2>/dev/null`
	[[ -z $ts ]] && return 1
	[[ $rig_conf_time -eq $ts ]] && return 0
	rig_conf_time=$ts
	# clear some vars
	local arr=("RIG_ID" "HIVE_HOST_URL" "WORKER_NAME" "MAINTENANCE" "X_DISABLED" "MINER" "MINER2" "MINER3" "MINER4" "MINER5" "MINER6" "MINER7")
	local var
	for var in "${arr[@]}"
	do
		unset $var
	done
	. $RIG_CONF
}

conf_miners=()
conf_miners_update() {
	conf_miners=()
	local miner
	local idx
	for idx in {1..7}
	do
		[[ $idx -eq 1 ]] && miner="MINER" || miner="MINER$idx"
		conf_miners[idx]="${!miner}"
	done
}


run_miners_update_timer=0
run_miners=()
run_miners_update() {
	if [[ ${#run_miners[@]} -gt 0 ]]; then
		if [[ `$NEEDSUDO screen -ls miner | grep -c "(Attached)"` -gt 0 ]]; then
			(( ++run_miners_update_timer < 15 )) && return 0
		fi
	fi
	run_miners_update_timer=0
	run_miners=()
	local windows
	windows=`timeout 1 $NEEDSUDO screen -S miner -Q windows | tail -n 1` || return 1
	readarray -t windows < <( echo "${windows//  /$'\n'}" )
	local win
	for win in "${windows[@]}"
	do
		[[ $win =~ ^([0-9]+)([^[:space:]]+)?[[:space:]]+(.*)$ ]] && run_miners[${BASH_REMATCH[1]}]="${BASH_REMATCH[3]}"
	done
}


miners_info() {
	#echo "Miners: $WHITE${scr//(L)/ -}$NOCOLOR"
	[[ -e $WALLET_CONF ]] && . $WALLET_CONF
	run_miners_update
	conf_miners_update
	[[ ${#run_miners[@]} -eq 0 && ${#conf_miners[@]} -eq 0 ]] && return 0
	local idx
	local output=
	for idx in {1..7}
	do
		[[ -z ${run_miners[idx]} && -z ${conf_miners[idx]} ]] && continue
		local miner_name=
		local miner_fork=
		local miner_ver=
		if [[ ! -z ${conf_miners[idx]} ]]; then
			# get version from flightsheet
			miner_name=${conf_miners[idx]//-/_}
			miner_fork="${miner_name^^}_FORK"
			miner_fork=${!miner_fork}
			miner_ver="${miner_name^^}_VER"
			miner_ver=${!miner_ver}
			if [[ ! -z $miner_ver ]]; then
				miner_ver="$WHITE$miner_ver$NOCOLOR"
			else
				read miner_ver < <(
					# get default version from miner config
					MINER_DIR=/hive/miners/${conf_miners[idx]}
					[[ -e $MINER_DIR/h-manifest.conf ]] && source $MINER_DIR/h-manifest.conf
					[[ -e $MINER_DIR/h-config.sh ]] && source $MINER_DIR/h-config.sh
					declare -fF miner_fork > /dev/null && # if function exists
						export MINER_FORK=`miner_fork` || export MINER_FORK=
					miner_ver 2>/dev/null
				)
			fi
			miner_ver="${miner_ver:+ }$miner_ver"
			miner_fork="${miner_fork:+-}$miner_fork"
		fi
		[[ ${run_miners[idx]} == ${conf_miners[idx]} ]] && output+="$SEP$BGREEN${conf_miners[idx]}$miner_fork$NOCOLOR$miner_ver" && continue
		[[ ! -z ${conf_miners[idx]} ]] && output+="$SEP$BRED${conf_miners[idx]}$miner_fork$NOCOLOR$miner_ver"
		[[ ! -z ${run_miners[idx]} ]] && output+="$SEP$BYELLOW${run_miners[idx]}$NOCOLOR"
	done
	local fs=
	[[ -f $WALLET_CONF ]] && fs=`grep -m 1 -oP "FLIGHT SHEET \K\".*\"(?= ###$)" $WALLET_CONF 2>/dev/null` || fs="${BRED}EMPTY"
	echo " $BCYAN$fs$NOCOLOR$output$NOCOLOR"

	return 0
}


add_help() {
	local -n var=$1
	output+=`printf '\n%b%14s%b · %b' "$WHITE" "$2" "$NOCOLOR" "$3"`
}


show_log() {
	# $cols is global
	local screen=$1
	local needed_lines=$2
	local -n result=$3
	local need_padding=$4

	# log menu
	local menu_color=$DGRAY

	local output=" "
	local i
	for i in {1..11}
	do
		local tab=$i
		local color=$CYAN
		if [[ $i -eq 8 ]]; then
			title="syslog"
		elif [[ $i -eq 9 ]]; then
			title="autofan"
		elif [[ $i -eq 10 ]]; then
			title="agent"
			tab="0"
		elif [[ $i -eq 11 ]]; then
			title="help"
			tab="h"
		else
			title=${run_miners[i]}
			color=$BGREEN
			[[ -z $title ]] && title=${conf_miners[i]} && color=$BRED
			[[ -z $title && "$i" != "$screen" ]] && continue
		fi
		[[ ! -z $title ]] && title=" $title"
		if [[ "$i" == "$screen" ]]; then
			output+="${menu_color}=${RED} [ $WHITE$tab$color$title $RED] $NOCOLOR"
		else
			output+="${menu_color}= $WHITE$tab$color$title $NOCOLOR"
		fi
	done
	# finish menu line
	output+="${menu_color}="
	
	local menu_len; menu_len=`echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | wc -m` || menu_len=$cols
	# make menu shorter if needed
	if [[ $menu_len -gt $cols ]]; then
		output=${output/syslog/SL}
		output=${output/autofan/AF}
		output=${output/agent/Ag}
		output=${output/help/\?}
		menu_len=`echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | wc -m` || menu_len=$cols
	fi
	# even more shorter
	if [[ $menu_len -gt $cols ]]; then
		output=${output//miner}
		menu_len=`echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | wc -m` || menu_len=$cols
	fi
	while [[ $menu_len -lt $cols ]]; do
		output+="="
		((menu_len++))
	done
	result+="$output$NOCOLOR"$'\n'
	needed_lines=$(( needed_lines - menu_len/(cols+1) - 1 ))

	# log itself
	local padding=-1 # count at the end
	if [[ $screen == "11" ]]; then
		output=
		add_help output "g" "switch gpu stats display mode"
		add_help output "t" "switch top info display mode"
		add_help output "f" "switch full screen log display mode"
		add_help output "1..7" "show selected miner log"
		add_help output "8" "show syslog"
		add_help output "9" "show autofan log"
		add_help output "0" "show agent log"
		add_help output "shift + 0..9" "show selected log in split mode at bottom"
		add_help output "s" "swap top and bottom logs in split mode" # "
		add_help output "d" "disable split mode (or select the same logs)"
		add_help output "- +" "change logs size in split mode"
		add_help output "=" "reset logs size in split mode"
		add_help output "a" "alternative drawing mode (to avoid flicker)"
		add_help output "Esc e x q" "exit"

	elif [[ $screen == "8" ]]; then
		output=`tail -n $needed_lines /var/log/syslog 2>/dev/null | tr -d "\r" | sed 's/.\{'$cols'\}/&\n/g'`

	elif [[ $screen == "9" ]]; then
		output=`autofan log 2>/dev/null | tail -n $needed_lines | tr -d "\r" | sed 's/.\{'$cols'\}/&\n/g'`

	elif [[ $screen == "10" ]]; then
		output=`agent-screen log 2>/dev/null | tail -n $needed_lines | tr -d "\r" | sed 's/.\{'$cols'\}/&\n/g'`

	else
		#output=`miner log $screen`
		output=`tail -n $needed_lines /run/hive/miner.$screen 2>/dev/null | tr -d "\r" | cat -s`
		if [[ $? -ne 0 ]]; then
			output=$'\n'" No log for miner #$screen"
		else
			# most tricky part. calc line wrapping for colored output
			local arr
			readarray -t arr < <( echo "$output" | sed 's/\x1b\[[0-9;]*m//g' )
			local calc_lines=0
			local length=$(( ${#arr[@]} - 1 ))
			local real_lines
			for((idx=length; idx>=0; idx--)); do
				real_lines=$(( ${#arr[idx]}/(cols+1) + 1 ))
				[[ $(( calc_lines + real_lines )) -gt $needed_lines ]] && break
				calc_lines=$(( calc_lines + real_lines ))
			done
			# set padding amount
			padding=$(( needed_lines - calc_lines ))
			# set lines needed to grab
			needed_lines=$(( length - idx ))
		fi
	fi

	result+=`echo "$output" | tail -n $needed_lines`
	if [[ $need_padding -eq 1 ]]; then
		[[ $padding -eq -1 ]] && padding=$(( needed_lines - `echo "$output" | wc -l` ))
		output=
		for((i=1; i<=padding; i++)); do
			output+=$'\n'
		done
		result+=$output
	fi
	#result+=$NOCOLOR
	#result+=$'\r'"(c=$cols; h=$2; l=$needed_lines; p=$padding)"
}


function show_top() {
	sys_info1
	sys_info2
	disk_info
	net_info
	sys_check
}


function motd_watch_output() {
	local lines=`tput lines`
	local cols=`tput cols`
	local buffer=
	local used_lines=0

	if [[ $full_screen -ne 1 ]]; then
		[[ $compact_top -eq 0 ]] && buffer+=`show_top` || buffer+=`sys_info_compact`
		buffer+=$'\n'$'\n'
		if [[ $compact_gpu -eq 0 ]]; then
			gpu_info buffer || buffer+=`unbuffer gpu-detect list`$'\n'
			buffer+=$'\n'
		else
			gpu_compact buffer && buffer+=$'\n'
		fi
		# strip colors and wrap lines for correct size
		used_lines=`echo "$buffer" | sed 's/\x1b\[[0-9;]*m//g; s/.\{'$((cols+1))'\}/&\n/g' | wc -l`
		((used_lines--))
	fi

	local log_lines=$(( lines - used_lines ))
	if [[ $first == $second || $log_lines -lt $(( pos_limit*2 )) ]]; then
		show_log $first $log_lines buffer
	else
		local real_limit=$(( log_lines/2 - pos_limit ))
		[[ $position -gt $real_limit ]] && position=$real_limit
		[[ $position -lt -$real_limit ]] && position=-$real_limit
		local second_lines=$(( log_lines/2 - position ))
		local first_lines=$(( log_lines - second_lines ))
		show_log $first $first_lines buffer 1
		buffer+=$'\n'
		show_log $second $second_lines buffer
	fi

	if [[ $alt_buffer -eq 0 ]]; then
		clear
		echo -n "$buffer"
	else
		echo -n "$cursor${buffer//$'\n'/$clearline$'\n'}$clearend"
	fi
}


function motd_watch() {
	# default values
	if [[ "$1" == "boot" ]]; then
		local compact_top=0
		local compact_gpu=0
	else
		local compact_top=1
		local compact_gpu=1
	fi
	local first=1
	local second=1
	local alt_buffer=1
	local full_screen=0

	local position=0
	local pos_limit=5
	local clearline=$'\033[K' # $'\033[0m\033[K'
	local clearend=$'\033[0m\033[J'
	local cursor=$'\033[H'

	# switching to alt screen mode
	trap "tput rmcup; tput cnorm" EXIT
	tput smcup
	tput civis
	tput bce

	# main loop
	while true
	do
		rig_conf_update
		run_miners_update
		conf_miners_update

		if [[ "$1" == "boot" ]]; then
			( motd_watch_output ) # sub shell
		else
			motd_watch_output
		fi

		read -rs -n 1 -t $WATCH_REFRESH key
		[[ -z $key ]] && continue

		[[ "$key" =~ ($'\033'|q|e|x)  ]] && break

		if [[ "$key" =~ ^[0-9]$ ]]; then
			[[ "$key" == "0" ]] && key=10
			[[ $second -eq $first ]] && second=$key
			first=$key
			continue
		fi

		[[ "$key" == "t" ]] && ((compact_top ^= 1)) && continue
		[[ "$key" == "g" ]] && ((compact_gpu ^= 1)) && continue
		[[ "$key" == "f" ]] && ((full_screen ^= 1)) && continue

		[[ "$key" == "h" ]] && first=11 && continue
		[[ "$key" == "H" ]] && second=11 && continue
		[[ "$key" == "s" ]] && local tmp=$first && first=$second && second=$tmp && continue # "
		[[ "$key" == "d" ]] && second=$first && continue
		[[ "$key" == "+" ]] && ((position--)) && continue
		[[ "$key" == "-" ]] && ((position++)) && continue
		[[ "$key" == "=" ]] && position=0 && continue

		[[ "$key" == "!" ]] && second=1 && continue
		[[ "$key" == "@" ]] && second=2 && continue
		[[ "$key" == "#" ]] && second=3 && continue
		[[ "$key" == "\$" ]] && second=4 && continue
		[[ "$key" == "%" ]] && second=5 && continue
		[[ "$key" == "^" ]] && second=6 && continue
		[[ "$key" == "&" ]] && second=7 && continue
		[[ "$key" == "*" ]] && second=8 && continue
		[[ "$key" == "(" ]] && second=9 && continue
		[[ "$key" == ")" ]] && second=10 && continue

		if [[ "$key" == "a" ]] ; then
			((alt_buffer ^= 1))
			echo -n $'\r'"$BYELLOW ALT MODE: $alt_buffer$clearline"
			sleep 1
			continue
		fi
	done

	return 0
}


if [[ "$1" == "watch" ]]; then
	# prevent running from scripts
	[[ ! -t 1 ]] && echo "Watch must be run from terminal!" && exit 1
	motd_watch
	exit
fi

# run motd watch in main terminal (console or X) only if monitor is connected
if [[ "$1" == "boot" && -t 1 && -f $HELLO_OK ]]; then
	tty1=$(tty | sed 's/\/dev\///')
	tty_all=( $(ps aux | grep -v grep | grep "firstrun; motd boot; bash" | awk '{print $7}') )
	[[ $tty1 == "tty$(fgconsole)" || $(pstree -As $$ | grep -c "xinit") -gt 0 || ${tty_all[@]} =~ $tty1 ]] &&
		grep -q "^connected" /sys/class/drm/*/status 2>/dev/null &&
		( motd_watch boot )
fi

# start from beginning of line
echo -n $'\r'

show_top
echo
gpu_info || gpu-detect list
echo
miners_info
echo

# show help only on boot and console session start
# this does not work correct in teleconsole
if [[ "$1" =~ ^(boot|help|--help|-h)$ || `timeout --foreground -s9 3 ps --no-headers $PPID 2>/dev/null` =~ (-bash|motd) ]]; then
	# do not wrap help in motd
	tput rmam
	unbuffer helpme | tr -d '\r' | awk '{print $0" "}'
	tput smam
fi

exit 0
