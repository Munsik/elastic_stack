#!/bin/bash
#
INSTALL_MINIMUM_MEMORY=30000
INSTALL_ULIMIT=65535
INSTALL_NPROC=4096
INSTALL_FSIZE=unlimited
INSTALL_MEMLOCK=unlimited
SERVICE_USER_NAME=elasticsearch
SYSCTL_VM_MAX_MAP_COUNT=262144

# *********** Global config *********** #
SYSTEM_KERNEL="$(uname -s)"
AVAILABLE_MEMORY=$(awk '/MemAvailable/{printf "%.f", $2/1024}' /proc/meminfo)

# *********** Check if user is root ***************
if [[ $EUID -ne 0 ]]; then
   echo "YOU MUST BE ROOT TO RUN THIS SCRIPT"
   exit 1
fi

# *********** Set Log File ***************
LOGFILE="/var/log/elastic-preconfiguration-install.log"

echoerror() {
    printf "${RC} * ERROR${EC}: $@\n" 1>&2;
}


# ********** Check Minimum Requirements **************
check_min_requirements(){
    if [ "$SYSTEM_KERNEL" == "Linux" ]; then
        ARCHITECTURE=$(uname -m)
        if [ "${ARCHITECTURE}" != "x86_64" ]; then
            echo "Your Systems Architecture: ${ARCHITECTURE}"
            exit 1
        fi
        if [[ "${AVAILABLE_MEMORY}" -ge $INSTALL_MINIMUM_MEMORY ]]; then
            echo "Available Memory: $AVAILABLE_MEMORY MBs"
        else
            echo "YOU DO NOT HAVE ENOUGH AVAILABLE MEMORY"
            echo "Available Memory: $AVAILABLE_MEMORY MBs"
            exit 1
        fi
    else
        echo "Could not calculate available memory for $SYSTEM_KERNEL"
    fi
}

check_system_info(){
    if [ "$SYSTEM_KERNEL" == "Linux" ]; then
        # *********** Check distribution list ***************
        LSB_DIST="$(. /etc/os-release && echo "$ID")"
        LSB_DIST="$(echo "$LSB_DIST" | tr '[:upper:]' '[:lower:]')"
        # *********** Check distribution version ***************
        case "$LSB_DIST" in
            centos)
                if [ -z "$DIST_VERSION" ] && [ -r /etc/os-release ]; then
                    DIST_VERSION="$(. /etc/os-release && echo "$VERSION_ID")"
                fi
            ;;
        esac
        ERROR=$?
        if [ $ERROR -ne 0 ]; then
            echoerror "Could not verify distribution or version of the OS (Error Code: $ERROR)."
        fi
		echo "Using $LSB_DIST version $DIST_VERSION"
	fi
}

# ********** Check Minimum Requirements **************
install_iproute(){
    echo "Check and Install iproute"
	if [ -x "$(command -v ip)" ]; then
	echo "ip already installed"
    case "$LSB_DIST" in
        centos)
            yum install -y iproute >> $LOGFILE 2>&1
        ;;
    esac
    ERROR=$?
    if [ $ERROR -ne 0 ]; then
        echoerror "Could not install iproute for $LSB_DIST $DIST_VERSION (Error Code: $ERROR)."
        exit 1
    fi
	fi
}

# ********** Setting network **************
set_network(){
    if [[ -z "$HOST_IP" ]]; then
        case "${SYSTEM_KERNEL}" in
            Linux*)     HOST_IP=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/');;
        esac
        # *********** Setting environment variable ***************
		echo "export HOST_IP=$HOST_IP" > /etc/profile.d/elastic.sh >> $LOGFILE 2>&1
		echo "export HOST_IP=$HOST_IP" > /etc/profile.d/elastic.sh
		echo "Setting $HOST_IP at /etc/profile.d/elastic.sh"
    fi
}

# ********** Setting ulimit **************
set_ulimit() {
	SYSTEM_ULIMIT=$(sed -n '/'"${SERVICE_USER_NAME}"'/p' /etc/security/limits.conf | grep nofile |awk '{print $4}'|tail -1);

	if [[ $INSTALL_ULIMIT == "$SYSTEM_ULIMIT" ]]; then
		echo "Already setting ulimit : $SYSTEM_ULIMIT"

	else 
		echo "setting ulimit"
		sed -i '$i'"${SERVICE_USER_NAME}"'  hard  nofile  65535' /etc/security/limits.conf >> $LOGFILE 2>&1
		sed -i '$i'"${SERVICE_USER_NAME}"'  soft  nofile  65535' /etc/security/limits.conf >> $LOGFILE 2>&1
	fi
}

