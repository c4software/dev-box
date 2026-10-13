-- dev-box: the Hyprland of `devbox desktop`, a session with no screen of its
-- own, shown by gliff on a private one. Kept bare: a launcher, no bar, no
-- animation. Your own goes in ~/.config/dev-box/desktop/hyprland.lua and
-- replaces this file as a whole.

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

hl.config({
    general = {
        gaps_in     = 2,
        gaps_out    = 4,
        border_size = 1,
    },
    animations = {
        enabled = false,
    },
    decoration = {
        blur   = { enabled = false },
        shadow = { enabled = false },
    },
    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
    },
    ecosystem = {
        no_update_news  = true,
        no_donation_nag = true,
    },
    -- Nothing in the box needs X11.
    xwayland = {
        enabled = false,
    },
})

-- The background: /usr/share/devbox/desktop/wallpaper.jpg, or your own
-- ~/.config/dev-box/desktop/wallpaper.jpg or .png. No app is opened.
hl.on("hyprland.start", function()
    hl.exec_cmd("dev-box-desktop wallpaper")
end)

-- The application launcher (fuzzel, with /etc/devbox/desktop/fuzzel.ini or
-- your own ~/.config/dev-box/desktop/fuzzel.ini) shows itself on a screen
-- with no window: when a client connects to an empty session, and when the
-- last window closes. It runs only while it is shown.
hl.on("monitor.added", function()
    hl.exec_cmd("dev-box-desktop launcher if-empty")
end)
hl.on("window.destroy", function()
    hl.exec_cmd("dev-box-desktop launcher if-empty")
end)

local mod = "SUPER"

hl.bind(mod .. " + Space", hl.dsp.exec_cmd("dev-box-desktop launcher"))
hl.bind(mod .. " + Return", hl.dsp.exec_cmd("foot"))
-- The apps of `devbox desktop install`: a key says so when one is missing.
hl.bind(mod .. " + B", hl.dsp.exec_cmd("dev-box-desktop open chromium"))
hl.bind(mod .. " + C", hl.dsp.exec_cmd("dev-box-desktop open code"))
hl.bind(mod .. " + Q", hl.dsp.window.close())
hl.bind(mod .. " + F", hl.dsp.window.fullscreen())

hl.bind(mod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + down",  hl.dsp.focus({ direction = "down" }))

for i = 1, 4 do
    hl.bind(mod .. " + " .. i,           hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. i,   hl.dsp.window.move({ workspace = i }))
end
