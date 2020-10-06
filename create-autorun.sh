#!/usr/bin/env bash
####################################################################################
# create-autorun.sh
#
# Copyright (C) 2017-2020 OneCD [one.cd.only@gmail.com]
#
# Create an autorun environment suited to this model QNAP NAS.
#
# Tested on:
#  QTS 4.2.6 #20200821 running on a QNAP TS-559 Pro+
#  QTS 4.4.1 #20191204 running on a QNAP TS-832X-8
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
####################################################################################

Init()
    {

    local -r SCRIPT_FILE=create-autorun.sh
    local -r SCRIPT_VERSION=201007

    # include QNAP functions
    if [[ ! -e /etc/init.d/functions ]]; then
        ShowAsError "QTS functions missing (is this a QNAP NAS?): aborting ..."
        return 1
    else
        . /etc/init.d/functions
    fi

    FindDefVol

    local -r NAS_BOOT_PATHFILE=/etc/default_config/BOOT.conf
    local -r NAS_PLATFORM_PATHFILE=/etc/platform.conf

    readonly NAS_ARC=$(<"$NAS_BOOT_PATHFILE")
    readonly NAS_DOM_NODE=$(/sbin/getcfg 'CONFIG STORAGE' DEVICE_NODE -f $NAS_PLATFORM_PATHFILE)
    readonly NAS_DOM_PART=$(/sbin/getcfg 'CONFIG STORAGE' FS_ACTIVE_PARTITION -f $NAS_PLATFORM_PATHFILE)
    readonly NAS_DOM_FS=$(/sbin/getcfg 'CONFIG STORAGE' FS_TYPE -f $NAS_PLATFORM_PATHFILE)

    readonly AUTORUN_FILE=autorun.sh
    readonly AUTORUN_PATH=$DEF_VOLMP/.system/autorun
    readonly SCRIPT_STORE_PATH=$AUTORUN_PATH/scripts
    readonly MOUNT_BASE_PATH=/tmp/${SCRIPT_FILE%.*}
    readonly AUTORUN_PROCESSOR_PATHFILE=$AUTORUN_PATH/$AUTORUN_FILE

    echo "$(ColourTextBrightWhite "$SCRIPT_FILE") ($SCRIPT_VERSION)"
    echo
    ShowAsInfo "NAS model: $(get_display_name)"
    ShowAsInfo "QTS version: $(/sbin/getcfg System Version) #$(/sbin/getcfg System 'Build Number')"
    ShowAsInfo "default volume: $DEF_VOLMP"

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
            case $(/sbin/getcfg 'System' 'Model') in
                TS-X28A|TS-XA28A)
                    DOM_partition+=5
                    ;;
                *)
                    DOM_partition+=6
                    ;;
            esac
        elif [[ $NAS_ARC = TS-NASARM ]]; then
            DOM_partition=/dev/mtdblock5
        else
            DOM_partition=/dev/sdx6
        fi
    fi

    if [[ -n $DOM_partition ]]; then
        ShowAsDone "DOM partition found ($DOM_partition)"
    else
        ShowAsError 'unable to find the DOM partition!'
        exitcode=2
    fi

    }

CreateMountPoint()
    {

    [[ $exitcode -gt 0 ]] && return

    DOM_mount_point=$(mktemp -d $MOUNT_BASE_PATH.XXXXXX 2> /dev/null)

    if [[ $? -ne 0 ]]; then
        ShowAsError "unable to create a DOM mount-point! ($MOUNT_BASE_PATH.XXXXXX)"
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
            ShowAsDone "ubiattached DOM partition ($NAS_DOM_PART)"
            mount_type=ubifs
            mount_dev=ubi2:config
        else
            ShowAsError "unable to ubiattach! [$result_msg]"
            mount_type=ext4
            mount_dev=/dev/mmcblk0p7
            ShowAsInfo "will try as ($mount_type) instead"
        fi
    else
        mount_type=ext2
        mount_dev=$DOM_partition
    fi

    result_msg=$(/bin/mount -t $mount_type $mount_dev "$DOM_mount_point" 2>&1)

    if [[ $? -eq 0 ]]; then
        ShowAsDone "mounted ($mount_type) DOM partition at ($DOM_mount_point)"
        mount_flag=true
    else
        ShowAsError "unable to mount ($mount_type) DOM partition ($mount_dev)! [$result_msg]"
        mount_flag=false
        exitcode=4
    fi

    }

