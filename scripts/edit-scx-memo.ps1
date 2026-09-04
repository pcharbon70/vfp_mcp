<#
.SYNOPSIS
  edit-scx-memo.ps1 - Edit a memo field (PROPERTIES/METHODS/etc.) directly inside a VFP SCX/VCX table.

.DESCRIPTION
  Appends a NEW memo block to the FPT memo file and repoints the DBF record's
  memo pointer at it. The old memo block is orphaned (reclaimed by PACK MEMO).
  The .SCX/.SCT files must NOT be open in Visual FoxPro while editing.

  IMPORTANT caveats:
  - Editing METHODS leaves the record's OBJCODE (compiled code) stale; VFP
    detects the mismatch and recompiles on next load/run. For safety this
    script can also zero the OBJCODE pointer (-ClearObjCode).
  - A built .EXE contains compiled forms; editing the source SCX only affects
    the project source - the EXE must be rebuilt.
  - Always work on a backup / use git.

.PARAMETER ScxPath    Path to the .SCX/.VCX file (memo file found alongside).
.PARAMETER ObjName    OBJNAME of the record to edit (e.g. a control or form name).
.PARAMETER MemoField  Memo field to edit: METHODS, PROPERTIES, etc.
.PARAMETER Find       Literal text to find ("" = append mode).
.PARAMETER Replace    Replacement text (or text to append in append mode).
.PARAMETER Append     Append Replace text to end of memo instead of find/replace.
.PARAMETER ClearObjCode  Zero the record's OBJCODE memo pointer after editing.
#>
param(
  [Parameter(Mandatory=$true)][string]$ScxPath,
  [Parameter(Mandatory=$true)][string]$ObjName,
  [Parameter(Mandatory=$true)][string]$MemoField,
  [string]$Find = "",
  [string]$Replace = "",
  [switch]$Append,
  [switch]$ClearObjCode
)

$ErrorActionPreference = 'Stop'

# --- locate memo file ---
$ext     = [System.IO.Path]::GetExtension($ScxPath).ToLower()
$memoExt = switch ($ext) { '.scx' { '.SCT' } '.vcx' { '.VCT' } default { '.FPT' } }
$memoPath = [System.IO.Path]::ChangeExtension($ScxPath, $memoExt)
if (-not (Test-Path -LiteralPath $memoPath)) {
  $memoPath = [System.IO.Path]::ChangeExtension($ScxPath, $memoExt.ToLower())
}
if (-not (Test-Path -LiteralPath $memoPath)) { Write-Error "Memo file not found for $ScxPath"; exit 1 }

$dbf = [System.IO.File]::ReadAllBytes($ScxPath)
$fpt = [System.IO.File]::ReadAllBytes($memoPath)
$enc = [System.Text.Encoding]::GetEncoding(1252)

$recCount = [BitConverter]::ToInt32($dbf, 4)
$hdrLen   = [BitConverter]::ToUInt16($dbf, 8)
$recLen   = [BitConverter]::ToUInt16($dbf, 10)

# --- field descriptors with byte offsets within record ---
$fields = @()
$pos = 32; $off = 1   # +1 skips deletion flag
while ($pos -lt $hdrLen -and $dbf[$pos] -ne 0x0D) {
  $name = $enc.GetString($dbf, $pos, 11).Trim([char]0, ' ')
  $fields += [PSCustomObject]@{ Name=$name; Type=[char]$dbf[$pos+11]; Len=$dbf[$pos+16]; Off=$off }
  $off += $dbf[$pos+16]; $pos += 32
}

# --- FPT block size (header bytes 6-7 BE; 0 -> dBASE default 512) ---
$bs = (([int]$fpt[6]) -shl 8) -bor ([int]$fpt[7])
if ($bs -le 0) { $bs = 512 }

function Get-MemoText([int]$ptr) {
  if ($ptr -le 0) { return '' }
  $o = $ptr * $bs
  if ($o + 8 -gt $fpt.Length) { return $null }
  $len = (([int]$fpt[$o+4]) -shl 24) -bor (([int]$fpt[$o+5]) -shl 16) -bor (([int]$fpt[$o+6]) -shl 8) -bor ([int]$fpt[$o+7])
  if ($len -lt 0 -or $o + 8 + $len -gt $fpt.Length) { return $null }
  return $enc.GetString($fpt, $o + 8, $len)
}

