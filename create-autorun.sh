#!/usr/bin/env bash
####################################################################################
# create-autorun.sh
#	Copyright 2017-2025 OneCD
#
# Contact:
#	one.cd.only@gmail.com
#
# Description:
#	Create an autorun environment suited to this model QNAP NAS
#
# Community forum:
#	https://community.qnap.com/t/script-create-autorun-sh/1096
#
# Project source:
#	https://github.com/OneCDOnly/create-autorun
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see http://www.gnu.org/licenses/
####################################################################################

set -o nounset -o pipefail
[[ -L /dev/fd ]] || ln -fns /proc/self/fd /dev/fd		# KLUDGE: `/dev/fd` isn't always created by QTS.
readonly r_user_args_raw=$*

Init()
	{

	local -r r_script_file=create-autorun.sh
	local -r r_script_version=250708
	exitcode=0

	# Include QNAP functions.

	if [[ -e /etc/init.d/functions ]]; then
		. /etc/init.d/functions
	else
		ShowAsError 'QNAP OS functions missing (is this a QNAP NAS?): aborting ...'
		exitcode=1
		return
	fi

	if [[ $EUID -ne 0 ]]; then
		ShowAsError 'this script must be run with superuser privileges. Try again as:'
		echo 'curl -skL https://git.io/create-autorun | sudo bash'
		exitcode=2
		return
	fi

	FindDefVol

	readonly r_nas_arc=$(</etc/default_config/BOOT.conf)
	readonly r_nas_dev_node=$(/sbin/getcfg 'CONFIG STORAGE' DEVICE_NODE -f /etc/platform.conf)
	readonly r_nas_autorun_part=$(/sbin/getcfg 'CONFIG STORAGE' FS_ACTIVE_PARTITION -f /etc/platform.conf)
	readonly r_nas_autorun_fs=$(/sbin/getcfg 'CONFIG STORAGE' FS_TYPE -f /etc/platform.conf)
	readonly r_nas_system_dev=$(/sbin/getcfg System 'System Device' -f /etc/config/uLinux.conf)

	readonly r_autorun_file=autorun.sh
	readonly r_autorun_path=$DEF_VOLMP/.system/autorun
	readonly r_script_store_path=$r_autorun_path/scripts
	readonly r_mount_base_path=/tmp/${r_script_file%.*}
	readonly r_autorun_pathfile=$r_autorun_path/$r_autorun_file
	autorun_partition=''
	partition_mounted=false
	script_store_created=false

	echo "$(TextBrightWhite "$r_script_file") v$r_script_version"
	ShowAsInfo "NAS model: $(get_display_name)"
	ShowAsInfo "$(GetQnapOS) version: $(/sbin/getcfg System Version) build $(/sbin/getcfg System 'Build Number')"
	ShowAsInfo "default volume: $DEF_VOLMP"

	}

DetermineAutorunPartitionLocation()
	{

	[[ $exitcode -eq 0 ]] || return

	if [[ -n $r_nas_dev_node ]]; then
		autorun_partition=${r_nas_dev_node}${r_nas_autorun_part}
	else
		if [[ -e /sbin/hal_app ]]; then
			if IsQuTS; then
				autorun_partition=$r_nas_system_dev
			else
				autorun_partition=$(/sbin/hal_app --get_boot_pd port_id=0)
			fi

			case $(/sbin/getcfg System Model) in
				TS-X16|TS-X28A|TS-XA28A|TS-X33|TS-X35EU)
					autorun_partition+=5
					;;
				*)
					autorun_partition+=6
			esac
		elif [[ $r_nas_arc = TS-NASARM ]]; then
			autorun_partition=/dev/mtdblock5
		else
			autorun_partition=/dev/sdx6
		fi
	fi

	if [[ -n $autorun_partition ]]; then
		ShowAsInfo "autorun partition should be: $autorun_partition"
		return
	fi

	ShowAsError 'unable to determine autorun partition location'
	exitcode=3

	}

