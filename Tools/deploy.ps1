<#
    deploy.ps1 — Deploy AltTracker + its on-demand plugins to the WoW AddOns folder.

    The repo keeps the plugins under Plugins/ for organization, but WoW only
    discovers addons as TOP-LEVEL folders under Interface/AddOns. So this script
    fans the sources out into three sibling AddOns folders:

        <repo root>            -> AddOns/AltTracker            (core, minus Plugins/)
        Plugins/Professions/   -> AddOns/AltTrackerProfessions (Recipes, LoadOnDemand)
        Plugins/Roster/        -> AddOns/AltTrackerRoster      (Roster,  LoadOnDemand)
        Plugins/Instances/     -> AddOns/AltTrackerInstances   (Raids,   LoadOnDemand)

    Usage:
        pwsh Tools/deploy.ps1
        pwsh Tools/deploy.ps1 -AddOnsPath "D:\Games\WoW\_anniversary_\Interface\AddOns"
#>

param(
    [string]$AddOnsPath = "C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns"
)

$ErrorActionPreference = "Stop"

# Repo root = parent of this script's folder.
$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $AddOnsPath)) {
    Write-Error "AddOns path not found: $AddOnsPath"
    exit 1
}

function Deploy-Tree($src, $destName, [string[]]$excludeDirs, [string[]]$excludeFiles, [switch]$Mirror) {
    $dest = Join-Path $AddOnsPath $destName
    Write-Host "Deploying $destName ..." -ForegroundColor Cyan
    # /MIR mirrors (purges stale files in dest) — used for the plugin folders,
    # which we own wholesale, so old files (e.g. dead ...Model.lua) get removed.
    # SavedVariables live in WTF\, not here, so purging is safe.
    # /E copies without purging — used for the core folder so unrelated files
    # already in AddOns\AltTracker (zips, etc.) are left alone.
    # robocopy exit codes 0-7 are success; 8+ is an error.
    $mode = if ($Mirror) { "/MIR" } else { "/E" }
    $args = @($src, $dest, $mode, "/NFL", "/NDL", "/NJH", "/NJS", "/NP")
    if ($excludeDirs)  { $args += "/XD"; $args += $excludeDirs }
    if ($excludeFiles) { $args += "/XF"; $args += $excludeFiles }
    robocopy @args | Out-Null
    if ($LASTEXITCODE -ge 8) { Write-Error "robocopy failed for $destName (code $LASTEXITCODE)"; exit 1 }
}

# Core AltTracker: everything at the repo root except the Plugins/ tree, the
# dev tooling, VCS, and scratch/log files (harmless in-game but noise on disk).
$coreExcludeDirs = @(
    (Join-Path $RepoRoot "Plugins"),
    (Join-Path $RepoRoot "Tools"),
    (Join-Path $RepoRoot ".git"),
    (Join-Path $RepoRoot ".github"),
    (Join-Path $RepoRoot ".claude")
)
$coreExcludeFiles = @("*.log", "*.zip", "settings.ini", "*.md")

Deploy-Tree $RepoRoot            "AltTracker"            $coreExcludeDirs $coreExcludeFiles
Deploy-Tree (Join-Path $RepoRoot "Plugins\Professions") "AltTrackerProfessions" @() @() -Mirror
Deploy-Tree (Join-Path $RepoRoot "Plugins\Roster")      "AltTrackerRoster"      @() @() -Mirror
Deploy-Tree (Join-Path $RepoRoot "Plugins\Instances")   "AltTrackerInstances"   @() @() -Mirror

Write-Host "Done. Deployed to $AddOnsPath" -ForegroundColor Green
Write-Host "In-game: /reload  (keep AltTrackerProfessions & AltTrackerRoster enabled in the AddOns list)."
