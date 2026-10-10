# Battery Health - ASUS Zenbook / Windows 11
# Doppio click per vedere la salute della batteria.

Add-Type -AssemblyName PresentationFramework

function Show-Msg([string]$msg, [string]$title, [string]$icon) {
    $btn = [System.Windows.MessageBoxButton]::OK
    $ic  = switch ($icon) {
        "Error"       { [System.Windows.MessageBoxImage]::Error }
        "Information" { [System.Windows.MessageBoxImage]::Information }
        default       { [System.Windows.MessageBoxImage]::Information }
    }
    [System.Windows.MessageBox]::Show($msg, $title, $btn, $ic) | Out-Null
}

try {
    $ErrorActionPreference = "Stop"

    function Get-BatteryReportPath {
        $temp = Join-Path $env:TEMP "battery-report.html"
        powercfg /batteryreport /output "$temp" | Out-Null
        if (Test-Path $temp) { return $temp }
        return $null
    }

    $report = Get-BatteryReportPath

    if (-not $report) {
        Show-Msg "Impossibile creare il report della batteria. Prova ad avviare lo script come amministratore." "Battery Health" "Error"
        return
    }

    $html = Get-Content -Raw -Path $report

    $rxOpts = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline

    $designMatch = [regex]::Match($html, 'DESIGN CAPACITY.*?([0-9][0-9,\.]*)\s*mWh', $rxOpts)
    $fullMatch   = [regex]::Match($html, 'FULL CHARGE CAPACITY.*?([0-9][0-9,\.]*)\s*mWh', $rxOpts)
    $cycleMatch  = [regex]::Match($html, 'CYCLE COUNT.*?([0-9]+)', $rxOpts)

    function ConvertTo-Number([string]$s) {
        if ([string]::IsNullOrWhiteSpace($s)) { return 0 }
        return [double](($s -replace '[^0-9]', ''))
    }

    $design = ConvertTo-Number $designMatch.Groups[1].Value
    $full   = ConvertTo-Number $fullMatch.Groups[1].Value
    $cycles = if ($cycleMatch.Success) { [int]$cycleMatch.Groups[1].Value } else { "N/D" }

    if ($design -le 0 -or $full -le 0) {
        Show-Msg "Non sono riuscito a leggere i dati della batteria dal report generato.`n`nFile report: $report" "Battery Health" "Error"
        return
    }

    $health = [math]::Round(($full / $design) * 100, 1)
    $wear   = [math]::Round(100 - $health, 1)

    $message = @"
🔋 SALUTE BATTERIA

Capacità massima: $health%
Usura: $wear%

Capacità attuale: $([math]::Round($full,0).ToString("N0")) mWh
Capacità originale: $([math]::Round($design,0).ToString("N0")) mWh
Cicli di ricarica: $cycles

Il valore è calcolato come:
capacità attuale ÷ capacità originale × 100
"@

    Show-Msg $message "Battery Health - ASUS Zenbook" "Information"
}
catch {
    # Qualsiasi errore imprevisto viene mostrato invece di chiudere la finestra senza spiegazioni
    Show-Msg "Si è verificato un errore imprevisto:`n`n$($_.Exception.Message)`n`nRiga: $($_.InvocationInfo.ScriptLineNumber)" "Battery Health - Errore" "Error"
}