#!/bin/bash

source /opt/retrolinux/bin/lib/setup_lib.sh

rx_post_plymouth() {
    local source_dir="/run/archiso/airootfs/usr/share/plymouth/themes/retrolinux"
    local dest_dir="/mnt/usr/share/plymouth/themes/retrolinux"
    local plymouth_conf_src="/run/archiso/airootfs/etc/plymouth/plymouthd.conf"
    local plymouth_conf_dest="/mnt/etc/plymouth/plymouthd.conf"

    rx_clear_logo
    gum style --foreground 5 "Plymouth Configuration" --padding "1 0 1 $PADDING_LEFT"
    gum style --foreground 7 "Copying and configuring Plymouth splash theme..." --padding "1 0 1 $PADDING_LEFT"

    if [[ ! -d $source_dir ]]; then
        gum style --foreground 3 "Plymouth theme not found at $source_dir, skipping" --padding "1 0 1 $PADDING_LEFT"
        return 0
    fi

    mkdir -p "$dest_dir"
    if cp -rf "$source_dir"/* "$dest_dir/"; then
        gum style --foreground 2 "  Plymouth theme files copied" --padding "1 0 1 $PADDING_LEFT"
    else
        gum style --foreground 3 "  Warning: Could not copy Plymouth theme files" --padding "1 0 1 $PADDING_LEFT"
    fi

    mkdir -p /mnt/etc/plymouth
    if [[ -f $plymouth_conf_src ]]; then
        if cp -f "$plymouth_conf_src" "$plymouth_conf_dest"; then
            gum style --foreground 2 "  Plymouth config copied" --padding "1 0 1 $PADDING_LEFT"
        else
            gum style --foreground 3 "  Warning: Could not copy Plymouth config" --padding "1 0 1 $PADDING_LEFT"
        fi
    fi

    gum style --foreground 7 "Setting Plymouth theme (via chroot)..." --padding "1 0 1 $PADDING_LEFT"
    local chroot_result
    if chroot_result=$(arch-chroot /mnt plymouth-set-default-theme retrolinux 2>&1); then
        gum style --foreground 2 "  Plymouth theme set successfully" --padding "1 0 1 $PADDING_LEFT"
    else
        gum style --foreground 3 "  Warning: Could not set Plymouth theme via chroot" --padding "1 0 1 $PADDING_LEFT"
        gum style --foreground 7 "  Falling back to direct config edit..." --padding "1 0 1 $PADDING_LEFT"
        if [[ -f /mnt/etc/plymouth/plymouthd.conf ]]; then
            sed -i 's|^.*Theme=.*|Theme=retrolinux|' /mnt/etc/plymouth/plymouthd.conf 2>/dev/null || true
            gum style --foreground 2 "  Plymouth theme set via config edit" --padding "1 0 1 $PADDING_LEFT"
        fi
    fi

    gum style --foreground 2 "Plymouth configuration complete" --padding "1 0 1 $PADDING_LEFT"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    rx_post_plymouth "$@"
fi