# --- locate target record by OBJNAME ---
$fObj    = $fields | Where-Object { $_.Name -eq 'OBJNAME' }
$fMemo   = $fields | Where-Object { $_.Name -eq $MemoField }
$fObjCod = $fields | Where-Object { $_.Name -eq 'OBJCODE' }
if (-not $fMemo) { Write-Error "No field '$MemoField' in $ScxPath"; exit 1 }

$targetRec = -1
$oldText   = $null
for ($r = 0; $r -lt $recCount; $r++) {
  $base = $hdrLen + ($r * $recLen)
  if ($base + $recLen -gt $dbf.Length) { break }
  if ($dbf[$base] -eq 0x2A) { continue }
  $objPtr = [BitConverter]::ToInt32($dbf, $base + $fObj.Off)
  if ((Get-MemoText $objPtr) -eq $ObjName) {
    $memoPtr = [BitConverter]::ToInt32($dbf, $base + $fMemo.Off)
    $oldText = Get-MemoText $memoPtr
    if ($null -eq $oldText) { $oldText = '' }
    # preserve original block type (VFP writes type=1 in SCT/VCT memos)
    $memoType = 0
    if ($memoPtr -gt 0 -and ($memoPtr * $bs + 4) -le $fpt.Length) {
      $memoType = (([int]$fpt[$memoPtr*$bs]) -shl 24) -bor (([int]$fpt[$memoPtr*$bs+1]) -shl 16) -bor (([int]$fpt[$memoPtr*$bs+2]) -shl 8) -bor [int]$fpt[$memoPtr*$bs+3]
    }
    $targetRec = $r
    break
  }
}
if ($targetRec -lt 0) { Write-Error "No record with OBJNAME='$ObjName' found"; exit 1 }

# --- build new memo text ---
if ($Append) {
  $newText = $oldText + $Replace
} elseif ($Find -ne '') {
  if (-not $oldText.Contains($Find)) { Write-Error "Find text not present in $MemoField of '$ObjName'"; exit 1 }
  $newText = $oldText.Replace($Find, $Replace)
} else {
  $newText = $Replace
}
if ($newText -eq $oldText) { Write-Error "No change made (new text identical)"; exit 1 }

"Record #$targetRec ('$ObjName'), field $MemoField : $($oldText.Length) -> $($newText.Length) chars"

# --- append new memo block at end of FPT, aligned to block size ---
# block layout: [4-byte BE type (0 = text)] [4-byte BE length] [data]
$data = $enc.GetBytes($newText)
$newBlock = [math]::Ceiling($fpt.Length / $bs)
$ms = New-Object System.IO.MemoryStream
$ms.Write($fpt, 0, $fpt.Length)
$pad = ($newBlock * $bs) - $fpt.Length
if ($pad -gt 0) { $ms.Write(@(0)*$pad, 0, $pad) }
$typeBE = [BitConverter]::GetBytes([System.Net.IPAddress]::HostToNetworkOrder([int]$memoType))
$ms.Write($typeBE, 0, 4)
$lenBE = [BitConverter]::GetBytes([System.Net.IPAddress]::HostToNetworkOrder([int]$data.Length))
$ms.Write($lenBE, 0, 4)
$ms.Write($data, 0, $data.Length)
$newFpt = $ms.ToArray()

# header bytes 0-3 (BE) = next free block
$nextFree = [math]::Ceiling($newFpt.Length / $bs)
$nf = [BitConverter]::GetBytes([System.Net.IPAddress]::HostToNetworkOrder([int]$nextFree))
$newFpt[0] = $nf[0]; $newFpt[1] = $nf[1]; $newFpt[2] = $nf[2]; $newFpt[3] = $nf[3]

# --- update pointer(s) in DBF record ---
$base = $hdrLen + ($targetRec * $recLen)
$ptrBytes = [BitConverter]::GetBytes([int]$newBlock)
for ($b = 0; $b -lt 4; $b++) { $dbf[$base + $fMemo.Off + $b] = $ptrBytes[$b] }
if ($ClearObjCode -and $fObjCod) {
  for ($b = 0; $b -lt 4; $b++) { $dbf[$base + $fObjCod.Off + $b] = 0 }
  "Cleared OBJCODE pointer (forces VFP recompile)."
}

# --- write files ---
[System.IO.File]::WriteAllBytes($ScxPath, $dbf)
[System.IO.File]::WriteAllBytes($memoPath, $newFpt)
"WROTE: $ScxPath ($($dbf.Length) bytes)"
"WROTE: $memoPath ($($newFpt.Length) bytes, was $($fpt.Length))"
