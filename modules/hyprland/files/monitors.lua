----------------
--- MONITORS ---
----------------
--
-- See https://wiki.hypr.land/Configuring/Monitors/

hl.monitor({
    output = "desc:Samsung Display Corp. 0x4197",
    mode = "highrr",
    vrr = 1,
    position = "0x0",
    scale = 2,
    bitdepth = 10,
})

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
})
