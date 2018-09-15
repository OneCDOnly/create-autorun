#!/bin/bash
#
# create-autorun.sh
#
# This version was coded on 2017/01/16 by OneCD and you can blame him if it all goes horribly wrong. ;)
#
# Create an autorun environment suited to this model NAS.
#
# Tested on QTS 4.2.2 #20161214 running on my QNAP TS-569 Pro.

Init()
	{

	# setup envars.

	# include QNAP functions
	. "/etc/init.d/functions"

	FindDefVol

	local script_file="create-autorun.sh"
	script_name="${script_file%.*}"
	autorun_file="autorun.sh"
	local NAS_CONFIG_PATHFILE="/etc/config/uLinux.conf"
	local NAS_PLATFORM_PATHFILE="/etc/platform.conf"

	local NAS_MODEL=$(getcfg -f "$NAS_CONFIG_PATHFILE" "System" "Model")
	local NAS_DISPLAY_NAME=$(getcfg -f "$NAS_PLATFORM_PATHFILE" "MISC" "DISPLAY_NAME")
	local QTS_VERSION=$(getcfg -f "$NAS_CONFIG_PATHFILE" "System" "Version")
	local QTS_BUILD=$(getcfg -f "$NAS_CONFIG_PATHFILE" "System" "Build Number")
	NAS_SYSTEM_DEVICE=$(getcfg -f "$NAS_CONFIG_PATHFILE" "System" "System Device")

	ShowHeading "Details"
	ShowInfo "NAS model" "$NAS_MODEL ($NAS_DISPLAY_NAME)"
	ShowInfo "QTS version" "$QTS_VERSION #$QTS_BUILD"
	ShowInfo "default volume" "$DEF_VOLMP"

	ShowHeading "Log"

	autorun_path="${DEF_VOLMP}/.system/autorun"
	script_store_path="${autorun_path}/scripts"

	DOM_partition_size_known="8896512"

	exitcode=0

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
		printf " %-1s %-27s: %s\n" "$1" "$2" "$3"
	else
		printf " %-1s %-27s\n" "$1" "$2"
	fi

	}

