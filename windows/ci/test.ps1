# Automated Windows test for Memo. Starts the real app several times and checks, on a real Windows desktop:
#  run 1 (light): the app copies text, a link, a colour, a picture, files and a secret on the real clipboard and checks
#                 the history kept or skipped each; pin, search, delete, saved to disk, paste back; popup above the tray
#  run 2 (dark):  the history is still there after a restart; an opened row; popup in dark
#  run 3:         the Settings window    run 4: the welcome window    run 5: the global shortcut opens the popup
param([string]$Exe = 'out/Memo/Memo.exe', [string]$Shots = 'shots')
. "$PSScriptRoot/winlib.ps1"
New-Item -ItemType Directory -Force $Shots | Out-Null
$Exe = (Resolve-Path $Exe).Path
$Shots = (Resolve-Path $Shots).Path
$data = Join-Path $Shots 'data'
$data2 = Join-Path $Shots 'data-fresh'

function Read-Json($path) { Get-Content $path -Raw | ConvertFrom-Json }

# ---- Run 1: light, capture checks, popup open ----
Set-Theme $false
$json = Join-Path $Shots 'memo-selftest.json'
$p = Start-App $Exe @('--no-intro', "--data=$data", '--capture-test', '--test-open', "--selftest=$json")
Check (Promote-TrayIcon 'Memo.exe') 'tray icon registered with Windows (NotifyIconSettings entry)'
Check (Wait-File $json 120) 'self-test file written'
$r = Read-Json $json
Write-Host ($r | ConvertTo-Json -Depth 5)
Check ($null -eq $r.error) "no error inside the app ($($r.error))"
Check (-not $p.HasExited) 'process alive'
Check $r.clipboardListener 'clipboard listener registered (AddClipboardFormatListener)'
Check $r.hotKey "global shortcut registered ($($r.hotKeyName))"
Check $r.textCaptured 'copied text lands in the history'
Check $r.linkCleaned 'tracking bits (utm_source, fbclid) removed from a copied link'
Check $r.colourCaptured 'a copied colour code is recognised'
Check $r.imageCaptured 'a copied picture lands in the history'
Check $r.imageSavedToDisk 'the picture is saved as a PNG on disk'
Check $r.filesCaptured 'copied files land in the history'
Check $r.secretSkipped 'an item marked secret is never saved'
Check $r.pausedSkipped 'nothing is recorded while paused'
Check $r.pinnedFirst 'pinning moves an item to the top'
Check $r.searchFinds 'search finds the right item and nothing else'
Check $r.deleted 'delete removes an item'
Check $r.persisted 'history is saved to disk and reads back'
Check $r.pasteTextBack 'text pastes back onto the clipboard'
Check $r.pasteImageBack 'picture pastes back onto the clipboard'
Check $r.pasteFilesBack 'files paste back onto the clipboard'
Check $r.noDuplicatesFromPaste 'pasting back does not add a duplicate'
Check $r.popupVisible 'popup opened'
Check ($r.listCount -ge 4) "popup lists the items (listed $($r.listCount))"
Check ($null -ne $r.tray) 'tray icon has a position on screen'
Start-Sleep -Seconds 1
Save-Screen (Join-Path $Shots '01-memo-desktop-light.png')
$b = $r.popupBounds
Save-Crop (Join-Path $Shots '02-memo-popup-light.png') $b[0] $b[1] $b[2] $b[3]
Save-TrayCorner (Join-Path $Shots '03-memo-tray-light.png')
Check (Quit-App $Exe 'Memo') 'quit with --quit (clean exit)'

# ---- Run 2: dark, history survives a restart, first row opened ----
Set-Theme $true
$json2 = Join-Path $Shots 'memo-selftest-dark.json'
$p2 = Start-App $Exe @('--no-intro', "--data=$data", '--test-open', '--test-expand', "--selftest=$json2")
[void](Promote-TrayIcon 'Memo.exe' 10)
Check (Wait-File $json2 120) 'dark run: self-test file written'
$r2 = Read-Json $json2
Check ($null -eq $r2.error) 'dark run: no error inside the app'
Check ($r2.itemsAtStart -ge 4) "history is still there after a restart ($($r2.itemsAtStart) items)"
Check $r2.popupVisible 'dark run: popup opened'
Save-Screen (Join-Path $Shots '04-memo-desktop-dark.png')
$b = $r2.popupBounds
Save-Crop (Join-Path $Shots '05-memo-popup-dark-open-row.png') $b[0] $b[1] $b[2] $b[3]
Save-TrayCorner (Join-Path $Shots '06-memo-tray-dark.png')
Check (Quit-App $Exe 'Memo') 'dark run: clean quit'

# ---- Run 3: Settings window ----
$json3 = Join-Path $Shots 'memo-selftest-settings.json'
$p3 = Start-App $Exe @('--no-intro', "--data=$data", '--test-settings', "--selftest=$json3")
Check (Wait-File $json3 120) 'settings run: self-test file written'
$r3 = Read-Json $json3
Check $r3.settingsVisible 'Settings window opened'
$b = $r3.settingsBounds
Save-Crop (Join-Path $Shots '07-memo-settings-dark.png') $b[0] $b[1] $b[2] $b[3]
Check (Quit-App $Exe 'Memo') 'settings run: clean quit'

# ---- Run 4: welcome window on a fresh install ----
Set-Theme $false
$json4 = Join-Path $Shots 'memo-selftest-intro.json'
$p4 = Start-App $Exe @("--data=$data2", '--test-intro', "--selftest=$json4")
Check (Wait-File $json4 120) 'welcome run: self-test file written'
$r4 = Read-Json $json4
Check (-not $r4.introDoneAtStart) 'fresh install has not seen the welcome yet'
Check $r4.introVisible 'welcome window opened'
$b = $r4.introBounds
Save-Crop (Join-Path $Shots '08-memo-welcome-light.png') $b[0] $b[1] $b[2] $b[3]
Check (Quit-App $Exe 'Memo') 'welcome run: clean quit'

# ---- Run 5: the global shortcut opens the popup ----
$json5 = Join-Path $Shots 'memo-selftest-hotkey.json'
$p5 = Start-App $Exe @('--no-intro', "--data=$data", "--selftest=$json5")
Check (Wait-File $json5 120) 'hotkey run: self-test file written'
$r5 = Read-Json $json5
Check (-not (Window-Visible 'Memo')) 'popup closed before the shortcut'
if ($r5.hotKeyName -eq 'Ctrl+Shift+V') {
  [System.Windows.Forms.SendKeys]::SendWait('^+v')
  Start-Sleep -Seconds 2
  Check (Window-Visible 'Memo') 'Ctrl+Shift+V opened the popup'
  Save-Screen (Join-Path $Shots '09-memo-hotkey-open.png')
} else {
  Fail "Ctrl+Shift+V could not be registered (Memo used $($r5.hotKeyName))"
}
Check (Quit-App $Exe 'Memo') 'hotkey run: clean quit'
Set-Theme $false

# ---- No zooming: Ctrl+wheel (= trackpad pinch), Ctrl and plus/minus/0 must do nothing ----
. "$PSScriptRoot/zoomtest.ps1"
Test-NoZoom $Exe 'Memo' $Shots @('--no-intro', "--data=$(Join-Path $Shots 'data-zoom')")
Set-Theme $false
Finish
