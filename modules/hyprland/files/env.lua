-----------------------------
--- ENVIRONMENT VARIABLES ---
-----------------------------
--
-- See https://wiki.hypr.land/Configuring/Environment-variables/

local retro_dir = os.getenv("RETRO_DIR") or "/opt/retrolinux"
package.path = retro_dir .. "/lib/lua/?.lua;" .. package.path

pcall(dofile, os.getenv("HOME") .. "/.config/retro/env.lua")

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("GTK_THEME", "adw-gtk3-dark")
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT5_STYLE_OVERRIDE", "")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
