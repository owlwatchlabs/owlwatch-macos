# menubar.tape — placeholder
#
# User story: the Nightwatch menu-bar icon opens to show recent process and
# file events, code-signing alerts, and a search box. Tape script becomes
# meaningful once M2/M3 ship event surfacing in the menu-bar app.
#
# This tape uses `osascript` to drive the menu-bar surface via the
# Accessibility API once the app exposes one. At M0 the app only shows
# "Nightwatch — M0 placeholder" and a Quit button; the tape script reflects
# that.
#
# Regenerate: `vhs docs/demos/menubar.tape` (writes to docs/demos/out/menubar.gif)

Output docs/demos/out/menubar.gif

Set FontSize 14
Set Width 1200
Set Height 700
Set TypingSpeed 50ms
Set Theme "Dracula"

Type "# Menu-bar surface lands at M2/M3. This tape script tracks expected state."
Enter
Sleep 1s

Type "open -a Nightwatch"
Enter
Sleep 2s

Type "# (M2: menu-bar shows process exec events with code-signing badges)"
Enter
Sleep 2s

Type "# (M3: code-signing alerts highlight unsigned or revoked binaries)"
Enter
Sleep 2s