ConfirmDOMPartition()
    {

    [[ $exitcode -gt 0 ]] && return

    # look for a known file
    if [[ ! -e ${DOM_mount_point}/uLinux.conf ]]; then
        ShowAsError 'DOM tag-file was not found!'
        exitcode=6
    fi

    }

CreateScriptStore()
    {

    [[ $exitcode -gt 0 ]] && return

    mkdir -p "$SCRIPT_STORE_PATH" 2> /dev/null

    if [[ $? -ne 0 ]]; then
        ShowAsError "unable to create script store! ($SCRIPT_STORE_PATH)"
        exitcode=7
    fi

    }

CreateProcessor()
    {

    [[ $exitcode -gt 0 ]] && return

    # write the script directory processor to disk.

    cat > "$AUTORUN_PROCESSOR_PATHFILE" << EOF
#!/usr/bin/env bash

readonly AUTORUN_PATH=$AUTORUN_PATH
readonly SCRIPT_STORE_PATH=$SCRIPT_STORE_PATH
readonly LOGFILE=/var/log/autorun.log

echo "\$(date) -- autorun.sh is processing --" >> "\$LOGFILE"

for i in \$SCRIPT_STORE_PATH/*; do
    if [[ -x \$i ]]; then
        echo -n "\$(date)" >> "\$LOGFILE"
        echo " executing \$i ..." >> "\$LOGFILE"
        \$i 2>&1 >> "\$LOGFILE"
    fi
done
EOF

    if [[ $? -ne 0 ]]; then
        ShowAsError "unable to create script processor! ($AUTORUN_PROCESSOR_PATHFILE)"
        exitcode=8
        return
    fi

    chmod +x "$AUTORUN_PROCESSOR_PATHFILE"

    }

BackupExistingAutorun()
    {

    [[ $exitcode -gt 0 ]] && return

    DOM_LINKED_PATHFILE=$DOM_mount_point/$AUTORUN_FILE

    if [[ -e $DOM_LINKED_PATHFILE && ! -L $DOM_LINKED_PATHFILE ]]; then
        [[ -e $AUTORUN_PROCESSOR_PATHFILE ]] && Upshift "$AUTORUN_PROCESSOR_PATHFILE.prev"
        mv "$DOM_LINKED_PATHFILE" "$AUTORUN_PROCESSOR_PATHFILE.prev"
    fi

    }

Upshift()
    {

    # move specified existing filename by incrementing extension value (upshift extension)
    # if extension is not a number, then create new extension of '1' and copy file

    # $1 = pathfilename to upshift

    [[ -z $1 ]] && return 1
    [[ ! -e $1 ]] && return 1

    local ext=''
    local dest=''
    local rotate_limit=10

    # keep count of recursive calls
    local rec_limit=$((rotate_limit*2))
    local rec_count=0
    local rec_track_file=/tmp/${FUNCNAME[0]}.count
    [[ -e $rec_track_file ]] && rec_count=$(<"$rec_track_file")
    ((rec_count++)); [[ $rec_count -gt $rec_limit ]] && { echo "recursive limit reached!"; rm -f "$rec_track_file"; exit 1 ;}
    echo $rec_count > "$rec_track_file"

    ext=${1##*.}
    case $ext in
        *[!0-9]*)   # specified file extension is not a number so add number and copy it
            dest="$1.1"
            [[ -e $dest ]] && Upshift "$dest"
            cp "$1" "$dest"
            ;;
        *)          # extension IS a number, so move it if possible
            if [[ $ext -lt $((rotate_limit-1)) ]]; then
                ((ext++)); dest="${1%.*}.$ext"
                [[ -e $dest ]] && Upshift "$dest"
                mv "$1" "$dest"
            else
                rm "$1"
            fi
            ;;
    esac

    [[ -e $rec_track_file ]] && { rec_count=$(<"$rec_track_file"); ((rec_count--)); echo "$rec_count" > "$rec_track_file" ;}

    }

AddLinkToStartup()
    {

    [[ $exitcode -gt 0 ]] && return

    ln -sf "$AUTORUN_PROCESSOR_PATHFILE" "$DOM_LINKED_PATHFILE"

    if [[ $? -ne 0 ]]; then
        ShowAsError 'unable to create symlink!'
        exitcode=10
    fi

    }

UnmountDOMPartition()
    {

    [[ $mount_flag = false ]] && return

    local result_msg=''

    result_msg=$(/bin/umount "$DOM_mount_point" 2>&1)

    if [[ $? -eq 0 ]]; then
        ShowAsDone "unmounted ($mount_type) DOM partition" "$DOM_mount_point"
        mount_flag=false
    else
        ShowAsError "unable to unmount ($mount_type) DOM partition! [$result_msg]"
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

    if [[ $exitcode -eq 0 ]]; then
        ShowAsDone '(autorun.sh) successfully created!'
        ShowAsInfo "please place your startup scripts into ($SCRIPT_STORE_PATH)"
    else
        ShowAsError '(autorun.sh) creation failed!'
    fi

    }

ShowAsInfo()
    {

    WriteToDisplay.New "$(ColourTextBrightYellow info)" "$1"

    }

ShowAsDone()
    {

    WriteToDisplay.New "$(ColourTextBrightGreen 'done')" "$1"

    }

ShowAsError()
    {

    local buffer="$1"
    local capitalised="$(tr "[a-z]" "[A-Z]" <<< "${buffer:0:1}")${buffer:1}"

    WriteToDisplay.New "$(ColourTextBrightRed fail)" "$capitalised"

    }

WriteToDisplay.Wait()
    {

    # Writes a new message without newline (unless in debug mode)

    # input:
    #   $1 = pass/fail
    #   $2 = message

    previous_msg=$(printf "%-10s: %s" "$1" "$2")

    echo -n "$previous_msg"

    return 0

    }

WriteToDisplay.New()
    {

    # Updates the previous message

    # input:
    #   $1 = pass/fail
    #   $2 = message

    # output:
    #   stdout = overwrites previous message with updated message
    #   $previous_length
    #   $appended_length

    local new_message=''
    local strbuffer=''
    local new_length=0

    new_message=$(printf "%-10s: %s" "$1" "$2")

    if [[ $new_message != "$previous_msg" ]]; then
        previous_length=$((${#previous_msg}+1))
        new_length=$((${#new_message}+1))

        # jump to start of line, print new msg
        strbuffer=$(echo -en "\r$new_message ")

        # if new msg is shorter then add spaces to end to cover previous msg
        if [[ $new_length -lt $previous_length ]]; then
            appended_length=$((new_length-previous_length))
            strbuffer+=$(printf "%${appended_length}s")
        fi

        echo "$strbuffer"
    fi

    return 0

    }

ColourTextBrightGreen()
    {

    echo -en '\033[1;32m'"$(ColourReset "$1")"

    }

ColourTextBrightYellow()
    {

    echo -en '\033[1;33m'"$(ColourReset "$1")"

    }

ColourTextBrightOrange()
    {

    echo -en '\033[1;38;5;214m'"$(ColourReset "$1")"

    }

ColourTextBrightRed()
    {

    echo -en '\033[1;31m'"$(ColourReset "$1")"

    }

ColourTextBrightWhite()
    {

    echo -en '\033[1;97m'"$(ColourReset "$1")"

    }

ColourReset()
    {

    echo -en "$1"'\033[0m'

    }

Init || exit 1

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
echo

exit "$exitcode"
