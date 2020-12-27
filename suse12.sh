#!/bin/bash
#By default it will expand / file system unless argument is passed.

LOGDIR="/var/log/azure/disk_expand"
LOGFILE="$LOGDIR/output.log"

#check if log files and DIR are exsits else create them.
if [ -d $LOGDIR ]
then
	if [ -f $LOGFILE ]
	then 
		echo "==================================" >> $LOGFILE
		echo $(date) >> $LOGFILE
		echo "File and directory exsits , we are good to go" >> $LOGFILE
	else
		$(touch $LOGFILE)
		echo "==================================" >> $LOGFILE
		echo $(date) >> $LOGFILE
		echo "File was not there , we just created it" >> $LOGFILE
	fi
else
	$(mkdir $LOGDIR)
	$(touch $LOGFILE)
	echo "==================================" >> $LOGFILE
	echo $(date) >> $LOGFILE
	echo "We just created the log file and directory, proceed ..." >> $LOGFILE
fi
	
if [ "$#" -ne 1 ]
then
	echo "No arguments passed, assuming / file system" >> $LOGFILE
	mount_point='/'
else
	mount_point=$1
	echo "Below mount point is passed : $mount_point" >> $LOGFILE
fi


# Define the function to expand the disk, reference document : https://docs.microsoft.com/en-us/azure/virtual-machines/linux/resize-os-disk-gpt-partition#suse
function expand_gpt_os_disk()
{	
	disk_dev_name=$1
	mount_point_partition_number=$2
	mount_point_requested=$3
	echo "Expanding the partition $disk_dev_name$mount_point_partition_number of the mount point $mount_point_requested..." >> $LOGFILE
	echo "OS disk partition table before the expantion" >> $LOGFILE
	lsblk $disk_dev_name >> $LOGFILE
	echo -e "\n" >> $LOGFILE 
	echo "Installing growpart utility to help in the expantion" >> $LOGFILE
	zypper install -l -y growpart 1> /dev/null 
	echo "Running below command to expand : growpart $disk_dev_name $mount_point_partition_number " >> $LOGFILE
	growpart $disk_dev_name $mount_point_partition_number 1>> $LOGFILE
	echo "Done expanding the partition" >> $LOGFILE
	echo "OS disk partition table after the expantion" >> $LOGFILE
	lsblk $disk_dev_name >> $LOGFILE
	echo "Checking file system type of the $mount_point_requested" >> $LOGFILE
	mount_point_fs_type=$(df --output=fstype $mount_point_requested | awk 'NR==2{print $1}')
	echo "Root file system type is : $mount_point_fs_type" >> $LOGFILE
	if [ $mount_point_fs_type == "xfs" ]
	then
		echo "Running below command to expand file system: xfs_growfs $mount_point_requested" >> $LOGFILE
		xfs_growfs $mount_point_requested 1>> $LOGFILE
 		echo "The file system size after expandtion , running df -Th $mount_point_requested" >> $LOGFILE
		df -Th $mount_point_requested >> $LOGFILE
	elif [ $mount_point_fs_type == "ext4" ]
	then
		echo "Running below command to expand file system: resize2fs  $disk_dev_name$mount_point_partition_number" >> $LOGFILE
		resize2fs  $disk_dev_name$mount_point_partition_number 1>> $LOGFILE
		echo "The file system size after expandtion , running df -Th $mount_point_requested" >> $LOGFILE
		df -Th $mount_point_requested >> $LOGFILE
	else
		echo "This file system not supported by the script" >> $LOGFILE
		exit 2
	fi
}

# Needed checks before start 

function expantion_prerequisite()
{
    root_partition_name=$(df --output=source $mount_point | awk 'NR==2{print $1}')
    if [ $root_partition_name == *'mapper'* ]
    then
        echo "This is LVM setup, not supported on this script for SUSE, Manual intervension needed" >> $LOGFILE
        exit 1
    else
        echo "Starting checking below items:
            - OS disk name
            - OS disk size
            - root partition name and number
            - root partition size 
            - Disk label
        " >> $LOGFILE
        os_disk_name=${root_partition_name%?}
        partition_number=${root_partition_name: -1}
        disk_label=$(fdisk -l $os_disk_name | grep Disklabel | cut -d":" -f2)
        # Validate that partition size is less than disk size
        os_disk_size_metadata=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/storageProfile/osDisk/diskSizeGB?api-version=2020-09-01&format=text" )
        os_disk_size_withG=$(lsblk -n -o SIZE $os_disk_name | awk 'NR==1{print $1}')
        os_disk_size=${os_disk_size_withG%?}
        root_partition_sizewithG=$(lsblk -n -o SIZE $root_partition_name | awk 'NR==1{print $1}')
        root_partition_size=${root_partition_sizewithG%?}
        
        if [ $os_disk_size == $os_disk_size_metadata ]
        then
            #echo $os_disk_size ; echo $os_disk_size_metadata
            #echo $os_disk_name; echo $root_partition_name ; echo $partition_number ; echo $disk_label
            echo "OS disk size is the same as in the platform, moving to expantion process" >> $LOGFILE
            if [ $disk_label == "gpt" ]
            then
                echo "The disk label is GPT , switching to GPT expand disk function" >> $LOGFILE
                expand_gpt_os_disk $os_disk_name $partition_number $mount_point
            else
                echo "The disk label is MBR, running MBR expand function" >> $LOGFILE
                # TODO create MBR function
                exit 3
            fi

        else
            echo "Plesae make sure that the disk is expanded from portal and the VM is restarted" >> $LOGFILE
        fi
    fi
}




#starting main function
cloud_init_status=$(systemctl is-enabled cloud-init-local.service)
if [ $cloud_init_status == "enabled" ]
then
    echo "Cloud-init is exsits, leaving the expantion process to it" >> $LOGFILE
    echo "Cloud-init is exsits, leaving the expantion process to it"
    exit 0
else
    expantion_prerequisite
fi