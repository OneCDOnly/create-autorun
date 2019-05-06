#!/usr/bin/env bash
############################################################################
# create-atorun.sh - (C)opyright 2017-2018 OneCD [one.cd.only@gmail.com]
#
# Create an autorun environment suited to this model QNAP NAS.
# Tested on QTS 4.2.6 #20180829 running on a QNAP TS-559 Pro+.
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

    if [[ ! -e /etc/init.d/functions ]]; then
        ShowError "QTS functions missing. Is this a QNAP NAS?"
        exit 1
    fi

    # include QNAP functions
    . /etc/init.d/functions

    FindDefVol

    local SCRIPT_FILE=create-autorun.sh
    local SCRIPT_NAME=${SCRIPT_FILE%.*}
    local SCRIPT_VERSION=190506

    local NAS_BOOT_PATHFILE=/etc/default_config/BOOT.conf
    local NAS_PLATFORM_PATHFILE=/etc/platform.conf
    local NAS_CONFIG_PATHFILE=/etc/config/uLinux.conf

    NAS_ARC=$(<"$NAS_BOOT_PATHFILE")
    NAS_MODEL=$(getcfg 'System' 'Model' -f $NAS_CONFIG_PATHFILE)
    NAS_DOM_NODE=$(getcfg 'CONFIG STORAGE' 'DEVICE_NODE' -f $NAS_PLATFORM_PATHFILE)
    NAS_DOM_PART=$(getcfg 'CONFIG STORAGE' 'FS_ACTIVE_PARTITION' -f $NAS_PLATFORM_PATHFILE)
    NAS_DOM_FS=$(getcfg 'CONFIG STORAGE' 'FS_TYPE' -f $NAS_PLATFORM_PATHFILE)

    echo -e "$(ColourTextBrightWhite "$SCRIPT_FILE") ($SCRIPT_VERSION)\n"

    ShowInfo "NAS model: $NAS_MODEL ($(getcfg 'MISC' 'DISPLAY_NAME' -d 'display name unknown' -f $NAS_PLATFORM_PATHFILE))"
    ShowInfo "QTS version: $(getcfg 'System' 'Version') #$(getcfg 'System' 'Build Number' -f $NAS_CONFIG_PATHFILE)"
    ShowInfo "default volume: $DEF_VOLMP"
    echo

    AUTORUN_FILE=autorun.sh
    AUTORUN_PATH=$DEF_VOLMP/.system/autorun
    SCRIPT_STORE_PATH=$AUTORUN_PATH/scripts
    MOUNT_BASE_PATH=/tmp/$SCRIPT_NAME

    exitcode=0

    }

FindDOMPartition()
    {

    [[ $exitcode -gt 0 ]] && return

    if [[ -n $NAS_DOM_NODE ]]; then
        DOM_partition=${NAS_DOM_NODE}${NAS_DOM_PART}
    else
        if [[ -e /sbin/hal_app ]]; then
            DOM_partition=$(/sbin/hal_app --get_boot_pd port_id=0)
            if [[ $NAS_MODEL = TS-X28A ]]; then
                DOM_partition+=5
            else
                DOM_partition+=6
            fi
        elif [[ $NAS_ARC = TS-NASARM ]]; then
            DOM_partition=/dev/mtdblock5
        else
            DOM_partition=/dev/sdx6
        fi
    fi

    if [[ -n $DOM_partition ]]; then
        ShowDone "DOM partition found ($DOM_partition)"
    else
        ShowError 'unable to find the DOM partition!'
        exitcode=2
    fi

    }

CreateMountPoint()
    {

    [[ $exitcode -gt 0 ]] && return

    DOM_mount_point=$(mktemp -d $MOUNT_BASE_PATH.XXXXXX 2> /dev/null)

    if [[ $? -ne 0 ]]; then
        ShowError "unable to create a DOM mount-point! [$MOUNT_BASE_PATH.XXXXXX]"
        exitcode=3
    fi

    }

MountDOMPartition()
    {

    [[ $exitcode -gt 0 ]] && return

    local mount_dev=''
    local result_msg=''

    if [[ $NAS_DOM_FS = ubifs ]]; then
        result_msg=$(/sbin/ubiattach -m "$NAS_DOM_PART" -d 2 2>&1)

        if [[ $? -eq 0 ]]; then
            ShowDone "ubiattached DOM partition ($NAS_DOM_PART)"
            mount_type=ubifs
            mount_dev=ubi2:config
        else
            ShowError "unable to ubiattach! [$result_msg]"
            mount_type=ext4
            mount_dev=/dev/mmcblk0p7
            ShowInfo "will try as ($mount_type) instead"
        fi
    else
        mount_type=ext2
        mount_dev=$DOM_partition
    fi

    result_msg=$(/bin/mount -t $mount_type $mount_dev $DOM_mount_point 2>&1)

    if [[ $? -eq 0 ]]; then
        ShowDone "mounted ($mount_type) DOM partition at [$DOM_mount_point]"
        mount_flag=true
    else
        ShowError "unable to mount ($mount_type) DOM partition ($mount_dev)! Error: [$result_msg]"
        mount_flag=false
        exitcode=4
    fi

    }

