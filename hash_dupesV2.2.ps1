####this script requires P$ version 4.0 --(mostly for the get-filehash) 
###download here: http://www.microsoft.com/en-us/download/details.aspx?id=40855
#clear all the variables?
Get-Variable  | Remove-Variable -EA 0
cls


	
#set home directory

$path = read-host -Prompt "Where do you want to look for duplicates?"
$offlimits_file_dirs = $env:SystemDrive,$env:SystemRoot,$env:ProgramFiles,${env:ProgramFiles(x86)},'C:\SCRIPTS_FOLDER - Copy'
if ($offlimits_file_dirs -contains $path) {THROW "You cannot search this directory, you might break something!"}

#run powershell as admin first -->start-->powershell-->right click and "run as admin"
#Set-ExecutionPolicy unrestricted

#start the clock!
	$time1=Get-Date



#no longer need to create MD5 tool based on: http://blogs.msdn.com/b/powershell/archive/2006/04/25/583225.aspx --removed 11/2/14

#now we need to recurse through all the files to compare hashes
#sort through ALL of the files first, and store the hash and filename in memory, then run a script to see which are dupes

# Reporting variables
$removed_duped_report = @()

# Log file
$logFile = "log.txt"
if (Test-Path $logFile) {Clear-Content $logFile} else {New-Item -ItemType file -Path $logFile}

#first off find anything bigger than 0 and is not a folder
	$get_all_the_files=Get-ChildItem -Path $Path -Recurse |Where-Object { ($_.Length -gt 0) -and ($_.PSIsContainer -ne $true) } 
#let's get some number counts
	$total_files=$get_all_the_files.count
	$total_file_size_bytes=($get_all_the_files| measure length -sum).sum
	$total_file_size_MBs_RAW=($total_file_size_bytes/ 1MB)
	$total_file_size_MBs="{0:N2}" -f $total_file_size_MBs_RAW
#what file number are we on for counting?
	$file_number_were_on=1
#get the running file size
	$total_running_filesize= ($get_all_the_files | Measure-Object -Sum length).Sum
#set the psobject up:

#create array for all files scanning
$all_files_info = @()

foreach ($file in $get_all_the_files)
	{
		
	$hash=get-filehash -algorithm md5 $($file.FullName)
	$actualhash=$hash.Hash
	$filesize=$file.Length
	$filename=$file.FullName
		#chart our progress:
			
			write "Working on hashing file $file_number_were_on of $total_files ($file). This file is $filesize bytes."
				$all_files_info += @([pscustomobject]@{filename="$filename";hash=$actualhash;size=$filesize})
		
		$file_number_were_on++
		
	}	

#group them by the hash and remove if there's only 1 instance (meaning duplicate!)
	$duplicate_hashes_only=$all_files_info | group hash | ? {$_.count -ne 1}

#now I have all the files grouped by their hashes and doubles, need to now tell the...
#...user that there are dupes, and which files they are!

#count of the number of duplicate files
$duplicate_hashes_only_file_count = ($duplicate_hashes_only | Measure-Object -Sum Count).sum

$all_duped_files_info = @()
$total_duped_files=0
$total_duped_filesize=0
$keeping_one_file_storage=0
#these next 2 vars are just for the double loop coming up
	$global:total_size_ACTUALS=0
	$global:total_number_dupes=0

