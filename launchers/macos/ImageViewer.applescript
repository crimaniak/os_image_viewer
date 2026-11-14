-- Image Viewer applet: the Finder "Open With" entry point on macOS.
-- Built by install-macos.sh with osacompile. The launcher (open-image) and the
-- viewer files live inside the bundle, in Contents/Resources.
-- Finder delivers files as Apple Events (not argv), which is why this applet exists.

on launcherCommand()
	return quoted form of (POSIX path of (path to me) & "Contents/Resources/open-image")
end launcherCommand

on runLauncher(cmd)
	try
		do shell script cmd
	on error errMsg
		display alert "Image Viewer" message errMsg as critical
	end try
end runLauncher

on open theItems
	set cmd to launcherCommand()
	repeat with anItem in theItems
		set cmd to cmd & " " & quoted form of (POSIX path of (contents of anItem))
	end repeat
	runLauncher(cmd)
end open

-- Started without files (double-click on the app): show the viewer's help page.
on run
	runLauncher(launcherCommand())
end run
