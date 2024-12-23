#!/usr/bin/env bash
####################################################################################
# create-autorun.sh
#
# Copyright (C) 2017-2024 OneCD - one.cd.only@gmail.com
#
# Create an autorun environment suited to this model QNAP NAS
#
# For more info: https://forum.qnap.com/viewtopic.php?f=45&t=130345
#
# Project source: https://github.com/OneCDOnly/create-autorun
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

readonly USER_ARGS_RAW=$*

Init()
    {

    local -r SCRIPT_FILE=create-autorun.sh
    local -r SCRIPT_VERSION=241219
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

    readonly NAS_ARC=$(</etc/default_config/BOOT.conf)
    readonly NAS_DEV_NODE=$(/sbin/getcfg 'CONFIG STORAGE' DEVICE_NODE -f /etc/platform.conf)
    readonly NAS_AUTORUN_PART=$(/sbin/getcfg 'CONFIG STORAGE' FS_ACTIVE_PARTITION -f /etc/platform.conf)
    readonly NAS_AUTORUN_FS=$(/sbin/getcfg 'CONFIG STORAGE' FS_TYPE -f /etc/platform.conf)
    readonly NAS_SYSTEM_DEV=$(/sbin/getcfg System 'System Device' -f /etc/config/uLinux.conf)

    readonly AUTORUN_FILE=autorun.sh
    readonly AUTORUN_PATH=$DEF_VOLMP/.system/autorun
    readonly SCRIPT_STORE_PATH=$AUTORUN_PATH/scripts
    readonly MOUNT_BASE_PATH=/tmp/${SCRIPT_FILE%.*}
    readonly AUTORUN_PATHFILE=$AUTORUN_PATH/$AUTORUN_FILE
    autorun_partition=''
    partition_mounted=false
    script_store_created=false

    echo "$(TextBrightWhite "$SCRIPT_FILE") v$SCRIPT_VERSION"
    ShowAsInfo "NAS model: $(get_display_name)"
    ShowAsInfo "$(GetQnapOS) version: $(/sbin/getcfg System Version) build $(/sbin/getcfg System 'Build Number')"
    ShowAsInfo "default volume: $DEF_VOLMP"

    }

DetermineAutorunPartitionLocation()
    {

    [[ $exitcode -eq 0 ]] || return

    if [[ -n $NAS_DEV_NODE ]]; then
		autorun_partition=${NAS_DEV_NODE}${NAS_AUTORUN_PART}
    else
        if [[ -e /sbin/hal_app ]]; then
            if IsQuTS; then
                autorun_partition=$NAS_SYSTEM_DEV
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
        elif [[ $NAS_ARC = TS-NASARM ]]; then
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

    mount_point=$(/bin/mktemp -d $MOUNT_BASE_PATH.XXXXXX 2>/dev/null)
    [[ $? -eq 0 ]] && return

    ShowAsError "unable to create a temporary mount-point ($MOUNT_BASE_PATH.XXXXXX)"
    exitcode=4

    }

MountAutorunPartition()
    {

    [[ $exitcode -eq 0 ]] || return

    local mount_dev=$autorun_partition
    local result_msg=''

    if [[ $NAS_AUTORUN_FS = ubifs ]]; then
        result_msg=$(/sbin/ubiattach -m "$NAS_AUTORUN_PART" -d 2 2>/dev/null)

        if [[ $? -eq 0 ]]; then
            ShowAsDone "ubiattached partition: $NAS_AUTORUN_PART"
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

    [[ ! -d $AUTORUN_PATH ]] && mkdir -p "$AUTORUN_PATH"

    if [[ -e $AUTORUN_PATHFILE ]]; then
        ShowAsSkip "'$AUTORUN_FILE' already exists: $AUTORUN_PATHFILE"
        return
    fi

    # write a new scripts directory processor to disk

    cat > "$AUTORUN_PATHFILE" << EOF
#!/usr/bin/env bash
# source: https://github.com/OneCDOnly/create-autorun

readonly LOGFILE=/var/log/autorun.log
f=''

echo "\$(date) -- begin processing --" >> "\$LOGFILE"

for f in $SCRIPT_STORE_PATH/*; do
    if [[ -x \$f ]]; then
        echo -n "\$(date)" >> "\$LOGFILE"
        echo " executing \$f ..." >> "\$LOGFILE"
        \$f >> "\$LOGFILE" 2>&1
    fi
done

echo "\$(date) -- end processing --" >> "\$LOGFILE"
EOF

    if [[ -e $AUTORUN_PATHFILE ]]; then
        ShowAsDone "created script processor: $AUTORUN_PATHFILE"
        chmod +x "$AUTORUN_PATHFILE"
        CreateScriptStore
        return
    fi

    ShowAsError "unable to create script processor $AUTORUN_PATHFILE"
    exitcode=7

    }

CreateScriptStore()
    {

    [[ $exitcode -eq 0 ]] || return

    if mkdir -p "$SCRIPT_STORE_PATH"; then
        ShowAsDone "created script store: $SCRIPT_STORE_PATH"
        script_store_created=true
        return 0
    fi

    ShowAsError "unable to create script store $SCRIPT_STORE_PATH"
    exitcode=8

    }

AddLinkFromAutorunPartition()
    {

    [[ $exitcode -eq 0 ]] || return

    if [[ -L "$mount_point/$AUTORUN_FILE" && $USER_ARGS_RAW != force ]]; then
        ShowAsSkip "symlink from autorun partition already exists and points to: $(/usr/bin/readlink "$mount_point/$AUTORUN_FILE")"
        return
	fi

	if ln -sf "$AUTORUN_PATHFILE" "$mount_point/$AUTORUN_FILE"; then
		ShowAsDone "created symlink from autorun partition to $AUTORUN_FILE"
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
            ShowAsDone "enabled '$AUTORUN_FILE' in $(GetQnapOS)"
        else
            ShowAsSkip "'$AUTORUN_FILE' is already enabled in $(GetQnapOS)"
        fi
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

    [[ $NAS_AUTORUN_FS = ubifs ]] && /sbin/ubidetach -m "$NAS_AUTORUN_PART" 2>/dev/null

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
    [[ $script_store_created = true ]] && ShowAsInfo "please place your startup scripts into: $SCRIPT_STORE_PATH"
    [[ -e $AUTORUN_PATHFILE ]] && ShowAsInfo "your '$AUTORUN_FILE' file is located at: $AUTORUN_PATHFILE"

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

    # Input:
    #   $1 = pass/fail
    #   $2 = message

    printf '%-10s: %s\n' "$1" "$2"

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

    /bin/grep -q zfs /proc/filesystems

    }

TextBrightGreen()
    {

    printf '\033[1;32m%s\033[0m' "$1"

    }

TextBrightYellow()
    {

    printf '\033[1;33m%s\033[0m' "$1"

    }

TextBrightOrange()
    {

    printf '\033[1;38;5;214m%s\033[0m' "$1"

    }

TextBrightRed()
    {

    printf '\033[1;31m%s\033[0m' "$1"

    }

TextBrightWhite()
    {

    printf '\033[1;97m%s\033[0m' "$1"

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
