[CmdletBinding()]
param(
  [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$failures = [System.Collections.Generic.List[string]]::new()
$markdownFiles = Get-ChildItem -LiteralPath $Root -Filter '*.md' -File -Recurse |
  Where-Object { $_.FullName -notmatch '[\\/]\.(terraform|cache)[\\/]' }

foreach ($file in $markdownFiles) {
  $text = Get-Content -LiteralPath $file.FullName -Raw
  $linkMatches = [regex]::Matches($text, '(?<!\!)\[[^\]]+\]\((?<target>[^)]+)\)')
  foreach ($match in $linkMatches) {
    $target = $match.Groups['target'].Value.Trim().Trim('<', '>')
    if ($target -match '^(https?://|mailto:|#)') { continue }
    $pathOnly = ($target -split '#', 2)[0]
    if (-not $pathOnly) { continue }
    $decoded = [uri]::UnescapeDataString($pathOnly)
    $candidate = Join-Path $file.DirectoryName ($decoded -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $candidate)) {
      $relativeFile = [IO.Path]::GetRelativePath($Root, $file.FullName)
      $failures.Add("${relativeFile}: missing local link target '$target'")
    }
  }
}

if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
  throw "$($failures.Count) local Markdown link(s) are broken."
}

Write-Host "Checked $($markdownFiles.Count) Markdown files; local links are valid."
