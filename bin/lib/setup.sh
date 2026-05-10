#!/bin/bash

rx_chrootable_systemctl_enable() {
  if [[ -n ${RETRO_CHROOT_INSTALL:-} ]]; then
    sudo systemctl enable "$1"
  else
    sudo systemctl enable --now "$1"
  fi
}

export -f rx_chrootable_systemctl_enable