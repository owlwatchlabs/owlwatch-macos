# nwctl.tape
#
# Surface: CLI (`nwctl ps`).
#
# User story: a user runs `nwctl ps` and sees the current process table
# with PID, PPID, user, and process name. The `--paths` flag adds the
# executable path. Tree view, arguments, libraries, and open files land in
# M1.2 / M1.3.
#
# This tape assumes nwctl is built and on PATH. Until `make install` ships
# (M1-close), use `swift run --package-path packages nwctl ps` instead.
#
# Regenerate: `vhs docs/demos/nwctl.tape` (writes to docs/demos/out/nwctl.gif)

Output docs/demos/out/nwctl.gif

Set FontSize 14
Set Width 1000
Set Height 500
Set TypingSpeed 50ms
Set Theme "Dracula"

Type "# nwctl ps — process table snapshot via libproc."
Enter
Sleep 1s

Type "nwctl ps | head -15"
Enter
Sleep 2s

Type "# --paths / -p adds the executable column."
Enter
Sleep 1s

Type "nwctl ps --paths | head -8"
Enter
Sleep 3s
