# deploy-probe.ps1 — copy Wick's Probe into every installed WoW flavor.
#
# The Forever beta's install folder name is not documented, so this script
# discovers it: it enumerates the flavor directories under the WoW root and
# flags anything it has not seen before.
#
#   powershell -File WickSuite\tools\deploy-probe.ps1            # list + copy
#   powershell -File WickSuite\tools\deploy-probe.ps1 -ListOnly  # just look
#   powershell -File WickSuite\tools\deploy-probe.ps1 -Flavor _forever_

param(
    [string] $WowRoot = "C:\Program Files (x86)\World of Warcraft",
    [string] $Source  = "C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\WicksProbe",
    [string] $Flavor  = "",
    [switch] $ListOnly
)

$ErrorActionPreference = "Stop"

# Flavors that existed before the Forever beta. Anything outside this list is
# new and worth reporting by name.
$known = @("_retail_", "_classic_", "_classic_era_", "_anniversary_", "_ptr_", "_classic_ptr_", "_classic_era_ptr_", "_xptr_", "_beta_")

if (-not (Test-Path $Source)) {
    Write-Error "Probe source not found: $Source"
}

$flavors = Get-ChildItem $WowRoot -Directory |
    Where-Object { $_.Name -like "_*_" } |
    Select-Object -ExpandProperty Name

Write-Host ""
Write-Host "WoW root: $WowRoot"
Write-Host "Flavors found:"
foreach ($f in $flavors) {
    $isNew = -not ($known -contains $f)
    $tag = if ($isNew) { "  <-- NEW, not a flavor this script knew about" } else { "" }
    Write-Host ("  {0}{1}" -f $f, $tag)
}
Write-Host ""

if ($ListOnly) { return }

$targets = if ($Flavor) { @($Flavor) } else { $flavors }

foreach ($f in $targets) {
    $addons = Join-Path $WowRoot "$f\Interface\AddOns"
    if (-not (Test-Path $addons)) {
        Write-Host "skip  $f  (no Interface\AddOns yet - launch the client once)"
        continue
    }

    $dest = Join-Path $addons "WicksProbe"
    if ((Resolve-Path $Source).Path -eq (Resolve-Path -ErrorAction SilentlyContinue $dest).Path) {
        Write-Host "skip  $f  (this is the source copy)"
        continue
    }

    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item (Join-Path $Source "*") -Destination $dest -Recurse -Force
    Write-Host "copy  $f  ->  $dest"
}

Write-Host ""
Write-Host "In-game: enable 'Load out of date AddOns' on the character select"
Write-Host "AddOns list, then /wickprobe full, then log out to flush SavedVariables."
Write-Host "Report lands in <flavor>\WTF\Account\<account>\SavedVariables\WicksProbe.lua"