ShowHeading()
	{

	# $1 = message

	[ -z "$1" ] && return 1

	linechar='-'
	current_length=$((${#1}))
	linewidth=60
	left=3
	right=$(($linewidth-$current_length-$left-4))

	printf "\n%${left}s" | tr ' ' "$linechar"; echo -n "| $1 |"; printf "%${right}s\n" | tr ' ' "$linechar"

	}

FindDOM()
	{

	# ensure that QTS System Device points to DOM.

	parted -s "$NAS_SYSTEM_DEVICE" print | grep -F "USB DISK MODULE" > /dev/null

	if [ "$?" -eq "0" ]; then
		ShowSuccess "DOM device found" "$NAS_SYSTEM_DEVICE"
	else
		ShowFailed "Unable to confirm that DOM device is present!"
		exitcode=1
	fi

	}

FindDOMPartition()
	{

	# this only works on HAL models.
	#local drive="$(/sbin/hal_app --get_boot_pd port_id=0)"
	#local partition="${DOM_drive}6"

	# hopefully, this is more universal.
	# list all drives and partitions, remove those that look RAID related, then grab the first field in the last row.
	#local drive=$(blkid | grep -vF "/md" | tail -n1)
	#DOM_partition=${drive/%\:*/}

	# take 3!
	DOM_partition="${NAS_SYSTEM_DEVICE}$(parted -s "$NAS_SYSTEM_DEVICE" print | grep "logical" | tail -n1 | cut -d' ' -f2)"

	if [ "$DOM_partition" ]; then
		ShowSuccess "DOM partition found" "$DOM_partition"
	else
		ShowFailed "Unable to find the DOM partition!"
		exitcode=2
	fi

	}

CreateMountPoint()
	{

	DOM_mount_point=$(mktemp -d "/dev/shm/${script_name}.XXXXXX" 2> /dev/null)

	if [ "$?" -eq "0" ]; then
		ShowSuccess "created new mount-point at" "$DOM_mount_point"
	else
		ShowFailed "Unable to create a DOM mount-point!"
		exitcode=3
	fi

	}

MountDOMPartition()
	{

	mountflag=false
	mount "$DOM_partition" "$DOM_mount_point"

	if [ "$?" -eq "0" ]; then
		ShowSuccess "mounted DOM partition at" "$DOM_mount_point"
		mountflag=true
	else
		ShowFailed "Unable to mount the DOM partition!"
		exitcode=4
	fi

	}

ConfirmDOMPartition()
	{

	# check DOM partition size
	partition_size=$(lsblk --bytes --output SIZE --noheadings "$DOM_partition")

	if [ "$partition_size" -eq "$DOM_partition_size_known" ]; then
		ShowSuccess "partition size is correct" "$partition_size bytes"
	else
		ShowFailed "DOM partition size is incorrect! (expected [$DOM_partition_size_known] but found [$partition_size]"
		exitcode=5
		return
	fi

	# look for a known file
	DOM_file_tag="${DOM_mount_point}/uLinux.conf"

	if [ -e "$DOM_file_tag" ]; then
		ShowSuccess "DOM tag-file was found" "$DOM_file_tag"
	else
		ShowFailed "DOM tag-file was not found!"
		exitcode=6
	fi

	}

CreateScriptStore()
	{

	mkdir -p "$script_store_path" 2> /dev/null

	if [ "$?" -eq "0" ]; then
		ShowSuccess "created script store" "$script_store_path"
	else
		ShowFailed "Unable to create script store!"
		exitcode=7
	fi

	}

WriteProcessor()
	{

	# write the script directory processor to disk.
	autorun_processor_pathfile="${autorun_path}/${autorun_file}"

	cat > "$autorun_processor_pathfile" << EOF
#!/bin/bash

autorun_path="$autorun_path"
script_store_path="$script_store_path"
logfile="/var/log/autorun.log"

echo "\$(date) ----- running autorun.sh -----" >> "\$logfile"

for i in \${script_store_path}/* ; do
	if [[ -x \$i ]] ; then
		echo -n "\$(date)" >> "\$logfile"
		echo " - \$i " >> "\$logfile"
		\$i 2>&1 >> "\$logfile"
	fi
done

EOF

	if [ "$?" -eq "0" ]; then
		ShowSuccess "created script processor" "$autorun_processor_pathfile"
	else
		ShowFailed "Unable to create script processor!"
		exitcode=8
		return
	fi

	chmod +x "$autorun_processor_pathfile"

	}

AddLinkToStartup()
	{

	local autorun_link_pathfile="${DOM_mount_point}/${autorun_file}"

	[ -e "$autorun_link_pathfile" ] && cp "$autorun_link_pathfile" "$autorun_processor_pathfile".old
	ln -sf "$autorun_processor_pathfile" "$autorun_link_pathfile"

	if [ "$?" -eq "0" ]; then
		ShowSuccess "created autorun symlink to" "$autorun_processor_pathfile"
	else
		ShowFailed "Unable to create symlink!"
		exitcode=9
	fi

	}

UnmountDOMPartition()
	{

	umount "$DOM_mount_point"

	if [ "$?" -eq "0" ]; then
		ShowSuccess "unmounted DOM partition" "$DOM_mount_point"
		mountflag=false
	else
		ShowFailed "Unable to unmount DOM partition!"
		exitcode=10
	fi

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

Init
[ "$exitcode" -eq "0" ] && FindDOM
[ "$exitcode" -eq "0" ] && FindDOMPartition
[ "$exitcode" -eq "0" ] && CreateMountPoint
[ "$exitcode" -eq "0" ] && MountDOMPartition
[ "$exitcode" -eq "0" ] && ConfirmDOMPartition
[ "$exitcode" -eq "0" ] && CreateScriptStore
[ "$exitcode" -eq "0" ] && WriteProcessor
[ "$exitcode" -eq "0" ] && AddLinkToStartup
[ "$mountflag" == "true" ] && UnmountDOMPartition
ShowResult
exit $exicode
