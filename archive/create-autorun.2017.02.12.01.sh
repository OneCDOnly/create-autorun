#!/bin/bash
#
# create-autorun.sh
#
# This version was coded on 2017/02/12 by OneCD and you can blame him if it all goes horribly wrong. ;)
#
# Create an autorun environment suited to this model NAS.
#
# Tested on QTS 4.2.3 #20170121 running on my QNAP TS-569 Pro.

Init()
	{

	# include QNAP functions
	. "/etc/init.d/functions"

	FindDefVol

	local SCRIPT_FILE="create-autorun.sh"
	SCRIPT_NAME="${SCRIPT_FILE%.*}"
	local SCRIPT_VERSION="2017.02.12.01"

	local NAS_BOOT_PATHFILE="/etc/default_config/BOOT.conf"
	local NAS_PLATFORM_PATHFILE="/etc/platform.conf"
	local NAS_CONFIG_PATHFILE="/etc/config/uLinux.conf"

	read NAS_ARC < "$NAS_BOOT_PATHFILE"
	local NAS_MODEL=$(getcfg -f "$NAS_CONFIG_PATHFILE" "System" "Model")
	local NAS_MODEL_DISPLAY=$(getcfg -f "$NAS_PLATFORM_PATHFILE" "MISC" "DISPLAY_NAME")
	local QTS_VERSION=$(getcfg -f "$NAS_CONFIG_PATHFILE" "System" "Version")
	local QTS_BUILD=$(getcfg -f "$NAS_CONFIG_PATHFILE" "System" "Build Number")
	NAS_DOM_NODE=$(getcfg -f "$NAS_PLATFORM_PATHFILE" "CONFIG STORAGE" "DEVICE_NODE")
	NAS_DOM_PART=$(getcfg -f "$NAS_PLATFORM_PATHFILE" "CONFIG STORAGE" "FS_ACTIVE_PARTITION")
	NAS_DOM_FS=$(getcfg -f "$NAS_PLATFORM_PATHFILE" "CONFIG STORAGE" "FS_TYPE")

	ShowHeading "Details"
	ShowInfo "script version" "$SCRIPT_VERSION"
	ShowInfo "NAS model" "$NAS_MODEL ($NAS_MODEL_DISPLAY)"
	ShowInfo "QTS version" "$QTS_VERSION #$QTS_BUILD"
	ShowInfo "default volume" "$DEF_VOLMP"

	ShowHeading "Log"

	AUTORUN_FILE="autorun.sh"
	AUTORUN_PATH="${DEF_VOLMP}/.system/autorun"
	SCRIPT_STORE_PATH="${AUTORUN_PATH}/scripts"

	DOM_PARTITION_SIZE_EXPECTED="8896512"
	MOUNT_BASE_PATH="/tmp/$SCRIPT_NAME"

	exitcode=0

	}

FindDOMPartition()
	{

	if [ ! -z "$NAS_DOM_NODE" ]; then
		DOM_partition="${NAS_DOM_NODE}${NAS_DOM_PART}"
	else
		if [ -e "/sbin/hal_app" ]; then
			DOM_partition="$(hal_app --get_boot_pd port_id=0)6"
		elif [ "$NAS_ARC" == "TS-NASARM" ]; then
			DOM_partition="/dev/mtdblock5"
		else
			DOM_partition="/dev/sdx6"
		fi
	fi

	if [ "$DOM_partition" ]; then
		ShowSuccess "DOM partition found" "$DOM_partition"
	else
		ShowFailed "Unable to find the DOM partition!"
		exitcode=2
	fi

	}

CreateMountPoint()
	{

	DOM_mount_point=$(mktemp -d "${MOUNT_BASE_PATH}.XXXXXX" 2> /dev/null)

	if [ "$?" -ne "0" ]; then
		ShowFailed "Unable to create a DOM mount-point!"
		exitcode=3
	fi

	}

MountDOMPartition()
	{

	mountflag=false

	if [ "$NAS_DOM_FS" == "ubifs" ]; then
		ubiattach -m "$NAS_DOM_PART" -d 2 2> /dev/null
		mount -t ubifs ubi2:config "$DOM_mount_point"

		if [ "$?" -eq "0" ]; then
			ShowSuccess "mounted UBIFS DOM partition at" "$DOM_mount_point"
			mountflag=true
		else
			ShowFailed "Unable to mount the UBIFS DOM partition!"
			exitcode=4
		fi
	else
		mount -t ext2 "$DOM_partition" "$DOM_mount_point"

		if [ "$?" -eq "0" ]; then
			ShowSuccess "mounted EXT2 DOM partition at" "$DOM_mount_point"
			mountflag=true
		else
			ShowFailed "Unable to mount the EXT2 DOM partition!"
			exitcode=4
		fi
	fi

	}

ConfirmDOMPartition()
	{

	# check DOM partition size
	partition_size=$(which lsblk > /dev/null && lsblk --bytes --output SIZE --noheadings "$DOM_partition" || echo "UNKNOWN")

	if [ "$partition_size" != "UNKNOWN" ]; then
		if [ "$partition_size" -ne "$DOM_PARTITION_SIZE_EXPECTED" ]; then
			ShowFailed "DOM partition size is incorrect! (expected [$DOM_PARTITION_SIZE_EXPECTED] but found [$partition_size]"
			exitcode=5
			return
		fi
	else
		# firmware doesn't include lsblk - but proceed wth DOM tests anyway
		ShowFailed "Unable to confirm DOM partion size - proceed anyway"
	fi

	# look for a known file
	if [ ! -e "${DOM_mount_point}/uLinux.conf" ]; then
		ShowFailed "DOM tag-file was not found!"
		exitcode=6
	fi

	}

