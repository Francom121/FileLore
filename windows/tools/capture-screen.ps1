# capture-screen.ps1 — screenshots the current interactive desktop to
# C:\Users\fm\AppData\Local\FileLore\screen.png. Run inside the interactive
# session (schtasks /ru fm /it). Used because `prlctl capture` grabs the
# console framebuffer, which can show a blank desktop even when windows are
# open in the user session.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$out = "C:\Users\fm\AppData\Local\FileLore\screen.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output "saved $out ($($bounds.Width)x$($bounds.Height))"
