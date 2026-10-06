-- Session restore: each app reopens on its home workspace, so a reboot
-- rebuilds the arrangement instead of dumping everything on ws 1.
-- "Home" is where each app lived before the last reboot (2026-10-05 layout).

o.window("^brave-origin$", { workspace = "1" })
o.window("^brave-discord", { workspace = "5" })
-- Terminals are NOT pinned: Super+Return must open on the workspace you're
-- viewing, so ghostty/foot rules stay out of the session restore.
o.window("^md.obsidian.Obsidian$", { workspace = "2" })
o.window("^Proton Pass$", { workspace = "3" })

-- Floating windows remember their own size across opens (Hyprland 0.56):
o.window(".*", { persistent_size = true })
