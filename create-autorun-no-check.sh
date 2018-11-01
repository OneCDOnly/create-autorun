#!/usr/bin/env bash
############################################################################
# create-atorun.sh - (C)opyright 2017-2018 OneCD [one.cd.only@gmail.com]
#
# Create an autorun environment suited to this model QNAP NAS.
# Tested on QTS 4.2.6 #20180711 running on a QNAP TS-559 Pro+.
#
# For more info: [https://forum.qnap.com/viewtopic.php?f=45&t=130345]
#
# Project source: [https://github.com/OneCDOnly/create-autorun]
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see http://www.gnu.org/licenses/.
############################################################################

Init()
    {

    # include QNAP functions
    . /etc/init.d/functions

    FindDefVol

    local SCRIPT_FILE='create-autorun.sh'
    local SCRIPT_NAME="${SCRIPT_FILE%.*}"
    local SCRIPT_VERSION='181102'

    local NAS_BOOT_PATHFILE='/etc/default_config/BOOT.conf'
    local NAS_PLATFORM_PATHFILE='/etc/platform.conf'
    local NAS_CONFIG_PATHFILE='/etc/config/uLinux.conf'

    NAS_ARC=$(<"$NAS_BOOT_PATHFILE")
    local NAS_MODEL=$(getcfg -f "$NAS_CONFIG_PATHFILE" 'System' 'Model')
    local NAS_MODEL_DISPLAY=$(getcfg -f "$NAS_PLATFORM_PATHFILE" 'MISC' 'DISPLAY_NAME')
    local QTS_VERSION=$(getcfg -f "$NAS_CONFIG_PATHFILE" 'System' 'Version')
    local QTS_BUILD=$(getcfg -f "$NAS_CONFIG_PATHFILE" 'System' 'Build Number')
    NAS_DOM_NODE=$(getcfg -f "$NAS_PLATFORM_PATHFILE" 'CONFIG STORAGE' 'DEVICE_NODE')
    NAS_DOM_PART=$(getcfg -f "$NAS_PLATFORM_PATHFILE" 'CONFIG STORAGE' 'FS_ACTIVE_PARTITION')
    NAS_DOM_FS=$(getcfg -f "$NAS_PLATFORM_PATHFILE" 'CONFIG STORAGE' 'FS_TYPE')

    echo
    ShowInfo 'script version' "$SCRIPT_VERSION"
    ShowInfo 'NAS model' "$NAS_MODEL ($NAS_MODEL_DISPLAY)"
    ShowInfo 'QTS version' "$QTS_VERSION #$QTS_BUILD"
    ShowInfo 'default volume' "$DEF_VOLMP"
    echo

    AUTORUN_FILE='autorun.sh'
    AUTORUN_PATH="${DEF_VOLMP}/.system/autorun"
    SCRIPT_STORE_PATH="${AUTORUN_PATH}/scripts"
    MOUNT_BASE_PATH="/tmp/$SCRIPT_NAME"

    exitcode=0

    }

FindDOMPartition()
    {

    [[ $exitcode -gt 0 ]] && return

    if [[ -n $NAS_DOM_NODE ]]; then
        DOM_partition="${NAS_DOM_NODE}${NAS_DOM_PART}"
    else
        if [[ -e /sbin/hal_app ]]; then
            DOM_partition="$(/sbin/hal_app --get_boot_pd port_id=0)6"
        elif [[ $NAS_ARC = 'TS-NASARM' ]]; then
            DOM_partition='/dev/mtdblock5'
        else
            DOM_partition='/dev/sdx6'
        fi
    fi

    if [[ -n $DOM_partition ]]; then
        ShowSuccess 'DOM partition found' "$DOM_partition"
    else
        ShowFailed 'Unable to find the DOM partition!'
        exitcode=2
    fi

    }

CreateMountPoint()
    {

    [[ $exitcode -gt 0 ]] && return

    DOM_mount_point=$(mktemp -d "${MOUNT_BASE_PATH}.XXXXXX" 2> /dev/null)

    if [[ $? -ne 0 ]]; then
        ShowFailed "Unable to create a DOM mount-point! (${MOUNT_BASE_PATH}.XXXXXX)"
        exitcode=3
    fi

    }

MountDOMPartition()
    {

    [[ $exitcode -gt 0 ]] && return

    local mount_dev=''
    local result=''
    local orig_result=''

    if [[ $NAS_DOM_FS = ubifs ]]; then
        ubiattach -m "$NAS_DOM_PART" -d 2 2> /dev/null
        mount_type=ubifs
        mount_dev='ubi2:config'
    else
        mount_type=ext2
        mount_dev="$DOM_partition"
    fi

    while true; do
        result=$(mount -t "$mount_type" "$mount_dev" "$DOM_mount_point" 2>&1)

        if [[ $? -eq 0 ]]; then
            ShowSuccess "mounted ($mount_type) DOM partition at" "$DOM_mount_point"
            mount_flag=true
            break
        else
            [[ -z $orig_result ]] && orig_result=$result

            if [[ $mount_type != ext4 ]]; then
                mount_type=ext4
                mount_dev='/dev/mmcblk0p7'
                continue
            else
                ShowFailed "Unable to mount ($mount_type) DOM partition ($mount_dev)! Error: [$orig_result]"
                mount_flag=false
                exitcode=4
                break
            fi
        fi
    done

    }

