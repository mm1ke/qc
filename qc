#!/bin/bash

# Filename: qc
# Autor: Michael Mair-Keimberger (m DOT mairkeimberger AT gmail DOT com)
# Date: 081011

# Copyright (C) 2011  Michael Mair-Keimberger
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

# Discription:
# qc - qemu create script
# for creating new guests

# programs
QI="/usr/bin/qemu-img"
LN="/bin/ln"
CP="/bin/cp"
SED="/bin/sed"
LS="/bin/ls"
GREP="/bin/grep"
RM="/bin/rm"
DD="/bin/dd"
AWK="/bin/awk"
MKDIR="/bin/mkdir"
MOUNT="/bin/mount"
UMOUNT="/bin/umount"
LVCREATE="/sbin/lvcreate"
LVREMOVE="/sbin/lvremove"
LVS="/sbin/lvs"
RC_SERVICE="/sbin/rc-service"
KPARTX="/sbin/kpartx"
CUT="/bin/cut"
QEMUIMG="/usr/bin/qemu-img"
GZIP="/usr/bin/pigz" # WARNING: not gzip (pigz needs to be installed)

# default paths
VG_NAME="vms"
VG_PATH="/dev/${VG_NAME}"
IMAGE_NAME=""
IMAGE_SIZE="20G"
SNAPSHOTSIZE="5G"
DEFAULT_ROOT_PART="3"

DEFAULT_CONF_FILE="/etc/conf.d/kvm.init"
DEFAULT_INIT_FILE="/etc/init.d/kvm.init"
# TODO: Set proper path (usr/local/bin??)
GSS="/mnt/data/public/gss.sh"

#
# pause()
# pause with a custom string
#
pause(){
  read -p "$*"
}

#
# config_change()
# change settings in a config file
#
config_change(){
  # 1=${TARGET_KEY}, 2=${REPLACEMENT_VALUE}, 3=${CONFIG_FILE}
  ${SED} -i "s|\(${1} *= *\).*|\1\"${2}\"|" ${3}
  # remove leading "#" if there is one
  ${SED} -i "s/^#${1}/${1}/g" ${3}
}

#
# usage()
# usage of the script
#
usage(){
  echo "$0 copy			copy a exicting guest"
  echo "$0 new			creating a new guest"
  echo "$0 edit			edit guest config file"
  echo "$0 del			delete a guest image"
  echo "$0 convert [path]	convert a lvm2 image to qcow2"
  exit 1
}

#
# set_image_name()
# set the name of the image
#
set_image_name() {
  while true; do
    echo -n "Please set image name: "
    read input
    if [ -z ${input} ]; then
      echo "No name set. Please set one: "
    else
      if [ -e "${VG_PATH}/${input}" ]; then
	echo "Image exists already. Please choose a different name: "
      else
	IMAGE_NAME=${input}
	break
      fi
    fi
  done
}

#
# select_from()
# selector for various functions
#
select_from(){
  select SELECT_VAR in ${1}; do
    echo ${SELECT_VAR}
    break;
  done
}

#
# creat_lv()
# creates a new lvm partition
#
create_lv(){
  #${1}=size, ${2}=image_name, ${3}=vg_path
  ${LVCREATE} --size ${1} --name ${2} ${3}
  ${CP} ${DEFAULT_CONF_FILE} /etc/conf.d/kvm.${2}
  ${LN} -s ${DEFAULT_INIT_FILE} /etc/init.d/kvm.${2}
}

#
# info_changes()
# outputs the actual changes
#
info_changes(){
  echo " == QC is ready to start == "
  echo "DOING: ${doing}"
  echo "#===================#"
  case ${doing} in
    copy)
      echo " Image to copy: ${IMAGE_TO_COPY}"
      echo " New Guest Name: ${IMAGE_NAME}"
      (${GENTOO_TEST_INSTANCE}) && echo " This will be a Gentoo Test Instance"
      echo " New Guest will be stored under: ${VG_PATH}/${IMAGE_NAME}"
      ;;
    new)
      echo " New Guest Name: ${IMAGE_NAME}"
      echo " New Guest Size: ${IMAGE_SIZE}"
      echo " New Guest will be stored under: ${VG_PATH}/${IMAGE_NAME}"
      ;;
    del)
      echo " Guest to delete: ${RM_GUEST}"
      echo " + config: /etc/conf.d/kvm.${RM_GUEST}"
      echo " + init: /etc/init.d/kvm.${RM_GUEST}"
      ;;
    convert)
      echo " Image to convert ${CONV_GUEST}"
      echo " Full path of the image: ${QCOW2_PATH}/${QCOW2_NAME}.qcow2"
      (${compress_image} && echo " Image will be compressed"
      ;;
    esac
  echo "#===================#"
  pause "Press any key to continue (Cancel with CTRL+C) ..."
}