CreateScriptStore()
	{

	mkdir -p "$SCRIPT_STORE_PATH" 2> /dev/null

	if [ "$?" -ne "0" ]; then
		ShowFailed "Unable to create script store!"
		exitcode=7
	fi

	}

CreateProcessor()
	{

	# write the script directory processor to disk.
	autorun_processor_pathfile="${AUTORUN_PATH}/${AUTORUN_FILE}"

	cat > "$autorun_processor_pathfile" << EOF
#!/bin/bash

AUTORUN_PATH="$AUTORUN_PATH"
SCRIPT_STORE_PATH="$SCRIPT_STORE_PATH"
LOGFILE="/var/log/autorun.log"

echo "\$(date) ----- running autorun.sh -----" >> "\$LOGFILE"

for i in \${SCRIPT_STORE_PATH}/* ; do
	if [[ -x \$i ]] ; then
		echo -n "\$(date)" >> "\$LOGFILE"
		echo " - \$i " >> "\$LOGFILE"
		\$i 2>&1 >> "\$LOGFILE"
	fi
done

EOF

	if [ "$?" -ne "0" ]; then
		ShowFailed "Unable to create script processor!"
		exitcode=8
		return
	fi

	chmod +x "$autorun_processor_pathfile"

	}

BackupExistingAutorun()
	{

	AUTORUN_LINK_PATHFILE="${DOM_mount_point}/${AUTORUN_FILE}"

	# copy original autorun.sh to backup location
	if [ -e "$AUTORUN_LINK_PATHFILE" ]; then
		# if an autorun.sh.old already exists in backup location, find a new name for it
		backup_pathfile="$autorun_processor_pathfile.prev"

		if [ -e "$backup_pathfile" ] ; then
			for ((acc=2; acc<=1000; acc++)) ; do
				[ ! -e "$backup_pathfile.$acc" ] && break
			done

			backup_pathfile="$backup_pathfile.$acc"
		fi

		cp "$AUTORUN_LINK_PATHFILE" "$backup_pathfile"

		if [ "$?" -eq "0" ]; then
			ShowSuccess "backed-up existing $AUTORUN_FILE to" "$backup_pathfile"
		else
			ShowFailed "Unable to backup existing ${AUTORUN_FILE}!"
			exitcode=9
		fi
	fi

	}

AddLinkToStartup()
	{

	ln -sf "$autorun_processor_pathfile" "$AUTORUN_LINK_PATHFILE"

	if [ "$?" -ne "0" ]; then
		ShowFailed "Unable to create symlink!"
		exitcode=10
	fi

	}

UnmountDOMPartition()
	{

	if [ "$NAS_DOM_FS" == "ubifs" ]; then
		umount "$DOM_mount_point"

		if [ "$?" -eq "0" ]; then
			ShowSuccess "unmounted UBIFS DOM partition" "$DOM_mount_point"
			mountflag=false
		else
			ShowFailed "Unable to unmount UBIFS DOM partition!"
			exitcode=11
		fi

		ubidetach -m "$NAS_DOM_PART"
	else
		umount "$DOM_mount_point"

		if [ "$?" -eq "0" ]; then
			ShowSuccess "unmounted EXT2 DOM partition" "$DOM_mount_point"
			mountflag=false
		else
			ShowFailed "Unable to unmount EXT2 DOM partition!"
			exitcode=11
		fi
	fi

	}

RemoveMountPoint()
	{

	[ -e "$DOM_mount_point" ] && rmdir "$DOM_mount_point"

	}

ShowResult()
	{

	ShowHeading "Result"

	if [ "$exitcode" -eq "0" ]; then
		ShowSuccess "Autorun successfully installed!"
	else
		ShowFailed "Autorun installation failed!"
	fi

	echo

	}

ShowSuccess()
	{

	ShowLogLine "√" "$1" "$2"

	}

ShowFailed()
	{

	ShowLogLine "X" "$1"

	}

ShowInfo()
	{

	ShowLogLine "*" "$1" "$2"

	}

ShowLogLine()
	{

	# $1 = pass/fail symbol
	# $2 = parameter
	# $3 = value (optional)

	if [ ! -z "$3" ]; then
		printf " %-1s %-33s: %s\n" "$1" "$2" "$3"
	else
		printf " %-1s %-33s\n" "$1" "$2"
	fi

	}

ShowHeading()
	{

	# $1 = message

	[ -z "$1" ] && return 1

	linechar='-'
	current_length=$((${#1}))
	linewidth=69
	left=3
	right=$(($linewidth-$current_length-$left-4))

	printf "\n%${left}s" | tr ' ' "$linechar"; echo -n "| $1 |"; printf "%${right}s\n" | tr ' ' "$linechar"

	}

Init
[ "$exitcode" -eq "0" ] && FindDOMPartition
[ "$exitcode" -eq "0" ] && CreateMountPoint
[ "$exitcode" -eq "0" ] && MountDOMPartition
[ "$exitcode" -eq "0" ] && ConfirmDOMPartition
[ "$exitcode" -eq "0" ] && CreateScriptStore
[ "$exitcode" -eq "0" ] && CreateProcessor
[ "$exitcode" -eq "0" ] && BackupExistingAutorun
[ "$exitcode" -eq "0" ] && AddLinkToStartup
[ "$mountflag" == "true" ] && UnmountDOMPartition
RemoveMountPoint
ShowResult
exit $exicode