CreateScriptStore()
    {

    [[ $exitcode -gt 0 ]] && return

    mkdir -p "$SCRIPT_STORE_PATH" 2> /dev/null

    if [[ $? -ne 0 ]]; then
        ShowFailed "Unable to create script store! ($SCRIPT_STORE_PATH)"
        exitcode=7
    fi

    }

CreateProcessor()
    {

    [[ $exitcode -gt 0 ]] && return

    # write the script directory processor to disk.
    autorun_processor_pathfile="${AUTORUN_PATH}/${AUTORUN_FILE}"

    cat > "$autorun_processor_pathfile" << EOF
#!/usr/bin/env bash

AUTORUN_PATH="$AUTORUN_PATH"
SCRIPT_STORE_PATH="$SCRIPT_STORE_PATH"
LOGFILE='/var/log/autorun.log'

echo "\$(date) ----- running autorun.sh -----" >> "\$LOGFILE"

for i in \${SCRIPT_STORE_PATH}/*; do
    if [[ -x \$i ]]; then
        echo -n "\$(date)" >> "\$LOGFILE"
        echo " - \$i " >> "\$LOGFILE"
        \$i 2>&1 >> "\$LOGFILE"
    fi
done

EOF

    if [[ $? -ne 0 ]]; then
        ShowFailed "Unable to create script processor! ($autorun_processor_pathfile)"
        exitcode=8
        return
    fi

    chmod +x "$autorun_processor_pathfile"

    }

BackupExistingAutorun()
    {

    [[ $exitcode -gt 0 ]] && return

    AUTORUN_LINK_PATHFILE="${DOM_mount_point}/${AUTORUN_FILE}"

    # copy original autorun.sh to backup location
    if [[ -e $AUTORUN_LINK_PATHFILE ]]; then
        # if an autorun.sh.old already exists in backup location, find a new name for it
        backup_pathfile="$autorun_processor_pathfile.prev"

        if [[ -e $backup_pathfile ]] ; then
            for ((acc=2; acc<=1000; acc++)) ; do
                [[ ! -e $backup_pathfile.$acc ]] && break
            done

            backup_pathfile="$backup_pathfile.$acc"
        fi

        cp "$AUTORUN_LINK_PATHFILE" "$backup_pathfile"

        if [[ $? -eq 0 ]]; then
            ShowSuccess "backed-up existing $AUTORUN_FILE to" "$backup_pathfile"
        else
            ShowFailed "Unable to backup existing file! ($AUTORUN_FILE)"
            exitcode=9
        fi
    fi

    }

AddLinkToStartup()
    {

    [[ $exitcode -gt 0 ]] && return

    ln -sf "$autorun_processor_pathfile" "$AUTORUN_LINK_PATHFILE"

    if [[ $? -ne 0 ]]; then
        ShowFailed 'Unable to create symlink!'
        exitcode=10
    fi

    }

UnmountDOMPartition()
    {

    [[ $mount_flag = false ]] && return

    local result=''

    result=$(umount "$DOM_mount_point" 2>&1)

    if [[ $? -eq 0 ]]; then
        ShowSuccess "unmounted ($mount_type) DOM partition" "$DOM_mount_point"
        mount_flag=false
    else
        ShowFailed "Unable to unmount ($mount_type) DOM partition! Error: [$result]"
        exitcode=11
    fi

    [[ $NAS_DOM_FS = ubifs ]] && ubidetach -m "$NAS_DOM_PART"

    }

RemoveMountPoint()
    {

    [[ $mount_flag = true ]] && return
    [[ -e $DOM_mount_point ]] && rmdir "$DOM_mount_point"

    }

ShowResult()
    {

    echo

    if [[ $exitcode -eq 0 ]]; then
        ShowSuccess 'Autorun successfully installed!'
    else
        ShowFailed 'Autorun installation failed!'
    fi

    echo

    }

ShowSuccess()
    {

    ShowLogLine '√' "$1" "$2"

    }

ShowFailed()
    {

    ShowLogLine 'X' "$1"

    }

ShowInfo()
    {

    ShowLogLine '*' "$1" "$2"

    }

ShowLogLine()
    {

    # $1 = pass/fail symbol
    # $2 = parameter
    # $3 = value (optional)

    if [[ -n $3 ]]; then
        printf ' %-1s %-34s: %s\n' "$1" "$2" "$3"
    else
        printf ' %-1s %-34s\n' "$1" "$2"
    fi

    }

Init
FindDOMPartition
CreateMountPoint
MountDOMPartition
CreateScriptStore
CreateProcessor
BackupExistingAutorun
AddLinkToStartup
UnmountDOMPartition
RemoveMountPoint
ShowResult

exit "$exitcode"
