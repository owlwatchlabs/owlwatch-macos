# nwctl.tape — placeholder
#
# User story: a user runs `nwctl ps` and sees a process tree annotated with
# code-signing status, parent chain, and bundle ID. Becomes meaningful once
# M1 ships the NWProcess library and the nwctl CLI.
#
# Until M1 lands, this tape only records the placeholder "command not found"
# error. The structure is in place so the M1 PR can edit a script, not author
# a new file.
#
# Regenerate: `vhs docs/demos/nwctl.tape` (writes to docs/demos/out/nwctl.gif)

Output docs/demos/out/nwctl.gif

Set FontSize 14
Set Width 1000
Set Height 500
Set TypingSpeed 50ms
Set Theme "Dracula"

Type "# nwctl is the Nightwatch command-line. Real behavior lands at M1."
Enter
Sleep 1s

Type "nwctl ps --tree"
Enter
Sleep 1s

Type "# (M1: process tree with code-signing status, bundle ID, parent chain)"
Enter
Sleep 2s
