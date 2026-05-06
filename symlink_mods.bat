@echo off
rem Symlinks each mod folder in this repo into Darktide's mods/ directory so
rem edits in the repo are picked up by the game without copying.
rem
rem Run as Administrator (or with Windows Developer Mode enabled). If your
rem game install lives somewhere other than the default Steam path, edit the
rem `target` variable below.

setlocal enabledelayedexpansion

set source=%~dp0.
set target=c:\Program Files (x86)\Steam\steamapps\common\Warhammer 40,000 DARKTIDE\mods
set excludes=.git .github .vscode types scripts

if not exist "%target%" (
	echo ERROR: Darktide mods folder not found at:
	echo   %target%
	echo Edit symlink_mods.bat and update the 'target' variable to your install path.
	exit /b 1
)

forfiles /P "%source%" /C "cmd /c if @isdir==TRUE echo @file" > "%temp%\dirs.txt"
for /f "delims=" %%D in (%temp%\dirs.txt) do (
	set skip=0
	for %%E in (%excludes%) do (
		if /i "%%~D"=="%%E" set skip=1
	)
	if "!skip!"=="0" (
		if exist "%target%\%%~D" (
			echo SKIP %%~D ^(already exists at target^)
		) else (
			mklink /d "%target%\%%~D" "%source%\%%~D"
		)
	)
)

del "%temp%\dirs.txt" >nul 2>&1
endlocal
