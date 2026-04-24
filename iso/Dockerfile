FROM archlinux/archlinux:latest

LABEL maintainer="RetroLinux"
LABEL description="RetroLinux ISO build environment with archiso pre-installed"

RUN pacman --noconfirm -Sy && \
    pacman --noconfirm -S archiso git sudo base-devel jq grub bc imagemagick && \
    rm -rf /var/lib/pacman/db.lck

COPY profile/packages.x86_64 /tmp/packages.x86_64

RUN mkdir -p /var/cache/pacman/pkg && \
    pacman --noconfirm -Sy && \
    while IFS= read -r pkg; do \
        [[ -z "$pkg" ]] && continue; \
        pacman --noconfirm -Sw "$pkg" --cachedir /var/cache/pacman/pkg 2>/dev/null || true; \
    done < /tmp/packages.x86_64 && \
    rm -f /tmp/packages.x86_64 && \
    rm -rf /var/lib/pacman/db.lck

WORKDIR /build