#!/bin/bash

NFS_HOST=$(mount | grep nfs | awk '{ print $1 }' | cut -d ":" -f 1)
NFS_HOST_PATH=$(mount | grep nfs | awk '{ print $1 }' | cut -d ":" -f 2)

host $NFS_HOST

if [[ $? -ne 0 ]]; then
    echo "NFS host $NFS_HOST doesn't exist!"
	# in case of lost mount point
	mount -a 
	exit 2
fi

MOUNT_POINT=$(mount | grep $NFS_HOST | awk '{ print $3 }')

NFS_IP=$(host $NFS_HOST | awk '{ print $4 }')
staleFlag=0

mount | grep "$NFS_IP"
if [[ $? -ne 0 ]]; then
	staleFlag=1
else 
	timeout 10 df -k
	if [[ $? -ne 0 ]]; then
		staleFlag=1
	fi
fi

if [[ staleFlag -ne 0 ]]; then 
    # This is a Stale NFS 
	# Kill process with open files on the NFS
	kill -9 $(timeout 10 lsof | egrep $MOUNT_POINT | awk '{print $2;}' | sort -fu)
	
	if [[ $? -ne 0 ]]; then
		# Kill process that have working directory on the NFS /mnt/nfs
		kill -9 $(for u in $(who | awk '{print $1;}' | sort -fu); do pwdx $(pgrep -u $u) |  grep $MOUNT_POINT  | awk -F: '{print $1;}' ; done)
	fi
		
	umount -fl $MOUNT_POINT
    mount -a 
else 
	exit 0
fi

# Re-check if that works, otherwise kill all users on the App instance 
NFS_IP=$(host $NFS_HOST | awk '{ print $4 }')
staleFlag=0

mount | grep "$NFS_IP"
if [[ $? -ne 0 ]]; then
	staleFlag=1
else 
	timeout 10 df -k
	if [[ $? -ne 0 ]]; then
		staleFlag=1
	fi
fi

if [[ staleFlag -ne 0 ]]; then 
    # This is still a Stale NFS and could not resolve
	# Kill all of the users
	for u in $(who | awk '{print $1;}' | sort -fu); do kill -9 $(pgrep -u $u) | awk -F: '{print $1;}' ;  done
			
	umount -fl $MOUNT_POINT
    mount -a 
else 
	exit 1	
fi

NFS_IP=$(host $NFS_HOST | awk '{ print $4 }')
staleFlag=0

mount | grep "$NFS_IP"
if [[ $? -ne 0 ]]; then
	staleFlag=1
else 
	timeout 10 df -k
	if [[ $? -ne 0 ]]; then
		staleFlag=1
	fi
fi

if [[ staleFlag -ne 0 ]]; then 
    # This is still a Stale NFS and could not resolve
	reboot
else 
	exit 3	
fi