ConfirmDOMPartition()
    {

    [[ $exitcode -gt 0 ]] && return

    # look for a known file
    if [[ ! -e ${DOM_mount_point}/uLinux.conf ]]; then
        ShowError 'DOM tag-file was not found!'
        exitcode=6
    fi

    }

CreateScriptStore()
    {

    [[ $exitcode -gt 0 ]] && return

    mkdir -p "$SCRIPT_STORE_PATH" 2> /dev/null

    if [[ $? -ne 0 ]]; then
        ShowError "unable to create script store! ($SCRIPT_STORE_PATH)"
        exitcode=7
    fi

    }

CreateProcessor()
    {

    [[ $exitcode -gt 0 ]] && return

    # write the script directory processor to disk.
    autorun_processor_pathfile="$AUTORUN_PATH/$AUTORUN_FILE"

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
        ShowError "unable to create script processor! [$autorun_processor_pathfile]"
        exitcode=8
        return
    fi

    chmod +x "$autorun_processor_pathfile"

    }

BackupExistingAutorun()
    {

    [[ $exitcode -gt 0 ]] && return

    AUTORUN_LINK_PATHFILE="${DOM_mount_point}/${AUTORUN_FILE}"

    # copy original [autorun.sh] to backup location
    if [[ -e $AUTORUN_LINK_PATHFILE ]]; then
        # if an [autorun.sh.old] already exists in backup location, find a new name for it
        backup_pathfile="$autorun_processor_pathfile.prev"

        if [[ -e $backup_pathfile ]] ; then
            for ((acc=2; acc<=1000; acc++)) ; do
                [[ ! -e $backup_pathfile.$acc ]] && break
            done

            backup_pathfile="$backup_pathfile.$acc"
        fi

        cp "$AUTORUN_LINK_PATHFILE" "$backup_pathfile"

        if [[ $? -eq 0 ]]; then
            ShowDone "backed-up existing [$AUTORUN_FILE] to [$backup_pathfile]"
        else
            ShowError "unable to backup existing file! [$AUTORUN_FILE]"
            exitcode=9
        fi
    fi

    }

AddLinkToStartup()
    {

    [[ $exitcode -gt 0 ]] && return

    ln -sf "$autorun_processor_pathfile" "$AUTORUN_LINK_PATHFILE"

    if [[ $? -ne 0 ]]; then
        ShowError 'unable to create symlink!'
        exitcode=10
    fi

    }

UnmountDOMPartition()
    {

    [[ $mount_flag = false ]] && return

    local result_msg=''

    result_msg=$(/bin/umount "$DOM_mount_point" 2>&1)

    if [[ $? -eq 0 ]]; then
        ShowDone "unmounted ($mount_type) DOM partition" "$DOM_mount_point"
        mount_flag=false
    else
        ShowError "unable to unmount ($mount_type) DOM partition! Error: [$result_msg]"
        exitcode=11
    fi

    [[ $NAS_DOM_FS = ubifs ]] && /sbin/ubidetach -m "$NAS_DOM_PART"

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
        ShowDone '[autorun.sh] successfully created!'
        ShowInfo "place your startup scripts in [$SCRIPT_STORE_PATH]"
    else
        ShowError '[autorun.sh] creation failed!'
    fi

    echo

    }

ShowInfo()
    {

    ShowLogLine_update "$(ColourTextBrightOrange info)" "$1"

    }

ShowDone()
    {

    ShowLogLine_update "$(ColourTextBrightGreen done)" "$1"

    }

ShowError()
    {

    local buffer="$1"
    local capitalised="$(tr "[a-z]" "[A-Z]" <<< ${buffer:0:1})${buffer:1}"

    ShowLogLine_update "$(ColourTextBrightRed fail)" "$capitalised"

    }

ShowLogLine_update()
    {

    # updates the previous message

    # $1 = pass/fail
    # $2 = message

    new_message=$(printf "[ %-10s ] %s" "$1" "$2")

    if [[ $new_message != $previous_msg ]]; then
        previous_length=$((${#previous_msg}+1))
        new_length=$((${#new_message}+1))

        # jump to start of line, print new msg
        strbuffer=$(echo -en "\r$new_message ")

        # if new msg is shorter then add spaces to end to cover previous msg
        [[ $new_length -lt $previous_length ]] && { appended_length=$(($new_length-$previous_length)); strbuffer+=$(printf "%${appended_length}s") ;}

        echo "$strbuffer"
    fi

    return 0

    }

ColourTextBrightGreen()
    {

    echo -en '\033[1;32m'"$(PrintResetColours "$1")"

    }

ColourTextBrightOrange()
    {

    echo -en '\033[1;38;5;214m'"$(PrintResetColours "$1")"

    }

ColourTextBrightRed()
    {

    echo -en '\033[1;31m'"$(PrintResetColours "$1")"

    }

ColourTextBrightWhite()
    {

    echo -en '\033[1;97m'"$(PrintResetColours "$1")"

    }

PrintResetColours()
    {

    echo -en "$1"'\033[0m'

    }

Init
FindDOMPartition
CreateMountPoint
MountDOMPartition
ConfirmDOMPartition
CreateScriptStore
CreateProcessor
BackupExistingAutorun
AddLinkToStartup
UnmountDOMPartition
RemoveMountPoint
ShowResult

exit "$exitcode"
