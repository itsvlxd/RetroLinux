#!/bin/bash

source "$RETRO_DIR/scripts/grub_core.sh"

install_grub_themes
update_grub_config
regenerate_grub