# ********** Setting nproc **************
set_nproc() {
	SYSTEM_NPROC=$(sed -n '/'"${SERVICE_USER_NAME}"'/p' /etc/security/limits.conf | grep nproc |awk '{print $4}'|tail -1);

	if [[ $INSTALL_NPROC == "$SYSTEM_NPROC" ]]; then
		echo "Already setting nproc : $SYSTEM_NPROC"

	else 
		echo "setting nproc"
		sed -i '$i'"${SERVICE_USER_NAME}"'  hard  nproc	4096' /etc/security/limits.conf >> $LOGFILE 2>&1
		sed -i '$i'"${SERVICE_USER_NAME}"'  soft  nproc	4096' /etc/security/limits.conf >> $LOGFILE 2>&1
	fi
}


# ********** Setting fsize **************
set_fsize() {
	SYSTEM_FSIZE=$(sed -n '/'"${SERVICE_USER_NAME}"'/p' /etc/security/limits.conf | grep fsize |awk '{print $4}'|tail -1);

	if [[ $INSTALL_FSIZE == "$SYSTEM_FSIZE" ]]; then
		echo "Already setting fsize : $SYSTEM_FSIZE"

	else 
		echo "setting fsize"
		sed -i '$i'"${SERVICE_USER_NAME}"'  hard  fsize	unlimited' /etc/security/limits.conf >> $LOGFILE 2>&1
		sed -i '$i'"${SERVICE_USER_NAME}"'  soft  fsize	unlimited' /etc/security/limits.conf >> $LOGFILE 2>&1
	fi
}

# ********** Setting memlock **************
set_memlock() {
	SYSTEM_MEMLOCK=$(sed -n '/'"${SERVICE_USER_NAME}"'/p' /etc/security/limits.conf | grep memlock |awk '{print $4}'|tail -1);

	if [[ $INSTALL_MEMLOCK == "$SYSTEM_MEMLOCK" ]]; then
		echo "Already setting memlock : $SYSTEM_MEMLOCK"

	else 
		echo "setting memlock"
		sed -i '$i'"${SERVICE_USER_NAME}"'  hard  memlock	unlimited' /etc/security/limits.conf >> $LOGFILE 2>&1
		sed -i '$i'"${SERVICE_USER_NAME}"'  soft  memlock	unlimited' /etc/security/limits.conf >> $LOGFILE 2>&1
	fi
}

# ********** Setting swap off**************
set_swap() {
	SYSTEM_SWAP=$(sed -n '/swap/p' /etc/fstab | awk '{print $1}') >> $LOGFILE 2>&1
	if [ $ERROR -ne 0 ]; then
		echo "Could not get swap info in fstab (Error Code: $ERROR)."
		exit 1
	fi
	if [[ $SYSTEM_SWAP =~ "#" ]]; then
		echo "Already setting swap : disable"

	else sed -i '/[^#]/ s/\(^.*swap.*$\)/#\ \1/' /etc/fstab >> $LOGFILE 2>&1
		echo "setting swap off"

	fi
}

set_mapcount() {
	SYSTEM_MAPCOUNT=$(sed -n '/max_map_count/p' /etc/sysctl.conf | awk '{print $1}' | grep -o '[0-9]*');

	if [[ $SYSCTL_VM_MAX_MAP_COUNT == "$SYSTEM_MAPCOUNT" ]]; then
		echo "Already setting memlock : $SYSTEM_MAPCOUNT"

	else 
		echo "setting mapcount"
		sed -i '$ivm.max_map_count='"${SYSCTL_VM_MAX_MAP_COUNT}"'' /etc/sysctl.conf >> $LOGFILE 2>&1
	fi
}

# *********** Banner ***************************
show_banner(){
    echo " "
    echo "**********************************************"
    echo "**          Server OS config check          **"
    echo "**                                          **"
    echo "** Author: munsik,kim			      **"
    echo "** Last update: '20.1.7                     **"
    echo "**********************************************"
    echo " "
}

# *********** Install ************************

install () {
	show_banner
	check_min_requirements
	check_system_info
	install_iproute
	set_network
	set_ulimit
	set_nproc
	set_fsize
	set_memlock
	set_swap
	set_mapcount
}

install
