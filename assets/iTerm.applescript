tell application id "com.googlecode.iterm2"
    repeat with terminalWindow in windows
        repeat with terminalTab in tabs of terminalWindow
            repeat with terminalSession in sessions of terminalTab
                if tty of terminalSession is wantedTTY then
                    set miniaturized of terminalWindow to false
                    select terminalWindow
                    select terminalTab
                    select terminalSession
                    activate
                    return true
                end if
            end repeat
        end repeat
    end repeat
end tell
return false