CreateMountPoint()
	{

	[[ $exitcode -eq 0 ]] || return

	mount_point=$(/bin/mktemp -d $r_mount_base_path.XXXXXX 2>/dev/null)
	[[ $? -eq 0 ]] && return

	ShowAsError "unable to create a temporary mount-point: $r_mount_base_path.XXXXXX"
	exitcode=4

	}

MountAutorunPartition()
	{

	[[ $exitcode -eq 0 ]] || return

	local mount_dev=$autorun_partition
	local result_msg=''

	if [[ $r_nas_autorun_fs = ubifs ]]; then
		result_msg=$(/sbin/ubiattach -m "$r_nas_autorun_part" -d 2 2>/dev/null)

		if [[ $? -eq 0 ]]; then
			ShowAsDone "ubiattached partition: $r_nas_autorun_part"
			mount_type=ubifs
			mount_dev=ubi2:config
		else
			ShowAsSkip 'unable to ubiattach'
			mount_type=ext4
			mount_dev=/dev/mmcblk0p7
			ShowAsInfo "will try as: $mount_type instead"
		fi
	else
		mount_type=ext2
	fi

	result_msg=$(/bin/mount -t $mount_type $mount_dev "$mount_point" 2>&1)

	if [[ $? -eq 0 ]]; then
		ShowAsDone "mounted $mount_type device: $mount_dev -> $mount_point"
		partition_mounted=true
		return
	fi

	ShowAsError "unable to mount $mount_type device: $mount_dev '$result_msg'"
	partition_mounted=false
	exitcode=5

	}

ConfirmAutorunPartition()
	{

	[[ $exitcode -eq 0 ]] || return

	# Look for a known file to confirm this is the autorun partition.
	# Include an alternative file to confirm autorun partition on QuTS. https://github.com/OneCDOnly/create-autorun/issues/10

	local tag_file=''

	for tag_file in uLinux.conf .sys_update_time; do
		if [[ -e $mount_point/$tag_file ]]; then
			ShowAsInfo "confirmed partition tag-file exists: '$tag_file' ($(TextBrightGreen "we're in the right place"))"
			return 0
		fi
	done

	ShowAsInfo 'partition tag-file not found'
	return 0

	}

