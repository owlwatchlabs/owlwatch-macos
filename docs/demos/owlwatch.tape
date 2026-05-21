# owlwatch.tape
#
# Surface: CLI (`owlwatch ps`).
#
# User story: a user runs `owlwatch ps` and sees the current process table
# with PID, PPID, user, and process name. The `--paths` flag adds the
# executable path. Tree view, arguments, libraries, and open files land in
# M1.2 / M1.3.
#
# This tape assumes owlwatch is built and on PATH. Until `make install` ships
# (M1-close), use `swift run --package-path packages owlwatch ps` instead.
#
# Regenerate: `vhs docs/demos/owlwatch.tape` (writes to docs/demos/out/owlwatch.gif)

Output docs/demos/out/owlwatch.gif

Set FontSize 14
Set Width 1000
Set Height 500
Set TypingSpeed 50ms
Set Theme "Dracula"

Type "# owlwatch ps — process table snapshot via libproc."
Enter
Sleep 1s

Type "owlwatch ps | head -15"
Enter
Sleep 2s

Type "# --paths / -p adds the executable column."
Enter
Sleep 1s

Type "owlwatch ps --paths | head -8"
Enter
Sleep 3s
