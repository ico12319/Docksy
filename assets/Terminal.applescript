tell application id "com.apple.Terminal"
    repeat with terminalWindow in windows
        repeat with terminalTab in tabs of terminalWindow
            if tty of terminalTab is wantedTTY then
                set selected of terminalTab to true
                set miniaturized of terminalWindow to false
                set index of terminalWindow to 1
                activate
                return true
            end if
        end repeat
    end repeat
end tell
return false
