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
# qc - qemu control script
# for creating, copy, compress and converting qemu guests

# programs
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
# WARNING: not gzip (pigz needs to be installed)
GZIP="/usr/bin/pigz"

# default paths
VG_NAME="vms"
VG_PATH="/dev/${VG_NAME}"
IMAGE_NAME=""
IMAGE_SIZE="20G"
SNAPSHOTSIZE="5G"
DEFAULT_ROOT_PART="3"

# config files
DEFAULT_CONF_FILE="/etc/conf.d/kvm.init"
DEFAULT_INIT_FILE="/etc/init.d/kvm.init"

#
# usage()
# usage of the script
#
usage(){
  echo "$0 copy			copy a exicting guest"
  echo "$0 new			creating a new guest"
  echo "$0 edit			edit guest config file"
  echo "$0 del			delete a guest image"
  echo "$0 convert [path]		convert a lvm2 image to qcow2"
  echo "$0 compress [path]		compress a lvm2 image"
  exit 1
}

#
# config_change()
# change settings in a config file
#
config_change(){
  # 1=${TARGET_KEY}, 2=${REPLACEMENT_VALUE}, 3=${CONFIG_FILE}
  ${SED} -i "s|\(${1} *= *\).*|\1\"${2}\"|" "${3}"
  # remove leading "#" if there is one
  ${SED} -i "s/^#${1}/${1}/g" "${3}"
}

#
# select_from()
# selector for various functions
#
select_from(){
  select SELECT_VAR in ${1}; do
    echo "${SELECT_VAR}"
    break;
  done
}

#
# set_image_name()
# set the name of the image
#
set_image_name() {
  # ${1} = path to check, ${2} = default image name
  while true; do
    echo -n "Please set image name [default: ${2}]: "
    read input
    if [ -z "${input}" ]; then
      IMAGE_NAME="${2}"
    else
      IMAGE_NAME="${input}"
    fi
    if [ -e "${1}/${IMAGE_NAME}" ]; then
      echo "File exists, choose different name"
    else
      break
    fi
  done
}

#
# set_image_path()
# sets the path for compress/convert 'ing
#
set_image_path() {
  # ${1} = default path (given over cmdline)
  while true; do
    echo -n "Set path, where the file should be stored [default: ${1}]: "
    read input
    if [ -z "${input}" ]; then
      IMAGE_PATH="${1}"
    else
      IMAGE_PATH="${input}"
    fi
    if ! [ -d "${IMAGE_PATH}" ]; then
      echo "Path dosen't exist, choose different one"
    else
      break
    fi
  done
}

#
# creat_lv()
# creates a new lvm partition
#
create_lv(){
  #${1}=size, ${2}=image_name, ${3}=vg_path
  ${LVCREATE} --size ${1} --name "${2}" "${3}"
  ${CP} "${DEFAULT_CONF_FILE}" /etc/conf.d/kvm.${2}
  ${LN} -s "${DEFAULT_INIT_FILE}" /etc/init.d/kvm.${2}
  
  local new_mac=`printf 'DE:AD:CA:5E:%02X:%02X\n' $((RANDOM%256)) $((RANDOM%256))`
  config_change "VM_IMAGE" "${3}/${2}" "/etc/conf.d/kvm.${2}"
  config_change "VM_MAC_ADDRESS" "${new_mac}" "/etc/conf.d/kvm.${2}"
}

#
# info_changes()
# outputs the actual changes
#
info_changes(){
  echo "#====================================#"
  echo "#        QC is ready to start        #"
  echo "Action: ${action}"
  echo "#====================================#"
  case ${action} in
    copy)
      echo " Image to copy: ${IMAGE_TO_COPY}"
      echo " New Guest Name: ${IMAGE_NAME}"
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
      echo " Full path of the image: ${IMAGE_PATH}/${IMAGE_NAME}.qcow2"
      (${compress_image}) && echo " Image will be compressed"
      ;;
    compress)
      echo " Image to compress ${COMP_GUEST}"
      echo " Full path of the image: ${IMAGE_PATH}/${IMAGE_NAME}.gz"
      ;;
    esac
  echo "#====================================#"
  read -p "Press any key to continue (Cancel with CTRL+C) ..."
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
  read -p "You really want to delete ${RM_GUEST}? (Press Ctrl+C for cancel) "

  # stop the virtual guest
  ( ${RC_SERVICE} kvm.${RM_GUEST} status > /dev/null ) && ${RC_SERVICE} kvm.${RM_GUEST} stop
  ${RM} /etc/conf.d/kvm.${RM_GUEST} >/dev/null 2>&1 || echo "* File doesn't exist"
  ${RM} /etc/init.d/kvm.${RM_GUEST} >/dev/null 2>&1 || echo "* File doesn't exist"
  ${LVREMOVE} --force "${VG_PATH}"/"${RM_GUEST}"
}

