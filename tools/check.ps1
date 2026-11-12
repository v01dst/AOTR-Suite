<#
	AOTR Suite :: check
	Verifies that every source file and the bundled build parse as Luau.

	Usage:
		powershell -ExecutionPolicy Bypass -File tools\check.ps1
#>

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$luau = Join-Path $root "tools\luau\luau-compile.exe"

if (-not (Test-Path $luau)) {
	throw "Luau compiler not found at $luau"
}

$files = @()
$files += Get-ChildItem (Join-Path $root "src") -Recurse -Filter *.lua | ForEach-Object { $_.FullName }
$files += Get-ChildItem (Join-Path $root "vendor") -Filter *.lua | ForEach-Object { $_.FullName }
$files += Get-ChildItem (Join-Path $root "dist") -Filter *.lua -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }

$failed = 0
$ErrorActionPreference = "Continue"
foreach ($file in $files) {
	$output = & $luau --binary $file 2>&1 | Out-String
	if ($LASTEXITCODE -eq 0) {
		Write-Host ("OK    " + $file.Replace($root + "\", ""))
	} else {
		$failed = $failed + 1
		Write-Host ("FAIL  " + $file.Replace($root + "\", "")) -ForegroundColor Red
		($output -split "`r?`n") | Where-Object { $_ -match "Error" } | Select-Object -First 6 | ForEach-Object { Write-Host ("      " + $_.Trim()) -ForegroundColor DarkYellow }
	}
}

Write-Host ""
if ($failed -gt 0) {
	Write-Host "$failed file(s) failed to parse." -ForegroundColor Red
	exit 1
}
Write-Host "all files parse cleanly."

# ---------------------------------------------------------------------------
# Wiring check: every Ctx.<Module> that is used has to be built in main.lua
# ---------------------------------------------------------------------------

$ctxRefs = @{}
Get-ChildItem (Join-Path $root "src") -Recurse -Filter *.lua | ForEach-Object {
	$text = Get-Content $_.FullName -Raw
	[regex]::Matches($text, "Ctx\.([A-Za-z_]\w*)") | ForEach-Object {
		$ctxRefs[$_.Groups[1].Value] = $true
	}
}

$mainText = Get-Content (Join-Path $root "src\main.lua") -Raw
$built = @([regex]::Matches($mainText, 'build\("(\w+)"\)') | ForEach-Object { $_.Groups[1].Value })
$built += "Util"
$built += "Rayfield"
$built += "state"

$missing = @($ctxRefs.Keys | Where-Object { $built -notcontains $_ } | Sort-Object)
if ($missing.Count -gt 0) {
	Write-Host ""
	Write-Host "ctx wiring is incomplete, these are used but never built:" -ForegroundColor Red
	$missing | ForEach-Object { Write-Host "  Ctx.$_" -ForegroundColor DarkYellow }
	exit 1
}
Write-Host "ctx wiring is complete ($($ctxRefs.Count) references)."

# ---------------------------------------------------------------------------
# Bundle sanity check: every module has to end up in the built file
# ---------------------------------------------------------------------------

$bundle = Join-Path $root "dist\AOTR.lua"
if (Test-Path $bundle) {
	$bundleText = Get-Content $bundle -Raw
	$defined = @([regex]::Matches($bundleText, '__define\("(\w+)"') | ForEach-Object { $_.Groups[1].Value })
	$expected = @("Rayfield") + @([regex]::Matches((Get-Content (Join-Path $root "tools\build.ps1") -Raw), '"(\w+)"\s*=\s*Join-Path') | ForEach-Object { $_.Groups[1].Value })
	$missing = @($expected | Where-Object { $defined -notcontains $_ })
	if ($missing.Count -gt 0) {
		Write-Host ""
		Write-Host "the bundle is missing modules:" -ForegroundColor Red
		$missing | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
		exit 1
	}
	if ($bundleText -notmatch '__MOD\["main"\]\(__MOD\)') {
		Write-Host ""
		Write-Host "the bundle does not boot the main module." -ForegroundColor Red
		exit 1
	}
	Write-Host "bundle contains all $($expected.Count) modules and boots main."
}

