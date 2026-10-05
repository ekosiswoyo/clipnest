on run argv
    set previousClipboard to the clipboard as record
    set testDocument to missing value
    try
        set the clipboard to (read POSIX file (item 1 of argv) as «class PNGf»)
        tell application "Microsoft Word"
            set testDocument to make new document
            paste object (text object of testDocument)
            set imageCount to count inline shapes of testDocument
            if imageCount is not 1 then error "Expected one pasted image"
            set imageWidth to width of inline shape 1 of testDocument
            set imageHeight to height of inline shape 1 of testDocument
            close testDocument saving no
        end tell
        set the clipboard to previousClipboard
        return "PASS Microsoft Word 16.113.3: pasted PNG as " & imageCount & " inline image; layout " & imageWidth & " x " & imageHeight & " points. Temporary document closed without saving; clipboard restored."
    on error messageText number errorNumber
        try
            if testDocument is not missing value then tell application "Microsoft Word" to close testDocument saving no
        end try
        set the clipboard to previousClipboard
        error messageText number errorNumber
    end try
end run
