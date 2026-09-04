<#
.SYNOPSIS
  dump-scx.ps1 - Dump a Visual FoxPro SCX/VCX form or class library as readable text.

.DESCRIPTION
  Parses a VFP .SCX/.VCX table (DBF format) together with its .SCT/.VCT memo file
  and prints one section per record: object class/name/parent, PROPERTIES memo
  (the property sheet) and METHODS memo (the event code).

  Format notes (discovered the hard way):
  - Memo pointers are 4-byte binary little-endian block numbers (not ASCII digits).
  - Memo block size is read from the FPT header bytes 6-7 (big-endian); VFP often
    writes 1 (pointer = raw byte offset) or 64. Do not assume 512.

.PARAMETER ScxPath
  Path to the .SCX (or .VCX) file. The memo file is assumed to sit next to it
  with the extension replaced by .SCT/.VCT (either case).

.PARAMETER MaxMethodChars
  Truncate METHODS output to this many characters per record. 0 = no limit.
  Default: 0 (full code).

.PARAMETER MaxPropLines
  Show at most this many non-empty PROPERTIES lines per record. 0 = no limit.
  Default: 0 (all lines).

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dump-scx.ps1 forms\login.scx
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dump-scx.ps1 "visual classes\dynamic.vcx" -MaxMethodChars 500
#>
param(
  [Parameter(Mandatory=$true)][string]$ScxPath,
  [int]$MaxMethodChars = 0,
  [int]$MaxPropLines   = 0
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ScxPath)) {
  Write-Error "File not found: $ScxPath"
  exit 1
}

# --- Locate memo file (.SCT for .SCX, .VCT for .VCX, try both cases) ---
$ext     = [System.IO.Path]::GetExtension($ScxPath).ToLower()
$memoExt = switch ($ext) { '.scx' { '.SCT' } '.vcx' { '.VCT' } default { '.FPT' } }
$memoPath = [System.IO.Path]::ChangeExtension($ScxPath, $memoExt)
if (-not (Test-Path -LiteralPath $memoPath)) {
  $memoPath = [System.IO.Path]::ChangeExtension($ScxPath, $memoExt.ToLower())
}
if (-not (Test-Path -LiteralPath $memoPath)) {
  Write-Error "Memo file not found next to $ScxPath (expected $memoExt)"
  exit 1
}

$dbf = [System.IO.File]::ReadAllBytes($ScxPath)
$fpt = [System.IO.File]::ReadAllBytes($memoPath)
$enc = [System.Text.Encoding]::GetEncoding(1252)

# --- DBF header ---
$recCount = [BitConverter]::ToInt32($dbf, 4)
$hdrLen   = [BitConverter]::ToUInt16($dbf, 8)
$recLen   = [BitConverter]::ToUInt16($dbf, 10)

# --- Field descriptors (32 bytes each, terminated by 0x0D) ---
$fields = @()
$pos = 32
while ($pos -lt $hdrLen -and $dbf[$pos] -ne 0x0D) {
  $name = $enc.GetString($dbf, $pos, 11).Trim([char]0, ' ')
  $fields += [PSCustomObject]@{
    Name = $name
    Type = [char]$dbf[$pos + 11]
    Len  = $dbf[$pos + 16]
  }
  $pos += 32
}

# --- FPT memo block size: header bytes 6-7, big-endian; 0 means 512 (dBASE default) ---
$bs = (([int]$fpt[6]) -shl 8) -bor ([int]$fpt[7])
if ($bs -le 0) { $bs = 512 }

function Get-MemoText([int]$ptr) {
  if ($ptr -le 0) { return '' }
  $off = $ptr * $bs
  if ($off + 8 -gt $fpt.Length) { return "<bad memo ptr $ptr>" }
  # record length is big-endian
  $len = (([int]$fpt[$off+4]) -shl 24) -bor (([int]$fpt[$off+5]) -shl 16) -bor
         (([int]$fpt[$off+6]) -shl 8)  -bor  ([int]$fpt[$off+7])
  if ($len -le 0 -or $off + 8 + $len -gt $fpt.Length) { return "<bad memo len $len @ ptr $ptr>" }
  return $enc.GetString($fpt, $off + 8, $len)
}

# --- Walk records, resolve memos ---
$rows = @()
for ($r = 0; $r -lt $recCount; $r++) {
  $base = $hdrLen + ($r * $recLen)
  if ($base + $recLen -gt $dbf.Length) { break }
  if ($dbf[$base] -eq 0x2A) { continue }  # deleted record
  $row = [ordered]@{}
  $fOff = $base + 1
  foreach ($f in $fields) {
    if ($f.Type -eq 'M') {
      $row[$f.Name] = Get-MemoText ([BitConverter]::ToInt32($dbf, $fOff))
    } else {
      $row[$f.Name] = $enc.GetString($dbf, $fOff, $f.Len).Trim()
    }
    $fOff += $f.Len
  }
  $rows += [PSCustomObject]$row
}

# --- Report ---
"SCX:     $ScxPath"
"MEMO:    $memoPath (block size $bs)"
"Records: $($rows.Count) (header said $recCount)"
""

$i = 0
foreach ($row in $rows) {
  "=== ROW $i : BASECLASS=$($row.BASECLASS)  CLASS=$($row.CLASS)  OBJNAME=$($row.OBJNAME)  PARENT=$($row.PARENT) ==="

  if ($row.PROPERTIES) {
    $plines = $row.PROPERTIES -split "`r?`n" | Where-Object { $_.Trim() -ne '' }
    if ($MaxPropLines -gt 0) { $plines = $plines | Select-Object -First $MaxPropLines }
    if ($plines) {
      "[PROPERTIES]"
      $plines | ForEach-Object { "  " + $_ }
    }
  }

  if ($row.METHODS -and $row.METHODS.Trim().Length -gt 0) {
    $m = $row.METHODS
    if ($MaxMethodChars -gt 0 -and $m.Length -gt $MaxMethodChars) {
      $m = $m.Substring(0, $MaxMethodChars) + " ...<truncated>"
    }
    "[METHODS]"
    ($m -replace "`r`n", "`n") -split "`n" | ForEach-Object { "  " + $_ }
  }
  ""
  $i++
}