#there are multiple files in each PSobject right now, so i can't just pull via each property
foreach ($duped_file in $duplicate_hashes_only)
	{
	$file_number_were_on_again=1
	
	$actualhash_again=$duped_file.name
	$split_out_multiple_filenames=$duped_file.group.filename
	Add-Content -Path $logFile -Value "***Starting hash $actualhash_again cleanup***"
	write "This hash $actualhash_again) has $($duped_file.Count) instances! Splitting/hashing..."
	$total_duped_files+=$duped_file.Count
		
		#gotta loop WITHIN a loop now to get all the files spit out individually -->
		foreach ($individual_file in $split_out_multiple_filenames)
		
			{
				$filename_again=$individual_file
				
			#they are all the same size as they're dupes, so this'll work
				$filesize_again=$duped_file.group.size[0]
				#get the running filesize (to show overall savings)
				$total_duped_filesize+=$filesize_again
					#need to add back 1 file size from each round as we need to keep 1 file, can't delete all
					#wow, that took way longer than needed, but the win is the global variable in there!
					#also knowing that the count is going to loop/count multiple times so divide by that many.
					$individual_number_of_files_duped=$split_out_multiple_filenames.count
					$keeping_one_file_storage=$filesize_again/$individual_number_of_files_duped
					$global:total_size_ACTUALS +=$keeping_one_file_storage
					
						#need to do the same with file counts, but need to loop through x times, but keep 1, so subtract and divide
							$keeping_one_file_storage_count=(($individual_number_of_files_duped-1)/ $individual_number_of_files_duped)
							$global:total_number_dupes +=$keeping_one_file_storage_count
																		
					#Let's now add it BACK to a PSObject so I can more easily export it to csv
						$all_duped_files_info += @([pscustomobject]@{filename="$filename_again";hash=$actualhash_again;size=$filesize_again})
				
			
					#chart our progress,again:
							write "Splitting/hashing file $file_number_were_on_again of $($duped_file.count) ($filename_again). This file is $filesize_again bytes."
							
			
					# Removing duplicated files.  Leaves first file and deletes remaining duplicates
					$filename_again_details = Get-Item $filename_again
					if ($file_number_were_on_again -gt 1)
						{
						Add-Content -Path $logFile -Value "$(get-date) Removing duplicate file $filename_again"
						write "Removing duplicate file $filename_again"
						Remove-Item $filename_again -Force
						$removed_duped_report += @([pscustomobject]@{filename="$filename_again";hash=$actualhash_again;action="Deleted";size=$filename_again_details.Length})						
						}
					else
						{
						Add-Content -Path $logFile -Value "$(get-date) Keeping file $filename_again"
						write "Keeping file $filename_again.  Will remove duplicates"
						$removed_duped_report += @([pscustomobject]@{filename="$filename_again";hash=$actualhash_again;action="Kept";size=$filename_again_details.Length})						
						}
						
					$file_number_were_on_again++
			}
	Add-Content -Path $logFile -Value "***End hash $actualhash_again cleanup***"
	}

#let's get some numbers around space and the savings we'd get!
		$total_space_used_in_MB_RAW=($total_running_filesize /1MB)
		$total_space_used_in_MB="{0:N2}" -f $total_space_used_in_MB_RAW
		#this next line is the total amount of space MINUS the single version of the file that needs to stay
			$total_space_duped_in_MB_RAW =(($total_duped_filesize-$global:total_size_ACTUALS) /1MB)
			$total_space_duped_in_MB="{0:N2}" -f $total_space_duped_in_MB_RAW		

write "There are $total_duped_files duped files, $global:total_number_dupes of them unique.  Therefore ther are $($total_duped_files - $global:total_number_dupes) duplicates that can go.  Removing those duplicates would save you $($total_space_duped_in_MB)MB of $($total_space_used_in_MB)MB on $path"

#bada-boom!  Works!  So let's send that to a CSV file now.
$exportfilename="c:\SCRIPTS_FOLDER\all_duped_files.csv"
$all_duped_files_info | Export-Csv $exportfilename -NoTypeInformation

$time2=Get-Date
$timediff=$time2-$time1
write "This script took $timediff to run!"

# Report
write "Duplicated files report: Removed $total_number_dupes files. Space saved: $($total_space_duped_in_MB)MB"
$dupReport = "c:\SCRIPTS_FOLDER\dupReport.csv"
$removed_duped_report | Export-Csv $dupReport -NoTypeInformation

$secpasswd = ConvertTo-SecureString "HIDDEN_PASSWORD" -AsPlainText -Force
$Credentials =  New-Object System.Management.Automation.PSCredential ("scriptingrobot", $secpasswd)
$From = "scriptingrobot@gmail.com"
$To = "YOUREMAIL"
$Cc = "ANOTHEREMAIL"
$Attachment = $exportfilename, $dupReport, $logFile
$Subject = "We had some dupes!"
$Body = "We did a bunch of stuff, notably these variables: 
We scanned this directory (and subdirectories): $path.
We scanned this many files: $file_number_were_on files.
There were this many file duplicates (not including original file): $total_number_dupes.
These duplicates take up this much space: $($total_space_duped_in_MB)MB.
We scanned this amount: $($total_file_size_MBs)MB.
It took this much time: $timediff.

Attached is the list, hash, and size of all the duplicate files."
$SMTPServer = "smtp.gmail.com"
$SMTPPort = "587"

Send-MailMessage -From $From -To $To -Cc $Cc -Subject $Subject -Body $Body -SmtpServer $SMTPServer -port $SMTPPort -UseSsl -Credential $credentials	-Attachments $Attachment