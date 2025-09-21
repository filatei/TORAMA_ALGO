# Central repo folders (your GitHub repo path)
$repoExperts = "C:\Users\trader\TORAMA_ALGO\experts"
$repoInclude = "C:\Users\trader\TORAMA_ALGO\include"

# Find all MT5 terminals under AppData\Roaming\MetaQuotes\Terminal
$mt5_terminals = Get-ChildItem "C:\Users\trader\AppData\Roaming\MetaQuotes\Terminal" -Directory

foreach ($terminal in $mt5_terminals) {
    # Target paths for symlinks
    $expertsPath = Join-Path $terminal.FullName "MQL5\Experts\TORAMA"
    $includePath = Join-Path $terminal.FullName "MQL5\Include\TORAMA"

    foreach ($pair in @(@{Repo=$repoExperts; Target=$expertsPath}, @{Repo=$repoInclude; Target=$includePath})) {
        $repo = $pair.Repo
        $target = $pair.Target

        if (-Not (Test-Path $repo)) {
            Write-Output "?? Repo folder not found: $repo. Skipping..."
            continue
        }

        # Remove existing folder/symlink if present
        if (Test-Path $target) {
            Write-Output "Removing old folder/symlink: $target"
            Remove-Item $target -Recurse -Force
        }

        # Ensure parent directory exists
        $parent = Split-Path $target -Parent
        if (-Not (Test-Path $parent)) {
            Write-Output "Creating parent folder: $parent"
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }

        # Create symlink
        Write-Output "Creating symlink: $target -> $repo"
        cmd /c mklink /D "$target" "$repo"
    }
}

Write-Output "? All MT5 terminals linked to Experts + Include from repo."
