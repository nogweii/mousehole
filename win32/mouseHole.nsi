; example1.nsi
;
; This script is perhaps one of the simplest NSIs you can make. All of the
; optional settings are left to their default settings. The installer simply 
; prompts the user asking them where to install, and drops a copy of example1.nsi
; there. 

;--------------------------------

; The name of the installer
Name "MouseHole 1.1"

; The file to write
OutFile "mouseHole-1.1.exe"

; The default installation directory
InstallDir $PROGRAMFILES\MouseHole

;--------------------------------

; Pages

Page directory
Page instfiles

;--------------------------------

; The stuff to install
Section "" ;No components page, name is not important

  ; Application directory
  SetOutPath $INSTDIR
  File mouseHole.exe
  File iconv.dll
  File gdbm.dll
  File charset.dll

  ; Images
  SetOutPath $INSTDIR\images
  File images\mouseHole-neon.png

SectionEnd ; end the section