CreateProcessor()
	{

	[[ $exitcode -eq 0 ]] || return

	[[ ! -d $r_autorun_path ]] && mkdir -p "$r_autorun_path"

	if [[ -e $r_autorun_pathfile ]]; then
		ShowAsSkip "'$r_autorun_file' already exists: $r_autorun_pathfile"
		return
	fi

	# Write a new scripts directory processor to disk.

	cat > "$r_autorun_pathfile" << EOF
#!/usr/bin/env bash
# source: https://github.com/OneCDOnly/create-autorun

readonly r_logfile=/var/log/autorun.log
f=''

echo "\$(date) -- begin processing --" >> "\$r_logfile"

for f in $r_script_store_path/*; do
	if [[ -x \$f ]]; then
		echo -n "\$(date)" >> "\$r_logfile"
		echo " executing \$f ..." >> "\$r_logfile"
		\$f >> "\$r_logfile" 2>&1
	fi
done

echo "\$(date) -- end processing --" >> "\$r_logfile"
EOF

	if [[ -e $r_autorun_pathfile ]]; then
		ShowAsDone "created script processor: $r_autorun_pathfile"
		chmod +x "$r_autorun_pathfile"
		CreateScriptStore
		return
	fi

	ShowAsError "unable to create script processor: $r_autorun_pathfile"
	exitcode=7

	}

CreateScriptStore()
	{

	[[ $exitcode -eq 0 ]] || return

	if mkdir -p "$r_script_store_path"; then
		ShowAsDone "created script store: $r_script_store_path"
		script_store_created=true
		return 0
	fi

	ShowAsError "unable to create script store: $r_script_store_path"
	exitcode=8

	}

AddLinkFromAutorunPartition()
	{

	[[ $exitcode -eq 0 ]] || return

	if [[ -L "$mount_point/$r_autorun_file" && $r_user_args_raw != force ]]; then
		ShowAsSkip "symlink from autorun partition already exists and points to: $(/usr/bin/readlink "$mount_point/$r_autorun_file")"
		return
	fi

	if ln -sf "$r_autorun_pathfile" "$mount_point/$r_autorun_file"; then
		ShowAsDone "created symlink from autorun partition to: $r_autorun_file"
		return
	fi

	ShowAsError 'unable to create symlink'
	exitcode=9

	}

EnableAutorun()
	{

	[[ $exitcode -eq 0 ]] || return

	local fwvers=$(/sbin/getcfg System Version)

	if [[ ${fwvers//.} -ge 430 ]]; then
		if [[ $(/sbin/getcfg Misc Autorun) != TRUE ]]; then
			/sbin/setcfg Misc Autorun TRUE
			ShowAsDone "enabled '$r_autorun_file' in $(GetQnapOS)"
		else
			ShowAsSkip "'$r_autorun_file' is already enabled in $(GetQnapOS)"
		fi
	else
		ShowAsInfo "'$r_autorun_file' is always enabled in this firmware version"
	fi

	}

UnmountAutorunPartition()
	{

	[[ $partition_mounted = true ]] || return

	if /bin/umount "$mount_point"; then
		ShowAsDone "unmounted $mount_type autorun partition: $mount_point"
		partition_mounted=false
	else
		ShowAsError "unable to unmount $mount_type autorun partition: $mount_point"
		exitcode=10
	fi

	[[ $r_nas_autorun_fs = ubifs ]] && /sbin/ubidetach -m "$r_nas_autorun_part" 2>/dev/null

	}

RemoveMountPoint()
	{

	[[ $partition_mounted = false ]] || return
	[[ -e $mount_point ]] || return

	rmdir "$mount_point" && return

	ShowAsError "unable to remove temporary mount-point: $mount_point"
	exitcode=11

	}

ShowResult()
	{

	[[ $exitcode -eq 0 ]] || return
	[[ $script_store_created = true ]] && ShowAsInfo "please place your startup scripts into: $r_script_store_path"
	[[ -e $r_autorun_pathfile ]] && ShowAsInfo "your '$r_autorun_file' file is located at: $r_autorun_pathfile"

	}

ShowAsInfo()
	{

	Show "$(TextBrightYellow info)" "${1:-}"

	}

ShowAsSkip()
	{

	Show "$(TextBrightOrange skip)" "${1:-}"

	}

ShowAsDone()
	{

	Show "$(TextBrightGreen 'done')" "${1:-}"

	}

ShowAsError()
	{

	local buffer="${1:-}"

	Show "$(TextBrightRed fail)" "$(tr 'a-z' 'A-Z' <<< "${buffer:0:1}")${buffer:1}"

	}

Show()
	{

	# Inputs: (local)
	#	$1 = pass/fail
	#	$2 = message

	printf '%-10s: %s\n' "${1:-}" "${2:-}"

	}

GetQnapOS()
	{

	if IsQuTS; then
		printf 'QuTS hero'
	else
		printf QTS
	fi

	}

IsQuTS()
	{

	/bin/grep zfs /proc/filesystems

	} &> /dev/null

TextBrightGreen()
	{

	printf '\033[1;32m%s\033[0m' "${1:-}"

	}

TextBrightYellow()
	{

	printf '\033[1;33m%s\033[0m' "${1:-}"

	}

TextBrightOrange()
	{

	printf '\033[1;38;5;214m%s\033[0m' "${1:-}"

	}

TextBrightRed()
	{

	printf '\033[1;31m%s\033[0m' "${1:-}"

	}

TextBrightWhite()
	{

	printf '\033[1;97m%s\033[0m' "${1:-}"

	}

Init
DetermineAutorunPartitionLocation
CreateMountPoint
MountAutorunPartition
ConfirmAutorunPartition
CreateProcessor
AddLinkFromAutorunPartition
EnableAutorun
UnmountAutorunPartition
RemoveMountPoint
ShowResult

exit "$exitcode"
