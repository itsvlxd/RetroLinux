#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="retrolinux"
iso_label="RETRO_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="RetroLinux <https://github.com/itsvlxd/RetroLinux>"
iso_application="RetroLinux Live ISO"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="retro"
buildmodes=('iso')
bootmodes=('bios.syslinux' 'uefi.grub')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-b' '1M' '-Xcompression-level' '3')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
    ["/etc/shadow"]="0:0:400"
    ["/root"]="0:0:750"
    ["/root/.automated_script.sh"]="0:0:755"
    ["/root/.gnupg"]="0:0:700"
    ["/usr/local/bin/choose-mirror"]="0:0:755"
    ["/usr/local/bin/Installation_guide"]="0:0:755"
    ["/opt/retrolinux/"]="0:0:755"
    ["/opt/retrolinux/bin/"]="0:0:755"
    ["/opt/retrolinux/bin/retroinstall"]="0:0:755"
    ["/opt/retrolinux/bin/setup/"]="0:0:755"
    ["/opt/retrolinux/bin/post/"]="0:0:755"
    ["/opt/retrolinux/bin/lib/"]="0:0:755"
    ["/opt/retrolinux/bin/logo.txt"]="0:0:644"
)
