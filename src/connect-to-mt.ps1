param (
    [string]$Url
)

# הסרת ה-"mt://" וכל נתונים עודפים (path או query)
$cleanUrl = $Url -replace '^mt://', '' -replace '[/\?].*$', ''

# פונקציה לבדיקת hostname תקין (IP או דומיין)
function Test-Hostname {
    param (
        [string]$Hostname
    )
    # בדיקת IP תקין
    if ($Hostname -match '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$') {
        return $true
    }
    # בדיקת דומיין תקין (פשוט: אותיות, מספרים, מקפים, נקודות)
    if ($Hostname -match '^[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9](?:\.[a-zA-Z]{2,})+$') {
        return $true
    }
    return $false
}

# פירוק החלקים: עם או בלי username:password
if ($cleanUrl -match '^(?:(?:([^:]+):([^@]+)@)?([^:]+)(?::(\d+))?)$') {
    $username = $Matches[1]
    $password = $Matches[2]
    $hostname = $Matches[3]
    $port = if ($Matches[4]) { $Matches[4] } else { '8291' } # ברירת מחדל ל-8291 אם אין פורט

    # בדיקת hostname תקין
    if (-not (Test-Hostname -Hostname $hostname)) {
        Write-Output "Invalid hostname: $hostname"
        return
    }

    # בדיקת פורט תקין (1-65535)
    if ($port -notmatch '^\d+$' -or [int]$port -lt 1 -or [int]$port -gt 65535) {
        Write-Output "Invalid port: $port"
        return
    }

    # בניית הפקודה להפעלת winbox64.exe
    $winboxPath = "C:\Program Files\winbox\winbox64.exe"
    # אם אין username ו-password, השתמש רק ב-hostname:port
    $arguments = if ($username -and $password) {
        "$hostname`:$port $username $password"
    } else {
        "$hostname`:$port"
    }

    # הפעלת winbox64.exe עם Start-Process
    try {
        Start-Process -FilePath $winboxPath -ArgumentList $arguments -NoNewWindow
    } catch {
        Write-Output "Error running winbox64.exe: $_"
    }
} else {
    Write-Output "Invalid URL format"
}