#
# edit_init_conf()
# set guest settings (in kvm.*)
#
edit_init_conf(){
  #${1}=vg_path, ${2}=image_name
  local new_mac=`printf 'DE:AD:CA:5E:%02X:%02X\n' $((RANDOM%256)) $((RANDOM%256))`
  config_change "VM_IMAGE" "${1}/${2}" "/etc/conf.d/kvm.${2}"
  config_change "VM_MAC_ADDRESS" "${new_mac}" "/etc/conf.d/kvm.${2}"
}

#
# edit_vm()
# set guest settings (in the guest)
#
edit_vm() {

  # mount vm
  TMP_DIR="${IMAGE_NAME}-${RANDOM}"
  ${MKDIR} /tmp/${TMP_DIR}
  ${KPARTX} -a "${VG_PATH}/${IMAGE_NAME}"
  
  # basically i suppose the / partition is the third partition
  # which could be either $name+p3 or $name+${DEFAULT_ROOT_PART}
  if [ -e /dev/mapper/${VG_NAME}-${IMAGE_NAME}p${DEFAULT_ROOT_PART} ]; then
    ${MOUNT} /dev/mapper/${VG_NAME}-${IMAGE_NAME}p${DEFAULT_ROOT_PART} /tmp/${TMP_DIR}
  elif [ -e /dev/mapper/${VG_NAME}-${IMAGE_NAME}${DEFAULT_ROOT_PART} ]; then
    ${MOUNT} /dev/mapper/${VG_NAME}-${IMAGE_NAME}${DEFAULT_ROOT_PART} /tmp/${TMP_DIR}
  else
    echo "*** WARNING! No root partition found. No settings will be made ***"
    ${RM} -rf /tmp/${TMP_DIR}
    ${KPARTX} -d "${VG_PATH}/${IMAGE_NAME}"
    return 1
  fi
    
  config_change "hostname" "${IMAGE_NAME}" "/tmp/${TMP_DIR}/etc/conf.d/hostname"  
  
  # change settings with gss
  if (${GENTOO_TEST_INSTANCE}); then
    [ -e ${GSS} ] && ${GSS} batchmode "/tmp/${TMP_DIR}/" gti
  fi

  # copy gss to root's home dir
  [ -e ${GSS} ] && ${CP} ${GSS} "/tmp/${TMP_DIR}/root/"
  
  #unmount vm
  ${UMOUNT} /tmp/${TMP_DIR}
  ${RM} -rf /tmp/${TMP_DIR}
  ${KPARTX} -d "${VG_PATH}/${IMAGE_NAME}"
}

#
# edit_config
# change a exiting config
#
edit_config(){
  IFS=$'\n'
  
  echo "Select the config file: "
  CFILE=$(select_from "`${LS} /etc/conf.d/|${GREP} "kvm.*"`")
  echo "You selected: ${CFILE}"
  
  VAR=$(select_from "`${GREP} < /etc/conf.d/${CFILE} -v ^\# | ${SED} -e "/^ *$/d"`")
  echo "You choose Variable ${VAR}"
  
  echo -n "Please give the new Variable: "
  read new_var
  
  config_change "`echo ${VAR}| ${CUT} -d '=' -f 1`" "${new_var}" "/etc/conf.d/${CFILE}"
  echo "Done"
  
  unset IFS
}

#
# delete_guest
# delete a guest image
#
delete_guest(){
  echo "Select the image to delete: "
  RM_GUEST=$(select_from "`${LS} ${VG_PATH}`")
  echo "You choose ${RM_GUEST}"
  
  echo "*** WARNING ***"
  info_changes del
  pause "You really want to delete ${RM_GUEST}? (Press Ctrl+C for cancel) "

  # stop the virtual guest
  ( ${RC_SERVICE} kvm.${RM_GUEST} status > /dev/null ) && ${RC_SERVICE} kvm.${RM_GUEST} stop
  ${RM} /etc/conf.d/kvm.${RM_GUEST} >/dev/null 2>&1 || echo "* File doesn't exist"
  ${RM} /etc/init.d/kvm.${RM_GUEST} >/dev/null 2>&1 || echo "* File doesn't exist"
  ${LVREMOVE} --force ${VG_PATH}/${RM_GUEST}
}

#
# new_guest()
# function for creating new virtual images
#
new_guest(){
  echo -n "Please set the image size [default is: ${IMAGE_SIZE}]: "
  read input
  [ -z ${input} ] || IMAGE_SIZE=${input}

  set_image_name
  info_changes new
  create_lv ${IMAGE_SIZE} ${IMAGE_NAME} ${VG_PATH}

  # modify config file
  edit_init_conf ${VG_PATH} ${IMAGE_NAME}
}

