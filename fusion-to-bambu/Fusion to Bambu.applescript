on run
	display dialog "Fusion → Bambu Studio helper" & return & return & ¬
		"This app is intended to be launched by Fusion's 3D Print command." buttons {"OK"} default button "OK"
end run


on open inputFiles
	set homePath to POSIX path of (path to home folder)
	set configPath to homePath & "Library/Application Support/BambuStudio/BambuStudio.conf"
	
	try
		-- Ask Bambu Studio where it last exported/saved.
		set targetFolder to do shell script ¬
			"/usr/bin/plutil -extract app.last_export_path raw -o - " & quoted form of configPath
	on error
		display dialog "Could not read Bambu Studio's last_export_path." & return & return & ¬
			¬
				"Save a project manually in Bambu Studio once, then try again." buttons {"OK"} default button "OK" with icon stop
		return
	end try
	
	if targetFolder is "" then
		display dialog "Bambu Studio's last_export_path is empty." buttons {"OK"} with icon stop
		return
	end if
	
	repeat with inputFile in inputFiles
		set sourcePath to POSIX path of inputFile
		set sourceName to do shell script "/usr/bin/basename " & quoted form of sourcePath
		
		-- Normally preserve Fusion's filename so Bambu suggests a sensible
		-- project name when you subsequently use Save Project As.
		set targetPath to targetFolder & "/" & sourceName
		
		-- Don't overwrite a real file already in the destination.
		set existingIsOurStagingFile to false
		
		try
			set markerValue to do shell script ¬
				"/usr/bin/xattr -p com.fusiontobambu.staging " & ¬
				quoted form of targetPath & " 2>/dev/null"
			
			if markerValue is "1" then
				set existingIsOurStagingFile to true
			end if
		end try
		
		set targetExists to false
		try
			do shell script "/usr/bin/test -e " & quoted form of targetPath
			set targetExists to true
		end try
		
		if targetExists and not existingIsOurStagingFile then
			-- Avoid touching a legitimate STL/3MF with the same name.
			set targetPath to targetFolder & "/FusionToBambu-" & sourceName
		end if
		
		-- Make a local staging copy in the desired Save As directory.
		do shell script "/bin/cp -f " & quoted form of sourcePath & " " & quoted form of targetPath
		
		-- Mark it so a later invocation knows that we created it.
		do shell script "/usr/bin/xattr -w com.fusiontobambu.staging 1 " & quoted form of targetPath
		
		-- Keep the staging mesh out of normal Finder views.
		do shell script "/usr/bin/chflags hidden " & quoted form of targetPath
		
		-- Open the staged copy in Bambu Studio.
		do shell script "/usr/bin/open -a BambuStudio " & quoted form of targetPath
	end repeat
end open
