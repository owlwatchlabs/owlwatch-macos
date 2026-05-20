# console.tape — placeholder
#
# Surface: terminal UI (`nwctl console --follow`). Runs in a regular
# terminal, drives VHS the same way the `nwctl` CLI does.
#
# User story: the Nightwatch console streams events live with filters by
# process, path, signing identity, and rule match. Becomes meaningful at M6
# when NWLog ships and the console view starts surfacing structured events.
#
# Regenerate: `vhs docs/demos/console.tape` (writes to docs/demos/out/console.gif)

Output docs/demos/out/console.gif

Set FontSize 14
Set Width 1200
Set Height 700
Set TypingSpeed 50ms
Set Theme "Dracula"

Type "# Console surface lands at M6. Tape tracks expected behavior."
Enter
Sleep 1s

Type "nwctl console --follow"
Enter
Sleep 1s

Type "# (M6: live event stream — process exec, file open, code-signing change)"
Enter
Sleep 2s

Type "# (M6: filter expressions: --signer, --rule, --pid, --process-name)"
Enter
Sleep 2s

Type "# (M13: rule-match annotations on each event when a detection fires)"
Enter
Sleep 2s
