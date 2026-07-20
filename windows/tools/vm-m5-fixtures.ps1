# vm-m5-fixtures.ps1 — builds the M5 demo fixtures inside the VM:
#   C:\FileLoreTest\media\demo.mp4 / demo.wmv   videos with a note + 2 linked files
#   C:\FileLoreTest\media\ref-poster.png / ref-script.txt   link targets
#   C:\FileLoreTest\multi\b1..b3.txt    noted files for the batch window
# Notes are written through the same ADS stream the app uses, so the
# editor/search read them back through the real code path.
# Run as fm in the interactive session (schtasks /ru fm /it).
#
# Media note: this Parallels arm64 VM has no H.264 decoder (mfh264dec.dll
# missing) and its virtual GPU can't drive WPF MediaElement playback, so the
# WMV transcode (dist-assets/demo.wmv, made with
# `ffmpeg -i filelore-demo.mp4 -c:v wmv2 -c:a wmav2`) is used for media
# screenshots; even that only reaches the thumbnail fallback in the VM.
# Real Intel PCs play H.264 inline. Pinned tags are set by vm-pin-tags.ps1.

$ErrorActionPreference = "Stop"
$media = "C:\FileLoreTest\media"
$multi = "C:\FileLoreTest\multi"
New-Item -ItemType Directory -Force $media, $multi | Out-Null

# --- files -------------------------------------------------------------------
Copy-Item "\\Mac\Home\Documents\Tether\website\public\filelore-demo.mp4" "$media\demo.mp4" -Force
Copy-Item "\\Mac\Home\Documents\Tether\windows\dist-assets\demo.wmv" "$media\demo.wmv" -Force
Copy-Item "\\Mac\Home\Documents\Tether\windows\src\FileLore.App\Resources\icon-256.png" "$media\ref-poster.png" -Force
Set-Content "$media\ref-script.txt" "reference script for the demo video"
foreach ($n in 1..3) { Set-Content "$multi\b$n.txt" "batch demo file $n" }

# --- notes (envelope JSON into the ADS stream) --------------------------------
$created = 776854800.0  # 2025-08-18 in Apple reference-date seconds
function Write-Note($path, $noteJson) {
    Set-Content -Path ($path + ":filelore.note") -Value $noteJson -Encoding UTF8
}

$demoNote = @"
{
  "version": 1,
  "note": {
    "body": "Prompt: cinematic shot of a red panda at golden hour\n\nModel: flux-2\n\nVoice: none",
    "tags": ["video", "prompt"],
    "links": [
      {
        "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
        "bookmark": "",
        "displayName": "ref-poster.png",
        "relativePathHint": "ref-poster.png",
        "path": "C:\\FileLoreTest\\media\\ref-poster.png",
        "size": 20480,
        "added": $created
      },
      {
        "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
        "bookmark": "",
        "displayName": "ref-script.txt",
        "relativePathHint": "ref-script.txt",
        "path": "C:\\FileLoreTest\\media\\ref-script.txt",
        "size": 41,
        "added": $created
      }
    ],
    "created": $created,
    "modified": $created
  }
}
"@
Write-Note "$media\demo.mp4" $demoNote
Write-Note "$media\demo.wmv" $demoNote

$videoNote = '{ "version": 1, "note": { "body": "batch demo note with a video tag", "tags": ["video"], "links": [], "created": 776854800.0, "modified": 776854800.0 } }'
Write-Note "$multi\b1.txt" $videoNote
Write-Note "$multi\b2.txt" ('{ "version": 1, "note": { "body": "second batch demo file", "tags": ["prompt"], "links": [], "created": 776854800.0, "modified": 776854800.0 } }')
Write-Note "$multi\b3.txt" ('{ "version": 1, "note": { "body": "third file, untagged note", "tags": [], "links": [], "created": 776854800.0, "modified": 776854800.0 } }')

# --- pinned tags ---------------------------------------------------------------
& "$PSScriptRoot\vm-pin-tags.ps1"

Write-Output "fixtures ready: $media, $multi; pinnedTags=video,prompt"
