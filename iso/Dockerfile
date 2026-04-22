FROM archlinux/archlinux:latest AS deps

LABEL maintainer="RetroLinux"
LABEL description="RetroLinux ISO build environment with archiso pre-installed"

RUN pacman --noconfirm -Sy && \
    pacman --noconfirm -S archiso git sudo base-devel jq grub bc imagemagick && \
    pacman --noconfirm -Sc && \
    rm -rf /var/lib/pacman/db.lck

FROM deps AS cache

WORKDIR /cache-build

COPY profile/packages.x86_64 /tmp/packages.x86_64

RUN mkdir -p /var/cache/retrolinux/mirror/offline && \
    mkdir -p /tmp/offlinedb && \
    mkdir -p /tmp/offline && \
    yes | xargs pacman -Syw --noconfirm \
        --cachedir /tmp/offline \
        --dbpath /tmp/offlinedb < /tmp/packages.x86_64 && \
    cp -r /tmp/offline/* /var/cache/retrolinux/mirror/offline/ && \
    cd /var/cache/retrolinux/mirror/offline && \
    repo-add offline.db.tar.gz *.pkg.tar.zst && \
    rm -rf /tmp/offlinedb /tmp/packages.x86_64 /tmp/offline

FROM deps AS version

COPY profile/packages.x86_64 /tmp/packages.x86_64

RUN pacman -Sy --noconfirm && \
    mkdir -p /var/cache/retrolinux/mirror/offline && \
    while IFS= read -r pkg; do \
        [[ -z "$pkg" ]] && continue; \
        version=$(pacman -Qi "$pkg" 2>/dev/null | awk '/^Version/{print $3}') || continue; \
        echo "$pkg $version"; \
    done < /tmp/packages.x86_64 > /var/cache/retrolinux/mirror/offline/.versions && \
    rm -rf /var/lib/pacman/db.lck

FROM deps

COPY --from=cache /var/cache/retrolinux /var/cache/retrolinux
COPY --from=version /var/cache/retrolinux/mirror/offline/.versions /var/cache/retrolinux/mirror/offline/.versions

WORKDIR /build
