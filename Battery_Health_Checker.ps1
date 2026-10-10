# Battery Health Checker - Windows 10/11
# Provetta: l'altezza e' la batteria nuova (100%). Il liquido pieno e' la carica
# attuale, il velo e' la capacita' ancora disponibile, il vuoto in alto e' quella persa.
# La carica e' sempre una frazione della capacita' attuale: il liquido non supera mai il velo.
# Tema chiaro/scuro, stime sulla vita residua (soglie 80% e 50%).
#
# NOTA: script scritto e revisionato staticamente, NON eseguito su un ambiente
# Windows reale (chi l'ha scritto aveva solo Linux). Prova prima il .ps1.

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

function Show-ErrorBox([string]$msg) {
    [System.Windows.MessageBox]::Show($msg, "Battery Health - Errore",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error) | Out-Null
}

try {
    $ErrorActionPreference = "Stop"
    $inv = [System.Globalization.CultureInfo]::InvariantCulture   # numeri dentro il XAML
    $it  = [System.Globalization.CultureInfo]::GetCultureInfo("it-IT")  # numeri mostrati (virgola)

    # --- Dati live: API Windows, senza file o battery report -------------------
    function Get-LiveBatteryState {
        try {
            $powerStatus = [System.Windows.Forms.SystemInformation]::PowerStatus
            $percent = [math]::Round($powerStatus.BatteryLifePercent * 100)
            if ($percent -lt 0 -or $percent -gt 100) { return $null }

            [pscustomobject]@{
                Charge     = [int]$percent
                IsCharging = $powerStatus.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Online
            }
        } catch {
            return $null
        }
    }

    # --- Dati diagnostici: report temporaneo, creato soltanto all'avvio ---------
    $script:report = $null
    $tempReportPrefix = 'BatteryHealth-Report-'
    Get-ChildItem -Path $env:TEMP -Filter "$tempReportPrefix*.html" -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue

    function ConvertTo-Number([string]$s) {
        if ([string]::IsNullOrWhiteSpace($s)) { return 0 }
        return [double](($s -replace '[^0-9]', ''))
    }

    function Get-BatteryDiagnostics {
        $script:report = Join-Path $env:TEMP ("{0}{1}.html" -f $tempReportPrefix, [guid]::NewGuid().ToString('N'))
        try {
            & powercfg /batteryreport /output $script:report 2>$null | Out-Null
            if (-not (Test-Path -LiteralPath $script:report)) { return $null }

            $html = Get-Content -Raw -LiteralPath $script:report -ErrorAction Stop
            $rxOpts = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline
            $designMatch = [regex]::Match($html, 'DESIGN CAPACITY.*?([0-9][0-9,\.]*)\s*mWh', $rxOpts)
            $fullMatch   = [regex]::Match($html, 'FULL CHARGE CAPACITY.*?([0-9][0-9,\.]*)\s*mWh', $rxOpts)
            $cycleMatch  = [regex]::Match($html, 'CYCLE COUNT.*?([0-9]+)', $rxOpts)

            [pscustomobject]@{
                Design = ConvertTo-Number $designMatch.Groups[1].Value
                Full   = ConvertTo-Number $fullMatch.Groups[1].Value
                Cycles = if ($cycleMatch.Success) { $cycleMatch.Groups[1].Value } else { 'N/D' }
            }
        } catch {
            return $null
        } finally {
            if ($script:report -and (Test-Path -LiteralPath $script:report)) {
                Remove-Item -LiteralPath $script:report -Force -ErrorAction SilentlyContinue
            }
            $script:report = $null
        }
    }

    function Get-XmlText([string]$s) {
        return [System.Security.SecurityElement]::Escape($s)
    }

    # Colori: "#FFRRGGBB" -> variante con trasparenza o piu' scura
    function Get-Argb([string]$hex, [int]$alpha) {
        return ('#{0:X2}{1}' -f $alpha, $hex.Substring(3))
    }
    function Get-Shade([string]$hex, [double]$k) {
        $r = [int]([Convert]::ToInt32($hex.Substring(3, 2), 16) * $k)
        $g = [int]([Convert]::ToInt32($hex.Substring(5, 2), 16) * $k)
        $b = [int]([Convert]::ToInt32($hex.Substring(7, 2), 16) * $k)
        return ('#FF{0:X2}{1:X2}{2:X2}' -f $r, $g, $b)
    }
    function Fmt([double]$v) { return $v.ToString("0.##", $inv) }

    $liveBattery = Get-LiveBatteryState
    $diagnostics = Get-BatteryDiagnostics
    $hasDiagnostics = $diagnostics -and $diagnostics.Design -gt 0 -and $diagnostics.Full -gt 0

    # Palette di stato del liquido: lime nel tema scuro, verde acqua nel chiaro
    # (il lime su sfondo chiaro non si legge). Le chiavi sono le stesse nei due temi.
    $statusDark  = @{ Good = "#FFC6F24A"; Ok = "#FFF2C84A"; Worn = "#FFF5A03C"; Bad = "#FFFF5D5D"; None = "#FF7B8A98" }
    $statusLight = @{ Good = "#FF10A07A"; Ok = "#FFD4A017"; Worn = "#FFE0701A"; Bad = "#FFD92D3A"; None = "#FF6B7785" }
    $script:isDarkMode = $true

    if ($hasDiagnostics) {
        $design = $diagnostics.Design
        $full   = $diagnostics.Full
        $cycles = $diagnostics.Cycles
        $health = [math]::Round(($full / $design) * 100, 1)
        $wear   = [math]::Max(0, [math]::Round(100 - $health, 1))

        if     ($health -ge 80) { $healthKey = "Good" }
        elseif ($health -ge 60) { $healthKey = "Ok" }
        elseif ($health -ge 40) { $healthKey = "Worn" }
        else                    { $healthKey = "Bad" }
        $color = $statusDark[$healthKey]

        $healthNumText = $health.ToString("0.#", $it) + "%"
        $fullNumText   = [math]::Round($full, 0).ToString("N0", $it)
        $designNumText = [math]::Round($design, 0).ToString("N0", $it)
        $footerRight   = "$fullNumText / $designNumText mWh"
        $capVis        = "Visible"
    } else {
        # Un errore diagnostico non deve impedire l'uso della lettura live.
        $design = 0; $full = 0; $cycles = 'N/D'; $health = 0; $wear = 0
        $healthKey = "None"
        $color = $statusDark[$healthKey]
        $healthNumText = "N/D"
        $footerRight = ""
        $capVis = "Collapsed"
    }

    # --- Modello PC (testo non fidato: pulito e poi escapato per XAML) -----------
    $pcModel = try {
        $sys = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($sys -and $sys.Model -and $sys.Model -notmatch "To be filled by O.E.M.|System Product Name") {
            $sys.Model.Trim()
        } else {
            $env:COMPUTERNAME
        }
    } catch {
        "PC Windows"
    }
    $pcModel = ($pcModel -replace '[\x00-\x1F]', ' ').Trim()
    if ($pcModel.Length -gt 48) { $pcModel = $pcModel.Substring(0, 48) }
    $pcModelXml = Get-XmlText $pcModel

    # --- Stime di vita residua (estrapolazione lineare dell'usura per ciclo) ----
    # Windows non espone la frequenza futura di ricarica: 1 ciclo completo ogni
    # 2 giorni per la conversione in tempo. Soglie: 80% e 50% (insostenibile).
    function Format-Horizon([double]$cyclesLeft) {
        $n = [math]::Max(1, [math]::Round($cyclesLeft))
        if ($n -gt 9999) { return [pscustomobject]@{ Cycles = "9999+ cicli"; Span = "" } }
        $days = $n * 2
        if ($days -ge 730) {
            $span = "~{0} anni" -f ([math]::Round($days / 365, 1)).ToString("0.#", $it)
        } elseif ($days -ge 60) {
            $span = "~{0} mesi" -f ([math]::Round($days / 30)).ToString("0", $it)
        } else {
            $span = "~{0} giorni" -f $days.ToString("0", $it)
        }
        return [pscustomobject]@{ Cycles = ("~{0} cicli" -f $n.ToString("0", $it)); Span = $span }
    }

    $numericCycles = 0
    if ($cycles -match '^\d+$') { $numericCycles = [double]$cycles }
    $wearPerCycle = if ($numericCycles -gt 0) { $wear / $numericCycles } else { 0 }

    $est80 = [pscustomobject]@{ Cycles = "N/D"; Span = "" }
    $est50 = [pscustomobject]@{ Cycles = "N/D"; Span = "" }
    if ($hasDiagnostics) {
        if ($health -le 80) {
            $est80 = [pscustomobject]@{ Cycles = "Raggiunta"; Span = "" }
        } elseif ($wearPerCycle -gt 0) {
            $est80 = Format-Horizon (($health - 80) / $wearPerCycle)
        }
        if ($health -le 50) {
            $est50 = [pscustomobject]@{ Cycles = "Raggiunta"; Span = "" }
        } elseif ($wearPerCycle -gt 0) {
            $est50 = Format-Horizon (($health - 50) / $wearPerCycle)
        }
    }
    $est80Cycles = Get-XmlText $est80.Cycles; $est80Span = Get-XmlText $est80.Span
    $est50Cycles = Get-XmlText $est50.Cycles; $est50Span = Get-XmlText $est50.Span

    # --- Geometria della provetta -------------------------------------------------
    # Area interna 76 x 426 (bordo di 2 px). y(p) = posizione del p% della batteria nuova.
    # La carica di Windows e' una percentuale della capacita' ATTUALE: nella provetta il
    # liquido e' alto  capacita% x carica%  (es. 88,4% x 100% = 88,4%), quindi non supera
    # mai il velo, anche quando il numero della carica (100%) e' maggiore di quello della capacita'.
    $tubeInnerH = 426.0
    $capPct = if ($hasDiagnostics) { [math]::Min(100.0, [double]$health) } else { 100.0 }
    function Get-InnerY([double]$pct)  { return $tubeInnerH * (1.0 - $pct / 100.0) }
    function Get-CanvasY([double]$pct) { return 2.0 + (Get-InnerY $pct) }

    # Testo breve nella targhetta della carica
    function Get-ChargeCaption([bool]$charging, [int]$charge) {
        if ($charging)      { return "in carica" }
        if ($charge -ge 20) { return "carica" }
        if ($charge -ge 10) { return "scarica" }
        return "critica"
    }

    $chargeNow = if ($liveBattery) { [int]$liveBattery.Charge } else { 0 }
    $chargeTotalPct = $capPct * $chargeNow / 100.0
    $script:capTargetH = if ($hasDiagnostics) { $tubeInnerH * $capPct / 100.0 } else { 0.0 }
    $script:chargeTargetH = $tubeInnerH * $chargeTotalPct / 100.0
    if ($chargeNow -gt 0 -and $script:chargeTargetH -lt 2) { $script:chargeTargetH = 2.0 }
    $script:chargeShown = $chargeNow

    $chargeVis  = if ($liveBattery) { "Visible" } else { "Collapsed" }
    $chargeTextInit = if ($liveBattery) { "$chargeNow%" } else { "N/D" }
    $chargeCaptionInit = if ($liveBattery) { Get-ChargeCaption ([bool]$liveBattery.IsCharging) $chargeNow } else { "" }

    $capLabelTop    = Fmt ((Get-CanvasY $capPct) - 16.0)
    $capLeaderTop   = Fmt ((Get-CanvasY $capPct) - 0.75)
    $est80Top = Fmt ((Get-CanvasY 80) - 7.0)
    $est50Top = Fmt ((Get-CanvasY 50) - 7.0)
    $y80i = Fmt (Get-InnerY 80)
    $y50i = Fmt (Get-InnerY 50)
    $zeroTop = Fmt ((Get-CanvasY 0) - 7.0)
    $topTop  = Fmt ((Get-CanvasY 100) - 7.0)

    # Colori del liquido (seguono lo stato di salute)
    $capFillTop  = Get-Argb $color 0x4D
    $capFillBot  = Get-Argb (Get-Shade $color 0.8) 0x2E
    $capLine     = Get-Argb $color 0xBF
    $chargeTopC  = $color
    $chargeBotC  = Get-Shade $color 0.8

    # Graduazione a destra: tacche minori ogni 10%, maggiori su 50% e 80%
    $ticksXaml = ""
    foreach ($p in 10, 30, 40, 60, 70, 90) {
        $ty = Fmt ((Get-CanvasY $p) - 0.5)
        $ticksXaml += "<Rectangle Canvas.Left=`"184`" Canvas.Top=`"$ty`" Width=`"6`" Height=`"1`" Fill=`"{DynamicResource TickBrush}`" IsHitTestVisible=`"False`"/>`n"
    }
    foreach ($p in 50, 80) {
        $ty = Fmt ((Get-CanvasY $p) - 0.75)
        $ticksXaml += "<Rectangle Canvas.Left=`"184`" Canvas.Top=`"$ty`" Width=`"12`" Height=`"1.5`" Fill=`"{DynamicResource TextSecondaryBrush}`" IsHitTestVisible=`"False`"/>`n"
    }

    # --- Dimensione finestra: la card si adatta all'area di lavoro ---------------
    $designW = 400.0; $designH = 640.0
    $workH = [System.Windows.SystemParameters]::WorkArea.Height
    $fit = [math]::Min(1.0, ($workH - 8.0) / $designH)
    if ($fit -lt 0.5) { $fit = 0.5 }
    $winW = ($designW * $fit).ToString("0.##", $inv)
    $winH = ($designH * $fit).ToString("0.##", $inv)
    $stageH = $designH.ToString("0.##", $inv)

    $motionOn = [System.Windows.SystemParameters]::ClientAreaAnimation

    # --- XAML della finestra -----------------------------------------------------
    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Battery Health"
        Width="$winW" Height="$winH"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="Transparent"
        ResizeMode="NoResize"
        UseLayoutRounding="True"
        SnapsToDevicePixels="True"
        WindowStartupLocation="CenterScreen">
  <Window.Resources>
    <SolidColorBrush x:Key="CardBgBrush" Color="#FF0E141B"/>
    <SolidColorBrush x:Key="TextPrimaryBrush" Color="#FFE8EEF3"/>
    <SolidColorBrush x:Key="TextSecondaryBrush" Color="#FF7B8A98"/>
    <SolidColorBrush x:Key="TubeBgBrush" Color="#FF101A23"/>
    <SolidColorBrush x:Key="TubeBorderBrush" Color="#FF2A3844"/>
    <SolidColorBrush x:Key="TickBrush" Color="#FF3A4856"/>
    <SolidColorBrush x:Key="ThresholdBrush" Color="#A6E8EEF3"/>
  </Window.Resources>

  <Viewbox Stretch="Uniform">
    <Grid x:Name="Stage" Width="400" Height="$stageH">
      <Grid x:Name="CardRoot" Margin="24" Opacity="0" RenderTransformOrigin="0.5,0.5">
        <Grid.RenderTransform><ScaleTransform x:Name="CardScale" ScaleX="0.97" ScaleY="0.97"/></Grid.RenderTransform>

        <!-- Ombra su un livello separato dal contenuto -->
        <Border CornerRadius="20" Background="{DynamicResource CardBgBrush}" IsHitTestVisible="False">
          <Border.Effect><DropShadowEffect Color="Black" BlurRadius="30" ShadowDepth="8" Opacity="0.4"/></Border.Effect>
        </Border>

        <Border x:Name="Card" CornerRadius="20" Background="{DynamicResource CardBgBrush}">
          <Grid Margin="28">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Intestazione (trascinabile) -->
            <Grid x:Name="DragHandle" Grid.Row="0" Height="40" Background="Transparent" Margin="0,0,0,20">
              <StackPanel x:Name="HeaderText" VerticalAlignment="Center" HorizontalAlignment="Left" Opacity="0" MaxWidth="220">
                <StackPanel.RenderTransform><TranslateTransform x:Name="HeaderT" Y="8"/></StackPanel.RenderTransform>
                <TextBlock Text="Batteria" FontSize="22" FontWeight="Bold" Foreground="{DynamicResource TextPrimaryBrush}"
                           FontFamily="Segoe UI Variable Display, Segoe UI"/>
                <TextBlock Text="$pcModelXml" FontSize="11" Foreground="{DynamicResource TextSecondaryBrush}"
                           TextTrimming="CharacterEllipsis" FontFamily="Segoe UI Variable Text, Segoe UI"/>
              </StackPanel>

              <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                <!-- Slider tema -->
                <Button x:Name="ThemeButton" Width="52" Height="28" Margin="0,0,8,0"
                        FocusVisualStyle="{x:Null}" AutomationProperties.Name="Cambia tema chiaro/scuro" Cursor="Hand">
                  <Button.Template>
                    <ControlTemplate TargetType="Button">
                      <Grid Background="Transparent"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Grid>
                    </ControlTemplate>
                  </Button.Template>
                  <Grid Width="52" Height="28" RenderTransformOrigin="0.5,0.5">
                    <Grid.RenderTransform><ScaleTransform x:Name="SwitchScale" ScaleX="1" ScaleY="1"/></Grid.RenderTransform>
                    <Border x:Name="SwitchTrack" CornerRadius="14" BorderThickness="1.2" BorderBrush="{DynamicResource TubeBorderBrush}"/>
                    <Border x:Name="SwitchGlow" CornerRadius="14" BorderThickness="1.6" BorderBrush="{DynamicResource TextPrimaryBrush}" Opacity="0" IsHitTestVisible="False"/>
                    <Ellipse Width="22" Height="22" Fill="#FFF4F7F6" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="3,0,0,0">
                      <Ellipse.Effect><DropShadowEffect Color="Black" BlurRadius="6" ShadowDepth="1" Opacity="0.4"/></Ellipse.Effect>
                      <Ellipse.RenderTransform><TranslateTransform x:Name="KnobTranslate" X="0"/></Ellipse.RenderTransform>
                    </Ellipse>
                  </Grid>
                </Button>

                <!-- Chiusura -->
                <Button x:Name="CloseButton" Width="28" Height="28"
                        FocusVisualStyle="{x:Null}" AutomationProperties.Name="Chiudi" Cursor="Hand">
                  <Button.Template>
                    <ControlTemplate TargetType="Button">
                      <Grid Background="Transparent"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Grid>
                    </ControlTemplate>
                  </Button.Template>
                  <Grid Width="28" Height="28" RenderTransformOrigin="0.5,0.5">
                    <Grid.RenderTransform><ScaleTransform x:Name="CloseScale" ScaleX="1" ScaleY="1"/></Grid.RenderTransform>
                    <Ellipse x:Name="CloseHalo" Width="26" Height="26" Fill="{DynamicResource TextPrimaryBrush}" Opacity="0" IsHitTestVisible="False"/>
                    <TextBlock Text="&#x2715;" FontSize="12" Foreground="{DynamicResource TextSecondaryBrush}"
                               FontFamily="Segoe UI Variable Text, Segoe UI" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Grid>
                </Button>
              </StackPanel>
            </Grid>

            <!-- Provetta: 296 x 430. Sinistra = capacita' massima, centro = provetta con la targhetta della carica, destra = graduazione e stime -->
            <Canvas x:Name="TubeCanvas" Grid.Row="1" Width="296" Height="430" HorizontalAlignment="Left" VerticalAlignment="Top">

              <!-- Provetta (si allarga leggermente in hover) -->
              <Grid x:Name="TubeGroup" Canvas.Left="104" Canvas.Top="0" Width="80" Height="430" RenderTransformOrigin="0.5,0.5" IsHitTestVisible="False">
                <Grid.RenderTransform><ScaleTransform x:Name="TubeScale" ScaleX="1" ScaleY="1"/></Grid.RenderTransform>
                <Border CornerRadius="40" BorderThickness="2" BorderBrush="{DynamicResource TubeBorderBrush}" Background="{DynamicResource TubeBgBrush}">
                  <Grid Width="76" Height="426">
                    <Grid.Clip><RectangleGeometry Rect="0,0,76,426" RadiusX="38" RadiusY="38"/></Grid.Clip>

                    <!-- Capacita' ancora disponibile (velo) -->
                    <Border x:Name="CapLayer" VerticalAlignment="Bottom" Height="0" BorderThickness="0,1.5,0,0">
                      <Border.BorderBrush><SolidColorBrush x:Name="CapLineBrush" Color="$capLine"/></Border.BorderBrush>
                      <Border.Background>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                          <GradientStop x:Name="CapStopA" Color="$capFillTop" Offset="0"/>
                          <GradientStop x:Name="CapStopB" Color="$capFillBot" Offset="1"/>
                        </LinearGradientBrush>
                      </Border.Background>
                    </Border>

                    <!-- Carica attuale (liquido pieno) -->
                    <Border x:Name="ChargeLayer" VerticalAlignment="Bottom" Height="0">
                      <Border.Background>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                          <GradientStop x:Name="ChargeStopA" Color="$chargeTopC" Offset="0"/>
                          <GradientStop x:Name="ChargeStopB" Color="$chargeBotC" Offset="1"/>
                        </LinearGradientBrush>
                      </Border.Background>
                    </Border>

                    <!-- Riflesso del vetro -->
                    <Rectangle HorizontalAlignment="Left" Margin="14,0,0,0" Width="6" Height="426" RadiusX="3" RadiusY="3" IsHitTestVisible="False">
                      <Rectangle.Fill>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                          <GradientStop Color="#00FFFFFF" Offset="0"/>
                          <GradientStop Color="#24FFFFFF" Offset="0.3"/>
                          <GradientStop Color="#00FFFFFF" Offset="1"/>
                        </LinearGradientBrush>
                      </Rectangle.Fill>
                    </Rectangle>

                    <Canvas Width="76" Height="426" IsHitTestVisible="False">
                      <!-- Soglie 80% e 50% -->
                      <Line X1="0" X2="76" Y1="$y80i" Y2="$y80i" Stroke="{DynamicResource ThresholdBrush}" StrokeThickness="1.5" StrokeDashArray="3,3"/>
                      <Line X1="0" X2="76" Y1="$y50i" Y2="$y50i" Stroke="{DynamicResource ThresholdBrush}" StrokeThickness="1.5" StrokeDashArray="3,3"/>

                      <!-- Targhetta della carica: segue il livello del liquido, sempre leggibile e mai sovrapposta alla capacita' -->
                      <Border x:Name="ChargePill" Canvas.Left="6" Canvas.Top="366" Width="64" Height="40" CornerRadius="20"
                              Background="{DynamicResource CardBgBrush}" BorderThickness="1.2" BorderBrush="{DynamicResource TubeBorderBrush}"
                              Opacity="0" Visibility="$chargeVis">
                        <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                          <TextBlock x:Name="ChargePercentText" Text="$chargeTextInit" FontSize="17" FontWeight="SemiBold"
                                     LineHeight="20" LineStackingStrategy="BlockLineHeight" HorizontalAlignment="Center"
                                     Foreground="{DynamicResource TextPrimaryBrush}" Typography.NumeralAlignment="Tabular"
                                     FontFamily="Segoe UI Variable Display, Segoe UI">
                            <TextBlock.RenderTransform><TranslateTransform x:Name="PillTextT" Y="0"/></TextBlock.RenderTransform>
                          </TextBlock>
                          <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,-1,0,0">
                            <Path x:Name="BoltIcon" Data="M 4,0 L 0,6 L 3,6 L 2,10 L 7,3.5 L 4,3.5 Z" Width="7" Height="10" Stretch="Fill"
                                  Fill="{DynamicResource TextSecondaryBrush}" Margin="0,0,3,0" VerticalAlignment="Center" Visibility="Collapsed"/>
                            <TextBlock x:Name="ChargeCaption" Text="$chargeCaptionInit" FontSize="9.5"
                                       Foreground="{DynamicResource TextSecondaryBrush}" FontFamily="Segoe UI Variable Text, Segoe UI"/>
                          </StackPanel>
                        </StackPanel>
                      </Border>
                    </Canvas>
                  </Grid>
                </Border>
                <!-- Anello di evidenza in hover -->
                <Border x:Name="TubeRing" CornerRadius="40" BorderThickness="1.6" BorderBrush="{DynamicResource TextPrimaryBrush}" Opacity="0" IsHitTestVisible="False"/>
              </Grid>

              <!-- Sinistra: capacita' massima -->
              <Rectangle x:Name="CapLeader" Canvas.Left="94" Canvas.Top="$capLeaderTop" Width="10" Height="1.5" Fill="{DynamicResource TickBrush}" Visibility="$capVis" IsHitTestVisible="False"/>
              <Grid x:Name="CapLabel" Canvas.Left="-8" Canvas.Top="$capLabelTop" Width="96" Opacity="0" Visibility="$capVis" IsHitTestVisible="False">
                <Grid.RenderTransform><TranslateTransform x:Name="CapT" Y="6"/></Grid.RenderTransform>
                <StackPanel HorizontalAlignment="Right">
                  <TextBlock x:Name="CapNum" Text="$healthNumText" FontSize="24" FontWeight="SemiBold" HorizontalAlignment="Right"
                             Foreground="{DynamicResource TextPrimaryBrush}" Typography.NumeralAlignment="Tabular"
                             FontFamily="Segoe UI Variable Display, Segoe UI"/>
                  <TextBlock Text="Capacità Massima" FontSize="11" HorizontalAlignment="Right" Margin="0,-2,0,0"
                             Foreground="{DynamicResource TextSecondaryBrush}" FontFamily="Segoe UI Variable Text, Segoe UI"/>
                </StackPanel>
              </Grid>

              <!-- Destra: graduazione -->
              <TextBlock Canvas.Left="198" Canvas.Top="$topTop" Text="100%" FontSize="10" Foreground="{DynamicResource TextSecondaryBrush}" IsHitTestVisible="False" FontFamily="Segoe UI Variable Text, Segoe UI"/>
              <TextBlock Canvas.Left="198" Canvas.Top="$zeroTop" Text="0%" FontSize="10" Foreground="{DynamicResource TextSecondaryBrush}" IsHitTestVisible="False" FontFamily="Segoe UI Variable Text, Segoe UI"/>
              $ticksXaml

              <!-- Destra: stime -->
              <StackPanel x:Name="Est80" Canvas.Left="202" Canvas.Top="$est80Top" Opacity="0" IsHitTestVisible="False">
                <StackPanel.RenderTransform><TranslateTransform x:Name="Est80T" Y="6"/></StackPanel.RenderTransform>
                <TextBlock Text="80%" FontSize="10.5" Foreground="{DynamicResource TextSecondaryBrush}" FontFamily="Segoe UI Variable Text, Segoe UI"/>
                <TextBlock Text="$est80Cycles" FontSize="14" FontWeight="SemiBold" Margin="0,2,0,0" Foreground="{DynamicResource TextPrimaryBrush}" FontFamily="Segoe UI Variable Display, Segoe UI"/>
                <TextBlock Text="$est80Span" FontSize="11" Foreground="{DynamicResource TextSecondaryBrush}" FontFamily="Segoe UI Variable Text, Segoe UI"/>
              </StackPanel>
              <StackPanel x:Name="Est50" Canvas.Left="202" Canvas.Top="$est50Top" Opacity="0" IsHitTestVisible="False">
                <StackPanel.RenderTransform><TranslateTransform x:Name="Est50T" Y="6"/></StackPanel.RenderTransform>
                <TextBlock Text="50% insostenibile" FontSize="10.5" Foreground="{DynamicResource TextSecondaryBrush}" FontFamily="Segoe UI Variable Text, Segoe UI"/>
                <TextBlock Text="$est50Cycles" FontSize="14" FontWeight="SemiBold" Margin="0,2,0,0" Foreground="{DynamicResource TextPrimaryBrush}" FontFamily="Segoe UI Variable Display, Segoe UI"/>
                <TextBlock Text="$est50Span" FontSize="11" Foreground="{DynamicResource TextSecondaryBrush}" FontFamily="Segoe UI Variable Text, Segoe UI"/>
              </StackPanel>

              <!-- Area sensibile fissa, sopra a tutto: nessun sfarfallio ai bordi -->
              <Rectangle x:Name="TubeHit" Canvas.Left="84" Canvas.Top="0" Width="128" Height="430" Fill="Transparent"/>
            </Canvas>

            <!-- Piede: nota e energia -->
            <Grid Grid.Row="3" Margin="0,8,0,0">
              <TextBlock x:Name="AiNote" Text="*Stime effettuate da AI" FontSize="10" Foreground="{DynamicResource TextSecondaryBrush}"
                         HorizontalAlignment="Left" Opacity="0" FontFamily="Segoe UI Variable Text, Segoe UI"/>
              <TextBlock x:Name="EnergyNote" Text="$footerRight" FontSize="10" Foreground="{DynamicResource TextSecondaryBrush}"
                         HorizontalAlignment="Right" Opacity="0" Typography.NumeralAlignment="Tabular" FontFamily="Segoe UI Variable Text, Segoe UI"/>
            </Grid>
          </Grid>
        </Border>
      </Grid>
    </Grid>
  </Viewbox>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    # --- Helper animazioni --------------------------------------------------------
    # Regole: ease-out forte per ingressi e risposte, uscita piu' veloce dell'ingresso,
    # ogni animazione riparte dal valore corrente (interrompibile), movimento ridotto
    # di Windows = durate di 1 ms e nessuna animazione ripetuta.
    function New-EaseOut {
        $e = New-Object System.Windows.Media.Animation.QuarticEase
        $e.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
        return $e
    }

    # Piccolo assestamento "fisico" per il liquido (non per l'interfaccia)
    function New-SettleEase([double]$amplitude) {
        $e = New-Object System.Windows.Media.Animation.BackEase
        $e.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
        $e.Amplitude = $amplitude
        return $e
    }

    function New-Anim([double]$to, [int]$ms, $ease = $null, $from = $null, [int]$delayMs = 0) {
        $a = New-Object System.Windows.Media.Animation.DoubleAnimation
        if ($null -ne $from) { $a.From = [double]$from }
        $a.To = $to
        $dur = if ($motionOn) { $ms } else { 1 }
        $a.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds($dur))
        if ($motionOn -and $delayMs -gt 0) { $a.BeginTime = [TimeSpan]::FromMilliseconds($delayMs) }
        if (-not $ease) { $ease = New-EaseOut }
        $a.EasingFunction = $ease
        return $a
    }

    function Start-Scale($st, [double]$to, [int]$ms) {
        $st.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, (New-Anim $to $ms))
        $st.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, (New-Anim $to $ms))
    }

    function Start-Fade($el, [double]$to, [int]$ms) {
        $el.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-Anim $to $ms))
    }

    $opacityProp = [System.Windows.UIElement]::OpacityProperty
    $transYProp  = [System.Windows.Media.TranslateTransform]::YProperty
    $heightProp  = [System.Windows.FrameworkElement]::HeightProperty
    $scaleXProp  = [System.Windows.Media.ScaleTransform]::ScaleXProperty

    $cardRoot    = $window.FindName("CardRoot")
    $cardScale   = $window.FindName("CardScale")
    $tubeScale   = $window.FindName("TubeScale")
    $tubeRing    = $window.FindName("TubeRing")
    $tubeHit     = $window.FindName("TubeHit")
    $capLayer    = $window.FindName("CapLayer")
    $chargeLayer = $window.FindName("ChargeLayer")
    $capNum      = $window.FindName("CapNum")
    $aiNote      = $window.FindName("AiNote")
    $energyNote  = $window.FindName("EnergyNote")
    $pill        = $window.FindName("ChargePill")
    $pillTextT   = $window.FindName("PillTextT")
    $bolt        = $window.FindName("BoltIcon")
    $chargePercentText = $window.FindName("ChargePercentText")
    $chargeCaption     = $window.FindName("ChargeCaption")
    $capStopA    = $window.FindName("CapStopA")
    $capStopB    = $window.FindName("CapStopB")
    $capLineBrush = $window.FindName("CapLineBrush")
    $chargeStopA = $window.FindName("ChargeStopA")
    $chargeStopB = $window.FindName("ChargeStopB")
    $script:isChargingNow = if ($liveBattery) { [bool]$liveBattery.IsCharging } else { $false }

    # --- Numeri guidati dal liquido ------------------------------------------------
    # I numeri non hanno un timer proprio: leggono l'altezza reale del liquido a ogni
    # fotogramma, quindi restano sincronizzati con l'animazione (anche con l'assestamento).
    $script:countUp = $false

    function Sync-Pill {
        if (-not $liveBattery) { return }
        $h = $chargeLayer.ActualHeight
        # La targhetta segue la superficie, ma resta dentro la provetta (che e' tondeggiante)
        $center = [math]::Min(386.0, [math]::Max(40.0, $tubeInnerH - $h))
        [System.Windows.Controls.Canvas]::SetTop($pill, $center - 20.0)
        if ($script:countUp -and $script:chargeTargetH -gt 0) {
            $f = [math]::Min(1.0, [math]::Max(0.0, $h / $script:chargeTargetH))
            $chargePercentText.Text = ("{0}%" -f [int][math]::Round($script:chargeShown * $f))
        }
    }

    function Set-FinalTexts {
        $script:countUp = $false
        $capNum.Text = $healthNumText
        if ($liveBattery) { $chargePercentText.Text = ("{0}%" -f $script:chargeShown) }
    }

    $capLayer.Add_SizeChanged({
        try {
            if (-not $script:countUp -or $script:capTargetH -le 0) { return }
            $f = [math]::Min(1.0, [math]::Max(0.0, $capLayer.ActualHeight / $script:capTargetH))
            $capNum.Text = (([double]$health * $f).ToString("0.#", $it)) + "%"
        } catch { }
    })
    $chargeLayer.Add_SizeChanged({ try { Sync-Pill } catch { } })

    # --- Riempimento della provetta (apertura) -----------------------------------
    function Start-TubeFill([int]$baseDelay, [int]$capMs, [int]$chargeMs) {
        $script:countUp = [bool]$motionOn
        $capAnim = $null
        if ($script:capTargetH -gt 0) {
            $capAnim = New-Anim $script:capTargetH $capMs $null 0.0 $baseDelay
        }
        $chargeAnim = $null
        if ($script:chargeTargetH -gt 0) {
            # Il liquido sale un filo oltre e si assesta (come un liquido vero)
            $chargeAnim = New-Anim $script:chargeTargetH $chargeMs (New-SettleEase 0.3) 0.0 ($baseDelay + 100)
        }

        # I numeri tornano al valore finale quando finisce l'ultima animazione
        $last = if ($chargeAnim) { $chargeAnim } else { $capAnim }
        if ($last) { $last.Add_Completed({ Set-FinalTexts }) } else { Set-FinalTexts }

        if ($capAnim)    { $capLayer.BeginAnimation($heightProp, $capAnim) }
        if ($chargeAnim) { $chargeLayer.BeginAnimation($heightProp, $chargeAnim) }
    }

    # --- Hover: la provetta si allarga, il liquido "ondeggia" e si riassesta -------
    # Parte dal livello corrente (mai da zero): sempre interrompibile.
    function New-SloshAnim([double]$cur, [double]$target) {
        $dip = [math]::Min(7.0, $target * 0.04)
        $cubic = New-Object System.Windows.Media.Animation.CubicEase
        $cubic.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
        $t1 = [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds(110))
        $t2 = [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds(650))
        $k1 = New-Object System.Windows.Media.Animation.EasingDoubleKeyFrame -ArgumentList ([math]::Max(0.0, $cur - $dip)), $t1, $cubic
        $k2 = New-Object System.Windows.Media.Animation.EasingDoubleKeyFrame -ArgumentList $target, $t2, (New-EaseOut)
        $kf = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
        $kf.KeyFrames.Add($k1) | Out-Null
        $kf.KeyFrames.Add($k2) | Out-Null
        return $kf
    }

    function Start-Slosh {
        if (-not $motionOn) { return }
        Set-FinalTexts
        if ($script:capTargetH -gt 0) {
            $capLayer.BeginAnimation($heightProp, (New-SloshAnim $capLayer.ActualHeight $script:capTargetH))
        }
        if ($script:chargeTargetH -gt 0) {
            $chargeLayer.BeginAnimation($heightProp, (New-SloshAnim $chargeLayer.ActualHeight $script:chargeTargetH))
        }
    }

    function Complete-Tube {
        Set-FinalTexts
        if ($script:capTargetH -gt 0)    { $capLayer.BeginAnimation($heightProp, (New-Anim $script:capTargetH 180)) }
        if ($script:chargeTargetH -gt 0) { $chargeLayer.BeginAnimation($heightProp, (New-Anim $script:chargeTargetH 180)) }
    }

    # --- Ingresso: card + etichette a cascata (60 ms) + liquido ----------------------
    $script:entered = $false
    $sections = @(
        @{ El = "HeaderText"; T = "HeaderT"; Delay = 40  },
        @{ El = "CapLabel";   T = "CapT";    Delay = 260 },
        @{ El = "Est80";      T = "Est80T";  Delay = 320 },
        @{ El = "Est50";      T = "Est50T";  Delay = 380 }
    )

    function Show-AllNow {
        $cardRoot.Opacity = 1
        $cardScale.ScaleX = 1; $cardScale.ScaleY = 1
        foreach ($s in $sections) { $window.FindName($s.El).Opacity = 1 }
        $pill.Opacity = 1
        $aiNote.Opacity = 1; $energyNote.Opacity = 1
        $capLayer.BeginAnimation($heightProp, $null); $capLayer.Height = $script:capTargetH
        $chargeLayer.BeginAnimation($heightProp, $null); $chargeLayer.Height = $script:chargeTargetH
        Set-FinalTexts
        Sync-Pill
    }

    $window.Add_ContentRendered({
        if ($script:entered) { return }
        $script:entered = $true
        try {
            if ($motionOn) {
                $capNum.Text = "0%"
                if ($liveBattery) { $chargePercentText.Text = "0%" }
            }

            $cardRoot.BeginAnimation($opacityProp, (New-Anim 1.0 260))
            Start-Scale $cardScale 1.0 340

            foreach ($s in $sections) {
                $el = $window.FindName($s.El)
                $tr = $window.FindName($s.T)
                $el.BeginAnimation($opacityProp, (New-Anim 1.0 300 $null $null $s.Delay))
                $tr.BeginAnimation($transYProp, (New-Anim 0.0 380 $null $null $s.Delay))
            }
            $pill.BeginAnimation($opacityProp, (New-Anim 1.0 200 $null $null 150))
            $aiNote.BeginAnimation($opacityProp, (New-Anim 0.85 300 $null $null 440))
            $energyNote.BeginAnimation($opacityProp, (New-Anim 0.85 300 $null $null 440))

            Start-TubeFill 100 800 900
        } catch {
            Show-AllNow
        }
    })

    # Hover sulla provetta
    $tubeHit.Add_MouseEnter({
        try {
            $tubeScale.BeginAnimation($scaleXProp, (New-Anim 1.06 280))
            Start-Fade $tubeRing 0.45 200
            Start-Slosh
        } catch { }
    })

    $tubeHit.Add_MouseLeave({
        try {
            $tubeScale.BeginAnimation($scaleXProp, (New-Anim 1.0 220))
            Start-Fade $tubeRing 0.0 200
            Complete-Tube
        } catch { }
    })

    # --- Monitor live della carica ----------------------------------------------
    $script:lastBatteryKey = $null

    # --- Colori del liquido: dipendono da tema (scuro/chiaro), salute e stato di carica ---
    function Get-StatusColor([string]$key) {
        $map = if ($script:isDarkMode) { $statusDark } else { $statusLight }
        return $map[$key]
    }

    # Cambia un colore animabile (fermo di gradiente o brush pieno); riparte dal colore corrente
    function Set-AnimColor($obj, $prop, [string]$hex, [bool]$animate) {
        $target = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
        if ($animate -and $motionOn) {
            $a = New-Object System.Windows.Media.Animation.ColorAnimation
            $a.To = $target
            $a.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(300))
            $a.EasingFunction = New-EaseOut
            $obj.BeginAnimation($prop, $a)
        } else {
            $obj.BeginAnimation($prop, $null)
            $obj.SetValue($prop, $target)
        }
    }

    function Set-LiquidColors([bool]$animate) {
        $stopProp  = [System.Windows.Media.GradientStop]::ColorProperty
        $brushProp = [System.Windows.Media.SolidColorBrush]::ColorProperty

        # Velo (capacita' disponibile): segue la salute
        $capC = Get-StatusColor $healthKey
        Set-AnimColor $capStopA $stopProp (Get-Argb $capC 0x4D) $animate
        Set-AnimColor $capStopB $stopProp (Get-Argb (Get-Shade $capC 0.8) 0x2E) $animate
        Set-AnimColor $capLineBrush $brushProp (Get-Argb $capC 0xBF) $animate

        # Liquido (carica): come la salute, ma giallo/rosso se la batteria e' scarica
        $chargeKey = $healthKey
        if (-not $script:isChargingNow -and $script:chargeShown -lt 10)     { $chargeKey = "Bad" }
        elseif (-not $script:isChargingNow -and $script:chargeShown -lt 20) { $chargeKey = "Ok" }
        $chargeC = Get-StatusColor $chargeKey
        Set-AnimColor $chargeStopA $stopProp $chargeC $animate
        Set-AnimColor $chargeStopB $stopProp (Get-Shade $chargeC 0.8) $animate
    }

    # Il fulmine pulsa piano finche' si carica (solo con le animazioni attive)
    function Set-ChargingIndicator([bool]$charging) {
        if ($charging) {
            $bolt.Visibility = [System.Windows.Visibility]::Visible
            if ($motionOn) {
                $p = New-Object System.Windows.Media.Animation.DoubleAnimation
                $p.From = 1.0; $p.To = 0.4
                $p.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(900))
                $p.AutoReverse = $true
                $p.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
                $sine = New-Object System.Windows.Media.Animation.SineEase
                $sine.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseInOut
                $p.EasingFunction = $sine
                $bolt.BeginAnimation($opacityProp, $p)
            }
        } else {
            $bolt.BeginAnimation($opacityProp, $null)
            $bolt.Opacity = 1.0
            $bolt.Visibility = [System.Windows.Visibility]::Collapsed
        }
    }

    function Update-LiveBatteryCard($state, [bool]$animate) {
        if (-not $state) { return }

        $charge = [int]$state.Charge
        $charging = [bool]$state.IsCharging
        $totalPct = $capPct * $charge / 100.0
        $h = $tubeInnerH * $totalPct / 100.0
        if ($charge -gt 0 -and $h -lt 2) { $h = 2.0 }
        $script:chargeTargetH = $h
        $script:chargeShown = $charge
        $script:isChargingNow = $charging
        if ($animate) { $script:countUp = $false }

        $chargeCaption.Text = Get-ChargeCaption $charging $charge
        Set-ChargingIndicator $charging
        Set-LiquidColors $animate

        if ($animate) {
            $chargeLayer.BeginAnimation($heightProp, (New-Anim $h 450 (New-SettleEase 0.2)))
        } else {
            $chargeLayer.BeginAnimation($heightProp, $null)
            if ($script:entered) { $chargeLayer.Height = $h }
        }

        if ($chargePercentText.Text -ne "$charge%") {
            $chargePercentText.Text = "$charge%"
            if ($animate) {
                # Il numero "scatta" verso l'alto di pochi pixel mentre si schiarisce
                $pillTextT.BeginAnimation($transYProp, (New-Anim 0.0 180 $null 5.0))
                $chargePercentText.BeginAnimation($opacityProp, (New-Anim 1.0 180 $null 0.3))
            }
        }
    }

    if ($liveBattery) {
        Update-LiveBatteryCard $liveBattery $false
        $script:lastBatteryKey = "$($liveBattery.Charge)|$($liveBattery.IsCharging)"
    }

    $liveTimer = New-Object System.Windows.Threading.DispatcherTimer
    $liveTimer.Interval = [TimeSpan]::FromSeconds(2)
    $liveTimerHandler = [System.EventHandler]{
        try {
            $state = Get-LiveBatteryState
            if (-not $state) { return } # conserva l'ultimo valore valido
            $key = "$($state.Charge)|$($state.IsCharging)"
            if ($key -ne $script:lastBatteryKey) {
                Update-LiveBatteryCard $state $true
                $script:lastBatteryKey = $key
            }
        } catch { }
    }
    $liveTimer.Add_Tick($liveTimerHandler)
    $liveTimer.Start()

    # Icona finestra (taskbar/Alt-Tab) quando gira come .ps1; nel .exe e' incorporata.
    try {
        $iconPath = Join-Path $PSScriptRoot "battery-icon.ico"
        if (Test-Path $iconPath) {
            $window.Icon = New-Object System.Windows.Media.Imaging.BitmapImage (New-Object System.Uri($iconPath))
        }
    } catch { }

    # --- Chiusura: con il mouse esce piu' veloce di come entra (160 ms contro 340 ms);
    #     da tastiera (Esc) chiude subito, senza animazione.
    $script:closing = $false
    function Close-Animated {
        if ($script:closing) { return }
        $script:closing = $true
        if (-not $motionOn) { $window.Close(); return }
        $fade = New-Anim 0.0 160
        $fade.Add_Completed({ $window.Close() })
        $cardRoot.BeginAnimation($opacityProp, $fade)
        Start-Scale $cardScale 0.97 160
    }

    # --- Pulsante chiusura: hover = zoom + alone, press = riduzione ---------------
    $closeBtn   = $window.FindName("CloseButton")
    $closeScale = $window.FindName("CloseScale")
    $closeHalo  = $window.FindName("CloseHalo")
    $closeBtn.Add_Click({ Close-Animated })
    $closeBtn.Add_MouseEnter({ Start-Scale $closeScale 1.12 160; Start-Fade $closeHalo 0.14 160 })
    $closeBtn.Add_MouseLeave({ Start-Scale $closeScale 1.0 180; Start-Fade $closeHalo 0.0 180 })
    $closeBtn.Add_PreviewMouseLeftButtonDown({ Start-Scale $closeScale 0.94 90 })
    $closeBtn.Add_PreviewMouseLeftButtonUp({
        $target = if ($closeBtn.IsMouseOver) { 1.12 } else { 1.0 }
        Start-Scale $closeScale $target 140
    })

    # --- Slider tema ------------------------------------------------------------------
    $themeBtn      = $window.FindName("ThemeButton")
    $knobTranslate = $window.FindName("KnobTranslate")
    $switchTrack   = $window.FindName("SwitchTrack")
    $switchScale   = $window.FindName("SwitchScale")
    $switchGlow    = $window.FindName("SwitchGlow")

    # Brush indipendente e animabile per il track.
    $switchTrack.Background = New-Object System.Windows.Media.SolidColorBrush `
        ([System.Windows.Media.Color]::FromRgb(0x16,0x20,0x2A))

    $themeBtn.Add_MouseEnter({ Start-Scale $switchScale 1.06 160; Start-Fade $switchGlow 0.9 160 })
    $themeBtn.Add_MouseLeave({ Start-Scale $switchScale 1.0 180; Start-Fade $switchGlow 0.0 180 })
    $themeBtn.Add_PreviewMouseLeftButtonDown({ Start-Scale $switchScale 0.97 90 })
    $themeBtn.Add_PreviewMouseLeftButtonUp({
        $target = if ($themeBtn.IsMouseOver) { 1.06 } else { 1.0 }
        Start-Scale $switchScale $target 140
    })

    $darkTheme  = @{
        CardBgBrush = "#FF0E141B"; TextPrimaryBrush = "#FFE8EEF3"; TextSecondaryBrush = "#FF7B8A98"
        TubeBgBrush = "#FF101A23"; TubeBorderBrush = "#FF2A3844"; TickBrush = "#FF3A4856"
        ThresholdBrush = "#A6E8EEF3"
    }
    $lightTheme = @{
        CardBgBrush = "#FFF2F5F8"; TextPrimaryBrush = "#FF111418"; TextSecondaryBrush = "#FF5F6B78"
        TubeBgBrush = "#FFE2E8EE"; TubeBorderBrush = "#FFB9C4CF"; TickBrush = "#FFAAB6C2"
        ThresholdBrush = "#A6111418"
    }
    $trackColorDark  = "#FF16202A"
    $trackColorLight = "#FFC9D2DB"
    $knobOffsetLight = 24.0

    function Start-ColorAnim($brush, [string]$hex, [double]$seconds) {
        $target = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
        $anim = New-Object System.Windows.Media.Animation.ColorAnimation
        $anim.To = $target
        $ms = if ($motionOn) { $seconds * 1000.0 } else { 1.0 }
        $anim.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds($ms))
        $anim.EasingFunction = New-EaseOut
        $brush.BeginAnimation([System.Windows.Media.SolidColorBrush]::ColorProperty, $anim)
    }

    $themeBtn.Add_Click({
        $targetTheme = if ($script:isDarkMode) { $lightTheme } else { $darkTheme }
        foreach ($key in $targetTheme.Keys) {
            Start-ColorAnim $window.Resources[$key] $targetTheme[$key] 0.3
        }

        $targetTrackHex = if ($script:isDarkMode) { $trackColorLight } else { $trackColorDark }
        Start-ColorAnim $switchTrack.Background $targetTrackHex 0.3

        $targetKnobX = if ($script:isDarkMode) { $knobOffsetLight } else { 0.0 }
        $knobTranslate.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, (New-Anim $targetKnobX 320 (New-SettleEase 0.3)))

        $script:isDarkMode = -not $script:isDarkMode
        Set-LiquidColors $true   # il liquido cambia colore insieme al tema (300 ms)
    })

    # Trascinamento finestra ed Esc per chiudere (subito, senza animazione)
    $dragHandle = $window.FindName("DragHandle")
    $dragHandle.Add_MouseLeftButtonDown({ $window.DragMove() })
    $window.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $window.Close() }
    })

    $window.Add_Closed({
        $liveTimer.Stop()
        $liveTimer.Remove_Tick($liveTimerHandler)
        if ($script:report -and (Test-Path -LiteralPath $script:report)) {
            Remove-Item -LiteralPath $script:report -Force -ErrorAction SilentlyContinue
        }
    })

    $window.ShowDialog() | Out-Null
}
catch {
    Show-ErrorBox "Si e' verificato un errore imprevisto:`n`n$($_.Exception.Message)`n`nRiga: $($_.InvocationInfo.ScriptLineNumber)"
}
finally {
    # Pulizia difensiva del solo report temporaneo creato dall'applicazione.
    if ($script:report -and (Test-Path -LiteralPath $script:report)) {
        Remove-Item -LiteralPath $script:report -Force -ErrorAction SilentlyContinue
    }
}
