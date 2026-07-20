# vm-pin-tags.ps1 — adds pinnedTags (video, prompt) to fm's settings.json.
# PS 5.1 compatible (no ConvertFrom-Json -AsHashtable).
$p = "C:\Users\fm\AppData\Local\FileLore\settings.json"
$raw = Get-Content $p -Raw
$pinBlock = '"pinnedTags": [' + "`n    `"video`",`n    `"prompt`"`n  ]"
if ($raw -match '"pinnedTags"\s*:\s*\[[^\]]*\]') {
    $raw = [regex]::Replace($raw, '"pinnedTags"\s*:\s*\[[^\]]*\]', [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $pinBlock })
} else {
    $raw = $raw -replace '}\s*$', ("," + "`n  " + $pinBlock + "`n}")
}
Set-Content $p $raw -Encoding UTF8
Get-Content $p
