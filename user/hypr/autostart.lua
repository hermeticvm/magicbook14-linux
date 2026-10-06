-- Session restore: reopen the daily set after login, like macOS.
-- Each lands on its home workspace via the rules in hypr/windows.lua.
-- Trim freely; add e.g. o.launch_on_start("proton-pass") for more.

o.launch_on_start("omarchy-launch-browser")
o.launch_on_start("omarchy-launch-terminal")
o.launch_on_start("obsidian")