#
# new_guest()
# function for creating new virtual images
#
new_guest(){
  echo -n "Please set the image size [default is: ${IMAGE_SIZE}]: "
  read input
  [ -z "${input}" ] || IMAGE_SIZE="${input}"
  
  set_image_name "${VG_PATH}" "new_guest"
  
  info_changes new
  
  create_lv "${IMAGE_SIZE}" "${IMAGE_NAME}" "${VG_PATH}"
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
  IMAGE_TO_COPY="${CP_GUEST}"
  DEFAULT_CONF_FILE="/etc/conf.d/kvm.${IMAGE_TO_COPY}"
  
  # get the size of the original guest
  COPY_SIZE=`${LVS} ${VG_PATH}/${CP_GUEST} -o LV_SIZE --noheadings --units b --nosuffix`
  
  set_image_name "${VG_PATH}" "${CP_GUEST}_new"
  echo "Enter hostname of the new guest [default: ${IMAGE_NAME}]: "
  read guest_hostname
  [ -z "${guest_hostname}" ] || guest_hostname="${IMAGE_NAME}"
  
  info_changes copy
  
  create_lv "${COPY_SIZE}b" "${IMAGE_NAME}" "${VG_PATH}"
  
  # create snapshot
  ${LVCREATE} --size ${SNAPSHOTSIZE} --snapshot --name ${CP_GUEST}-snapshot "${VG_PATH}/${CP_GUEST}"
  echo "Copy..."
  ${DD} if=${VG_PATH}/${IMAGE_TO_COPY}-snapshot bs=4k conv=sync,noerror of=${VG_PATH}/${IMAGE_NAME}
  # delete snapshot
  ${LVREMOVE} --force ${VG_PATH}/${CP_GUEST}-snapshot
  
  # edit settings of the new vm
  # mount vm
  TMP_DIR="${IMAGE_NAME}-${RANDOM}"
  ${MKDIR} /tmp/${TMP_DIR}
  ${KPARTX} -a "${VG_PATH}/${IMAGE_NAME}"
  
  # basically i suppose the root partition is the third partition
  # which could be either $name+p3 or $name+$3
  # this can be overwritten with ${DEFAULT_ROOT_PART}
  if [ -e /dev/mapper/${VG_NAME}-${IMAGE_NAME}p${DEFAULT_ROOT_PART} ]; then
    ${MOUNT} /dev/mapper/${VG_NAME}-${IMAGE_NAME}p${DEFAULT_ROOT_PART} /tmp/${TMP_DIR}
  elif [ -e /dev/mapper/${VG_NAME}-${IMAGE_NAME}${DEFAULT_ROOT_PART} ]; then
    ${MOUNT} /dev/mapper/${VG_NAME}-${IMAGE_NAME}${DEFAULT_ROOT_PART} /tmp/${TMP_DIR}
  else
    echo "*** WARNING! No root partition found. No settings will be made ***"
    ${RM} -rf /tmp/${TMP_DIR}
    ${KPARTX} -d "${VG_PATH}/${IMAGE_NAME}"
    exit 1
  fi
    
  config_change "hostname" "${guest_hostname}" "/tmp/${TMP_DIR}/etc/conf.d/hostname"  
  
  #unmount vm
  ${UMOUNT} /tmp/${TMP_DIR}
  ${RM} -rf /tmp/${TMP_DIR}
  ${KPARTX} -d "${VG_PATH}/${IMAGE_NAME}"
}

#
# compress_lvm()
# compress a lvm partition
#
compress_lvm() {
  echo "Select the image to compress:"
  COMP_GUEST=$(select_from "`${LS} ${VG_PATH}`")
  echo "You choose ${COMP_GUEST}"
  
  set_image_path "${COMP_PATH}"
  set_image_name "${IMAGE_PATH}" "${COMP_GUEST}"
  info_changes compress
  
  # create snapshot
  ${LVCREATE} --size ${SNAPSHOTSIZE} --snapshot --name ${COMP_GUEST}-snapshot ${VG_PATH}/${COMP_GUEST}
  echo -n "Compressing..."
  ${DD} if=${VG_PATH}/${COMP_GUEST}-snapshot bs=4k conv=sync,noerror 2>/dev/null | ${GZIP} -c > ${IMAGE_PATH}/${IMAGE_NAME}.gz
  # delete snapshot
  ${LVREMOVE} --force ${VG_PATH}/${COMP_GUEST}-snapshot
}

#
# convert_guest()
# convert a lvm partition to qcow2
#
convert_guest(){
  echo "Select the image to convert:"
  CONV_GUEST=$(select_from "`${LS} ${VG_PATH}`")
  echo "You choose ${CONV_GUEST}"
  
  set_image_path "${QCOW2_PATH}"
  set_image_name "${IMAGE_PATH}" "${CONV_GUEST}.qcow2"
  
  echo -n "Would you like to compress the image? [N/y]: "
  local compress_image=false
  read input
  if [ "${input}" == "y" ]; then
    compress_image=true
  fi
  
  info_changes convert
  
  # create snapshot
  ${LVCREATE} --size ${SNAPSHOTSIZE} --snapshot --name ${CONV_GUEST}-snapshot ${VG_PATH}/${CONV_GUEST}
  echo "Converting..."
  ${QEMUIMG} convert -O qcow2 ${VG_PATH}/${CONV_GUEST}-snapshot ${IMAGE_PATH}/${IMAGE_NAME}.qcow2  
  # delete snapshot
  ${LVREMOVE} --force ${VG_PATH}/${CONV_GUEST}-snapshot
  
  if (${compress_image}); then
    echo "Compressing..."
    ${GZIP} ${IMAGE_PATH}/${IMAGE_NAME}.qcow2 
  fi
}

# start of the script
if [ $# -lt 1 ]; then
  usage;
else
  action="${1}"
  echo ">---------------< QC >---------------<"
  echo ">----------< Qemu Control >----------<"
  read -p "Press any key to continue ..."
  echo ">====================================<"
  echo "Default LV is \"${VG_PATH}\" "
  case ${1} in
    copy)
      echo ">============copy images=============<"
      copy_guest
      ;;
    new)
      echo ">============create image============<"
      new_guest
      ;;
    edit)
      echo ">============edit config=============<"
      edit_config
      ;;
    del)
      echo ">============delete guest============<"
      delete_guest
      ;;
    convert)
      QCOW2_PATH=$2
      echo ">=======convert lvm to qcow2=========<"
      convert_guest
      ;;
    compress)
      COMP_PATH=$2
      echo ">======compress a lvm partition======<"
      compress_lvm
      ;;
    *)
      usage
      ;;
   esac
fi