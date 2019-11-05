#!/bin/bash
#
*********** Variables for user modification ***************
INSTALL_MINIMUM_MEMORY=30000
INSTALL_ULIMIT=65535

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
}

# ********** Setting network **************
set_network(){
    if [[ -z "$HOST_IP" ]]; then
        case "${SYSTEM_KERNEL}" in
            Linux*)     HOST_IP=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/');;
        esac
        # *********** Setting environment variable ***************
		echo "export HOST_IP=$HOST_IP" > /etc/profile.d/elastic.sh >> $LOGFILE 2>&1
    fi
}

# ********** Setting ulimit **************
set_ulimit() {
	SYSTEM_ULIMIT=$(sed -n '/elasticsearch/p' limits.conf | grep nofile |awk '{print $4}')
	if ["$INSTALL_ULIMIT" == "$SYSTEM_ULIMIT"]; then
		echo "Already setting ulimit : ${SYSTEM_ULIMIT}"
		exit 1
	else sed -i '$ielasticsearch  -  nofile  65535\n' /etc/security/limits.conf >> $LOGFILE 2>&1
		echo "setting ulimit"
		exit 1
	fi
}

# ********** Setting swap off**************
set_swap() {
	SYSTEM_SWAP=$(sed -n '/swap/p' /etc/fstab | awk '{print $1}') >> $LOGFILE 2>&1
	if [ $ERROR -ne 0 ]; then
		echoerror "Could not get swap info in fstab (Error Code: $ERROR)."
	fi
	if [[ $SYSTEM_SWAP =~ "#" ]] then;
		echo "already setting disable swap"
		exit 1
	else sed -i '/[^#]/ s/\(^.*swap.*$\)/#\ \1/' /etc/fstab >> $LOGFILE 2>&1
		echo "setting swap off"
		exit 1
	fi
}
