# connect-to-mt.ps1 - URL handler for winbox:// and mt:// links (PowerShell version).
#
#   winbox://[user[:password]@]host[:port]
#
# host: hostname or IPv4. port: defaults to 8291.
# The password may be percent-encoded (%40 = '@'), and may also contain a raw
# '@', '/', '?' or '#', because user info is split at the LAST '@'.
#
# Register as the handler with this command line:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\path\connect-to-mt.ps1" "%1"
param(
    [Parameter(Position = 0)]
    [string]$Url
)

$ErrorActionPreference = 'Stop'
$DefaultPort = 8291

# There is no visible console when launched from a link, so show errors in a dialog.
function Show-Error([string]$Message) {
    try { (New-Object -ComObject WScript.Shell).Popup($Message, 0, 'MikroTik URL Handler', 16) | Out-Null }
    catch { [Console]::Error.WriteLine($Message) }
    exit 1
}

# Hostname or IPv4. Anything made only of digits and dots must be a valid IPv4
# address (rejects 10.0.0.256, 1.2.3).
function Test-MtHost([string]$Name) {
    if ($Name -match '^[0-9.]+$') {
        return $Name -match '^((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$'
    }
    return $Name -match '^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*\.?$'
}

# Extract host, port, user and password from the URL. Throws on invalid input.
function ConvertFrom-MtUrl([string]$Raw) {
    $s = $Raw.Trim() -replace '^(winbox|mt):(//)?', ''    # -replace is case-insensitive
    $user = ''; $pass = ''; $hasPass = $false

    $at = $s.LastIndexOf('@')
    if ($at -ge 0) {
        $info = $s.Substring(0, $at)
        $s = $s.Substring($at + 1)
        $colon = $info.IndexOf(':')
        if ($colon -ge 0) {
            $user = $info.Substring(0, $colon)
            $pass = $info.Substring($colon + 1)
            $hasPass = $true
        } else {
            $user = $info
        }
        $user = [Uri]::UnescapeDataString($user)
        $pass = [Uri]::UnescapeDataString($pass)
    }

    # Drop any path / query / fragment (browsers often append a trailing '/').
    $s = $s -replace '[/?#].*$', ''
    if (-not $s) { throw 'No host specified.' }

    $hostName = $s
    $port = "$DefaultPort"
    $colon = $s.LastIndexOf(':')
    if ($colon -ge 0) {
        $hostName = $s.Substring(0, $colon)
        if ($colon -lt $s.Length - 1) { $port = $s.Substring($colon + 1) }
    }

    if ($port -notmatch '^\d{1,5}$' -or [int]$port -lt 1 -or [int]$port -gt 65535) { throw "Invalid port: $port" }
    if (-not (Test-MtHost $hostName)) { throw "Invalid host: $hostName" }

    [pscustomobject]@{
        Host        = $hostName
        Port        = [int]$port
        User        = $user
        Password    = $pass
        HasPassword = $hasPass
    }
}

# Quote one argument for the Windows command line, so a password with spaces
# or quotes reaches WinBox as a single, unchanged argument.
function ConvertTo-ProcessArg([string]$Arg) {
    if ($Arg -and $Arg -notmatch '[\s"]') { return $Arg }
    '"' + ($Arg -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

# --- main ---
if (-not $Url) { Show-Error 'No URL specified.' }

try { $t = ConvertFrom-MtUrl $Url }
catch { Show-Error $_.Exception.Message }

$candidates = @(
    (Join-Path $PSScriptRoot 'WinBox.exe'),
    (Join-Path $PSScriptRoot 'winbox64.exe'),
    "$env:ProgramFiles\winbox\WinBox.exe",
    "$env:ProgramFiles\winbox\winbox64.exe"
)
$winbox = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $winbox) { Show-Error ("WinBox not found. Looked for:`n" + ($candidates -join "`n")) }

$wbArgs = @("$($t.Host):$($t.Port)")
if ($t.User -and $t.HasPassword) { $wbArgs += $t.User, $t.Password }

$psi = New-Object System.Diagnostics.ProcessStartInfo $winbox
$psi.Arguments = ($wbArgs | ForEach-Object { ConvertTo-ProcessArg $_ }) -join ' '
$psi.UseShellExecute = $false
$psi.WorkingDirectory = Split-Path -Parent $winbox

try { [System.Diagnostics.Process]::Start($psi) | Out-Null }
catch { Show-Error "Failed to launch ${winbox}: $($_.Exception.Message)" }