#
# copy_guest()
# function for coping virtual images
#
copy_guest(){
  echo "Select the image to copy:"
  CP_GUEST=$(select_from "`${LS} ${VG_PATH}`")
  echo "You choose ${CP_GUEST}"
  
  # set important vars
  GENTOO_TEST_INSTANCE="false"
  IMAGE_TO_COPY=${CP_GUEST}
  DEFAULT_CONF_FILE="/etc/conf.d/kvm.${IMAGE_TO_COPY}"
  
  # get the size of the original guest
  COPY_SIZE=`${LVS} ${VG_PATH}/${CP_GUEST} -o LV_SIZE --noheadings --units b --nosuffix`

  echo -n "Would you like to create an Gentoo Test Instance? [N/y]: "
  read input
  if [ "${input}" == "y" ]; then
    GENTOO_TEST_INSTANCE="true"
    GENTOO_TEST_INSTANCE_ID=0
    while ( ${LS} /etc/conf.d/|${GREP} kvm.gti${GENTOO_TEST_INSTANCE_ID} >/dev/null 2>&1 ); do
      let "GENTOO_TEST_INSTANCE_ID += 1"
      if [ ${GENTOO_TEST_INSTANCE_ID} -eq 9 ]; then
	echo "No free Gentoo Text Instance avaiable. Please delete one first"
	exit 1
      fi
    done
    echo "gti${GENTOO_TEST_INSTANCE_ID} is free."
    IMAGE_NAME="gti${GENTOO_TEST_INSTANCE_ID}"
  else
    # set image name
    set_image_name
  fi

  info_changes copy

  # great a new lvm partition
  create_lv "${COPY_SIZE}b" ${IMAGE_NAME} ${VG_PATH}

  # make sure the vm to copy is down or create snapshot
  if ( ${RC_SERVICE} kvm.${CP_GUEST} status > /dev/null ); then
    ${LVCREATE} --size ${SNAPSHOTSIZE} --snapshot --name ${CP_GUEST}-snapshot ${VG_PATH}/${CP_GUEST}
    IMAGE_TO_COPY="${CP_GUEST}-snapshot"
  fi
  
  # copy the image
  ${DD} if=${VG_PATH}/${IMAGE_TO_COPY} bs=4k conv=sync,noerror of=${VG_PATH}/${IMAGE_NAME}
  
  edit_init_conf ${VG_PATH} ${IMAGE_NAME}
  
  # remove snapshot if one exists
  [ -e "${VG_PATH}/${CP_GUEST}-snapshot" ] && ${LVREMOVE} --force ${VG_PATH}/${CP_GUEST}-snapshot
  
  # modify config file
  edit_vm ${IMAGE_NAME}
}

#
# convert_guest()
# convert a lvm partition to qcow2
#
convert_guest(){
  echo "Select the image to convert:"
  CONV_GUEST=$(select_from "`${LS} ${VG_PATH}`")
  while true; do
    echo -n "Set path, where the image should be stored [default: $QCOW2_PATH]: "
    read input
    if ! [ -z ${input} ]; then
      QCOW2_PATH=${input}
    else
      if ! [ -d "${QCOW2_PATH}" ]; then
	echo "Path dosent exists"
      else
	break
      fi
    fi
  done
  while true; do
    echo -n "Set Image name [default: ${CONV_GUEST}.qcow2]: "
    read input
    if [ -z ${input} ]; then
      QCOW2_NAME=${CONV_GUEST}
    else
      QCOW2_NAME=${input}
    fi
    if [ -e "${QCOW2_PATH}/${QCOW2_NAME}.qcow2" ]; then
      echo "File exists, choose different name"
    else
      break
    fi
  done
  
  echo -n "Would you like to compress the image? [N/y]: "
  read input
  if [ "${input}" == "y" ]; then
    compress_image=true
  fi
  
  info_changes convert
  
  echo -n "Converting..."
  ${QEMUIMG} convert -O qcow2 ${VG_PATH}/${CONV_GUEST} ${QCOW2_PATH}/${QCOW2_NAME}.qcow2  
  
  if (${compress_image}); then
    echo -n "Compressing..."
    ${GZIP} ${QCOW2_PATH}/${QCOW2_NAME}.qcow2 
  fi
}

# start of the script
if [ $# -lt 1 ]; then
  usage;
else
  doing="${1}"
  echo ">--------< QC >--------<"
  echo ">---< Qemu Control >---<"
  pause "Press any key to continue ..."
  echo "=============================="
  echo "Default LV is \"${VG_PATH}\" "
  case ${1} in
    copy)
      echo " < copy images > "
      copy_guest
      ;;
    new)
      echo " < create image > "
      new_guest
      ;;
    edit)
      echo " < edit config > "
      edit_config
      ;;
    del)
      echo " < delete guest > "
      delete_guest
      ;;
    convert)
      QCOW2_PATH=$2
      echo " < convert lvm to qcow2 > "
      convert_guest
      ;;
    *)
      usage
      ;;
   esac
fi