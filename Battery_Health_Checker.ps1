# Battery Health - ASUS Zenbook / Windows 11
# Stile card moderno, finestra senza barra titolo.
# Gauge: arco statico (Path), gia' verificato accurato. Animazione limitata
# all'apertura della card (fade + scala), che non ha dato problemi finora.
#
# NOTA: script scritto e revisionato ma non eseguito su un ambiente Windows
# reale (qui ho solo Linux).

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

function Show-ErrorBox([string]$msg) {
    [System.Windows.MessageBox]::Show($msg, "Battery Health - Errore",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error) | Out-Null
}

try {
    $ErrorActionPreference = "Stop"
    $inv = [System.Globalization.CultureInfo]::InvariantCulture

    # --- Dati live: API Windows, senza file o battery report -------------------
    # SystemInformation.PowerStatus e' disponibile su Windows 10/11 con PowerShell 5.1.
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

    function ConvertTo-Number([string]$s) {
        if ([string]::IsNullOrWhiteSpace($s)) { return 0 }
        return [double](($s -replace '[^0-9]', ''))
    }

    $liveBattery = Get-LiveBatteryState
    $diagnostics = Get-BatteryDiagnostics
    $hasDiagnostics = $diagnostics -and $diagnostics.Design -gt 0 -and $diagnostics.Full -gt 0

    if ($hasDiagnostics) {
        $design = $diagnostics.Design
        $full   = $diagnostics.Full
        $cycles = $diagnostics.Cycles
        $health = [math]::Round(($full / $design) * 100, 1)
        $wear   = [math]::Round(100 - $health, 1)

        if     ($health -ge 80) { $color = "#FF34C759"; $status = "Ottima" }
        elseif ($health -ge 60) { $color = "#FFFFD60A"; $status = "Buona, da monitorare" }
        elseif ($health -ge 40) { $color = "#FFFF9F0A"; $status = "Usura significativa" }
        else                    { $color = "#FFFF453A"; $status = "Valuta la sostituzione" }
    } else {
        # Un errore diagnostico non deve impedire l'uso della lettura live.
        $design = 0; $full = 0; $cycles = 'N/D'; $health = 0; $wear = 0
        $color = "#FF8E8E93"; $status = "Dati diagnostici non disponibili"
    }

    # --- Raccolta info modello PC ------------------------------------------------
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

    # --- Stato iniziale della card live -----------------------------------------
    $currentCharge = if ($liveBattery) { $liveBattery.Charge } else { 'N/D' }
    $isCharging = $liveBattery -and $liveBattery.IsCharging

    # Calcola larghezza interna dell'icona batteria (max 33px)
    $chargeWidth = if ($liveBattery) { [math]::Round(33 * ($currentCharge / 100)) } else { 0 }
    if ($liveBattery -and $currentCharge -gt 0 -and $chargeWidth -lt 2) { $chargeWidth = 2 }

    # Colore e stato basati su carica e alimentazione
    if (-not $liveBattery) {
        $chargeColor = "#FF8E8E93"
        $chargeStatusText = "Stato non disponibile"
        $lightningVisibility = "Collapsed"
    } elseif ($isCharging) {
        $chargeColor = "#FF34C759" # Verde iOS
        $chargeStatusText = "In carica"
        $lightningVisibility = "Visible"
    } else {
        $lightningVisibility = "Collapsed"
        if ($currentCharge -ge 20) {
            $chargeColor = "{DynamicResource BatteryDischargingBrush}" # Adattivo: bianco in dark, nero in light
            $chargeStatusText = "Su batteria"
        } elseif ($currentCharge -ge 10) {
            $chargeColor = "#FFFFD60A" # Giallo iOS
            $chargeStatusText = "Batteria scarica"
        } else {
            $chargeColor = "#FFFF453A" # Rosso iOS
            $chargeStatusText = "Batteria quasi scarica"
        }
    }

    # --- Proiezione fino alla soglia indicativa dell'80% ------------------------
    # Windows non espone la frequenza futura di ricarica: la conversione in tempo
    # usa esplicitamente l'ipotesi di un ciclo completo ogni due giorni.
    $numericCycles = 0
    if ($cycles -match '^\d+$') { $numericCycles = [double]$cycles }
    $wearPerCycle = if ($numericCycles -gt 0) { $wear / $numericCycles } else { 0 }

    if (-not $hasDiagnostics) {
        $estimateCyclesText = "Stima non disponibile"
        $estimateTimeText = "Dati diagnostici non disponibili"
        $replacementText = "Impossibile valutare la sostituzione senza i dati di salute."
    } elseif ($health -le 80) {
        $estimateCyclesText = "Soglia indicativa dell'80% gia' raggiunta"
        $estimateTimeText = "La capacita' residua e' gia' sotto la soglia indicativa."
        $replacementText = if ($health -le 60) {
            "Usura significativa: e' consigliabile valutare la sostituzione."
        } else {
            "Potrebbe essere utile valutare una sostituzione."
        }
    } elseif ($numericCycles -le 0) {
        $estimateCyclesText = "Stima della durata non disponibile"
        $estimateTimeText = "Windows non ha fornito il numero di cicli."
        $replacementText = "Non attualmente necessaria; la soglia indicativa e' l'80%."
    } elseif ($wearPerCycle -le 0) {
        $estimateCyclesText = "Stima della durata non disponibile"
        $estimateTimeText = "L'usura per ciclo rilevata non consente una proiezione affidabile."
        $replacementText = "Non attualmente necessaria; la soglia indicativa e' l'80%."
    } else {
        $remainingCycles = [math]::Max(1, [math]::Round(($health - 80) / $wearPerCycle))
        $remainingDays = [math]::Max(1, [math]::Round($remainingCycles * 2))
        $estimateCyclesText = "~$remainingCycles cicli residui"
        if ($remainingDays -ge 730) {
            $estimateTimeText = "~$([math]::Round($remainingDays / 365, 1)) anni prima dell'80%"
        } elseif ($remainingDays -ge 60) {
            $estimateTimeText = "~$([math]::Round($remainingDays / 30)) mesi prima dell'80%"
        } else {
            $estimateTimeText = "~$remainingDays giorni prima dell'80%"
        }
        $replacementText = "Non attualmente necessaria; la soglia indicativa e' l'80%."
    }

    # --- Geometria dell'arco (tecnica gia' confermata accurata) -----------------
    $cx = 130.0; $cy = 130.0; $r = 100.0
    $angleDeg = 360.0 * ($health / 100.0)
    if ($angleDeg -ge 359.9) { $angleDeg = 359.9 }

    $startDeg = -90.0
    $endDeg   = $startDeg + $angleDeg
    $toRad    = { param($d) $d * [math]::PI / 180.0 }

    $startX = $cx + $r * [math]::Cos((& $toRad $startDeg))
    $startY = $cy + $r * [math]::Sin((& $toRad $startDeg))
    $endX   = $cx + $r * [math]::Cos((& $toRad $endDeg))
    $endY   = $cy + $r * [math]::Sin((& $toRad $endDeg))
    $largeArc = if ($angleDeg -gt 180) { 1 } else { 0 }

    $arcData = "M {0},{1} A {2},{2} 0 {3},1 {4},{5}" -f `
        $startX.ToString("0.##", $inv), $startY.ToString("0.##", $inv), `
        $r.ToString("0.##", $inv), $largeArc, `
        $endX.ToString("0.##", $inv), $endY.ToString("0.##", $inv)

    # --- XAML della finestra -----------------------------------------------------
    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Battery Health"
        Width="460" Height="950"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="Transparent"
        ResizeMode="NoResize"
        WindowStartupLocation="CenterScreen">
  <Window.Resources>
    <SolidColorBrush x:Key="CardBgBrush" Color="#FF1C1C1E"/>
    <SolidColorBrush x:Key="InnerCardBgBrush" Color="#FF2C2C2E"/>
    <SolidColorBrush x:Key="TextPrimaryBrush" Color="#FFFFFFFF"/>
    <SolidColorBrush x:Key="TextSecondaryBrush" Color="#FF8E8E93"/>
    <SolidColorBrush x:Key="SeparatorBrush" Color="#FF2C2C2E"/>
    <SolidColorBrush x:Key="BatteryDischargingBrush" Color="#FFFFFFFF"/>
  </Window.Resources>

  <Window.Triggers>
    <EventTrigger RoutedEvent="Window.Loaded">
      <BeginStoryboard>
        <Storyboard>
          <DoubleAnimation Storyboard.TargetName="Card" Storyboard.TargetProperty="Opacity"
                            From="0" To="1" Duration="0:0:0.4"/>
          <DoubleAnimation Storyboard.TargetName="CardScale" Storyboard.TargetProperty="ScaleX"
                            From="0.94" To="1" Duration="0:0:0.5">
            <DoubleAnimation.EasingFunction><BackEase EasingMode="EaseOut" Amplitude="0.25"/></DoubleAnimation.EasingFunction>
          </DoubleAnimation>
          <DoubleAnimation Storyboard.TargetName="CardScale" Storyboard.TargetProperty="ScaleY"
                            From="0.94" To="1" Duration="0:0:0.5">
            <DoubleAnimation.EasingFunction><BackEase EasingMode="EaseOut" Amplitude="0.25"/></DoubleAnimation.EasingFunction>
          </DoubleAnimation>
        </Storyboard>
      </BeginStoryboard>
    </EventTrigger>
  </Window.Triggers>

  <Border x:Name="Card" Margin="24" CornerRadius="22" Background="{DynamicResource CardBgBrush}" Opacity="0">
    <Border.RenderTransform>
      <ScaleTransform x:Name="CardScale" ScaleX="0.94" ScaleY="0.94" CenterX="206" CenterY="336"/>
    </Border.RenderTransform>
    <Border.Effect>
      <DropShadowEffect Color="Black" BlurRadius="40" ShadowDepth="10" Opacity="0.45"/>
    </Border.Effect>

      <Grid Margin="30">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Grid x:Name="DragHandle" Grid.Row="0" Height="32" Background="Transparent" Margin="0,0,0,8">
          <!-- Bottone Tema Dark/Light: slider animato stile iOS -->
          <Button x:Name="ThemeButton" Width="52" Height="28"
                  HorizontalAlignment="Left" VerticalAlignment="Center"
                  FocusVisualStyle="{x:Null}"
                  Cursor="Hand">
            <Button.Template>
              <ControlTemplate TargetType="Button">
                <Grid Background="Transparent">
                  <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Grid>
              </ControlTemplate>
            </Button.Template>
            <Grid x:Name="SwitchVisual" Width="52" Height="28" RenderTransformOrigin="0.5,0.5">
              <Grid.RenderTransform>
                <ScaleTransform ScaleX="1" ScaleY="1"/>
              </Grid.RenderTransform>
              <Grid.Style>
                <Style TargetType="Grid">
                  <Style.Triggers>
                    <DataTrigger Binding="{Binding Path=IsMouseOver, RelativeSource={RelativeSource AncestorType=Button}}" Value="True">
                      <Setter Property="RenderTransform">
                        <Setter.Value><ScaleTransform ScaleX="1.08" ScaleY="1.08"/></Setter.Value>
                      </Setter>
                    </DataTrigger>
                  </Style.Triggers>
                </Style>
              </Grid.Style>

              <Border x:Name="SwitchTrack" CornerRadius="14" BorderThickness="1.2" BorderBrush="#FF48484A">
                <Border.Style>
                  <Style TargetType="Border">
                    <Style.Triggers>
                      <DataTrigger Binding="{Binding Path=IsMouseOver, RelativeSource={RelativeSource AncestorType=Button}}" Value="True">
                        <Setter Property="BorderBrush" Value="White"/>
                      </DataTrigger>
                    </Style.Triggers>
                  </Style>
                </Border.Style>
              </Border>

              <Ellipse x:Name="SwitchKnob" Width="22" Height="22" Fill="White"
                       HorizontalAlignment="Left" VerticalAlignment="Center" Margin="3,0,0,0">
                <Ellipse.Effect>
                  <DropShadowEffect Color="Black" BlurRadius="6" ShadowDepth="1" Opacity="0.4"/>
                </Ellipse.Effect>
                <Ellipse.RenderTransform>
                  <TranslateTransform x:Name="KnobTranslate" X="0"/>
                </Ellipse.RenderTransform>
              </Ellipse>
            </Grid>
          </Button>

          <!-- Bottone Chiusura -->
          <Button x:Name="CloseButton" Width="28" Height="28"
                  HorizontalAlignment="Right" VerticalAlignment="Center"
                  FocusVisualStyle="{x:Null}"
                  Cursor="Hand">
            <Button.Template>
              <ControlTemplate TargetType="Button">
                <Grid Background="Transparent">
                  <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Grid>
              </ControlTemplate>
            </Button.Template>
            <TextBlock x:Name="BtnText" Text="&#x2715;" FontSize="12" Foreground="{DynamicResource TextSecondaryBrush}" 
                       FontFamily="Segoe UI Variable Text, Segoe UI" RenderTransformOrigin="0.5,0.5"
                       HorizontalAlignment="Center" VerticalAlignment="Center">
              <TextBlock.Style>
                <Style TargetType="TextBlock">
                  <Style.Triggers>
                    <DataTrigger Binding="{Binding Path=IsMouseOver, RelativeSource={RelativeSource AncestorType=Button}}" Value="True">
                      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
                      <Setter Property="RenderTransform">
                        <Setter.Value>
                          <ScaleTransform ScaleX="1.25" ScaleY="1.25"/>
                        </Setter.Value>
                      </Setter>
                    </DataTrigger>
                  </Style.Triggers>
                </Style>
              </TextBlock.Style>
            </TextBlock>
          </Button>
        </Grid>

        <StackPanel Grid.Row="1" HorizontalAlignment="Center" Margin="0,0,0,14">
          <TextBlock Text="Salute Batteria" FontSize="22" FontWeight="Bold" Foreground="{DynamicResource TextPrimaryBrush}"
                     HorizontalAlignment="Center" FontFamily="Segoe UI Variable Display, Segoe UI"/>
          <TextBlock Text="$pcModel" FontSize="12" Foreground="{DynamicResource TextSecondaryBrush}"
                     HorizontalAlignment="Center" FontFamily="Segoe UI Variable Text, Segoe UI"/>
        </StackPanel>

        <!-- Card Stato Carica Attuale -->
        <Border Grid.Row="2" Background="{DynamicResource InnerCardBgBrush}" CornerRadius="14" Padding="16,12" Margin="0,0,0,16">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <!-- Icona Batteria -->
            <Grid Grid.Column="0" Width="44" Height="22" Margin="0,0,12,0" VerticalAlignment="Center">
              <Border CornerRadius="5" BorderBrush="{DynamicResource TextSecondaryBrush}" BorderThickness="2" Background="Transparent" Margin="0,0,4,0">
              <Border x:Name="BatteryFill" CornerRadius="2.5" Background="$chargeColor" HorizontalAlignment="Left" Width="$chargeWidth" Margin="1.5"/>
              </Border>
              <Border Width="2.5" Height="8" CornerRadius="0.8" Background="{DynamicResource TextSecondaryBrush}" HorizontalAlignment="Right" VerticalAlignment="Center"/>
              <TextBlock x:Name="ChargingIcon" Text="⚡" Foreground="White" FontSize="11" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="$lightningVisibility" Margin="0,0,4,0"/>
            </Grid>
            <!-- Stato e info carica -->
            <StackPanel Grid.Column="1" VerticalAlignment="Center">
              <TextBlock Text="Livello di Carica" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimaryBrush}" FontFamily="Segoe UI Variable Text, Segoe UI"/>
              <TextBlock x:Name="ChargeStatusText" Text="$chargeStatusText" FontSize="11" Foreground="{DynamicResource TextSecondaryBrush}" FontFamily="Segoe UI Variable Text, Segoe UI"/>
            </StackPanel>
            <!-- Percentuale -->
            <TextBlock x:Name="ChargePercentText" Grid.Column="2" Text="$currentCharge%" FontSize="22" FontWeight="Bold" Foreground="{DynamicResource TextPrimaryBrush}" VerticalAlignment="Center" FontFamily="Segoe UI Variable Display, Segoe UI"/>
          </Grid>
        </Border>

        <!-- Area trasparente piu' ampia: l'hover resta stabile anche ai bordi del gauge. -->
        <Grid x:Name="GaugePanel" Grid.Row="3" Width="284" Height="284" Background="Transparent" HorizontalAlignment="Center" RenderTransformOrigin="0.5,0.5" Cursor="Hand">
          <Grid.RenderTransform><ScaleTransform x:Name="GaugeScale" ScaleX="1" ScaleY="1"/></Grid.RenderTransform>
          <Canvas Width="260" Height="260" HorizontalAlignment="Center" VerticalAlignment="Center">
            <Ellipse Canvas.Left="30" Canvas.Top="30" Width="200" Height="200"
                     Stroke="{DynamicResource SeparatorBrush}" StrokeThickness="22"/>
            <Path x:Name="ArcPath" Data="$arcData" Stroke="$color" StrokeThickness="22" StrokeDashArray="100,100" StrokeDashOffset="0"
                  StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
          </Canvas>
          <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
            <TextBlock Text="$health%" FontSize="42" FontWeight="Bold" Foreground="{DynamicResource TextPrimaryBrush}"
                       HorizontalAlignment="Center" FontFamily="Segoe UI Variable Display, Segoe UI"/>
            <TextBlock Text="Capacità Massima" FontSize="11" Foreground="{DynamicResource TextSecondaryBrush}"
                       HorizontalAlignment="Center" FontFamily="Segoe UI Variable Text, Segoe UI"/>
          </StackPanel>
        </Grid>

        <!-- Pannello informativo mostrato con il passaggio sul gauge. -->
        <Border x:Name="EstimatePanel" Grid.Row="4" Background="{DynamicResource InnerCardBgBrush}" CornerRadius="14" Padding="16,13" Margin="0,14,0,12" Visibility="Collapsed" Opacity="0" RenderTransformOrigin="0.5,0.5">
          <Border.RenderTransform><TranslateTransform x:Name="EstimatePanelTranslate" Y="5"/></Border.RenderTransform>
          <StackPanel>
            <TextBlock Text="STIMA DELLA BATTERIA" FontSize="11" FontWeight="SemiBold" Foreground="{DynamicResource TextSecondaryBrush}" HorizontalAlignment="Center"/>
            <TextBlock Text="$estimateCyclesText" FontSize="15" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimaryBrush}" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" Margin="0,8,0,1"/>
            <TextBlock Text="$estimateTimeText" FontSize="11" Foreground="{DynamicResource TextSecondaryBrush}" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" Margin="0,0,0,10"/>
            <Rectangle Height="1" Fill="{DynamicResource SeparatorBrush}"/>
            <TextBlock Text="POSSIBILE SOSTITUZIONE" FontSize="10" FontWeight="SemiBold" Foreground="{DynamicResource TextSecondaryBrush}" Margin="0,10,0,2"/>
            <TextBlock Text="$replacementText" FontSize="12" Foreground="{DynamicResource TextPrimaryBrush}"/>
            <TextBlock Text="Stima indicativa: proiezione basata sull'usura rilevata; 1 ciclo completo ogni 2 giorni. La durata reale varia con utilizzo, temperatura e ricarica." FontSize="9" Foreground="{DynamicResource TextSecondaryBrush}" TextWrapping="Wrap" Margin="0,8,0,0"/>
          </StackPanel>
        </Border>

        <StackPanel Grid.Row="5" Margin="0,0,0,0">
        <TextBlock Text="$status" FontSize="15" FontWeight="SemiBold" Foreground="$color"
                   HorizontalAlignment="Center" Margin="0,0,0,18" FontFamily="Segoe UI Variable Text, Segoe UI"/>

        <Grid Margin="0,7">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <TextBlock Grid.Column="0" Text="Usura" Foreground="{DynamicResource TextSecondaryBrush}" FontFamily="Segoe UI Variable Text, Segoe UI"/>
          <TextBlock Grid.Column="1" Text="$wear%" Foreground="{DynamicResource TextPrimaryBrush}" HorizontalAlignment="Right" FontFamily="Segoe UI Variable Text, Segoe UI"/>
        </Grid>
        <Rectangle Height="1" Fill="{DynamicResource SeparatorBrush}" Margin="0,4"/>
        <Grid Margin="0,7">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <TextBlock Grid.Column="0" Text="Capacità attuale" Foreground="{DynamicResource TextSecondaryBrush}" FontFamily="Segoe UI Variable Text, Segoe UI"/>
          <TextBlock Grid.Column="1" Text="$([math]::Round($full,0).ToString('N0')) mWh" Foreground="{DynamicResource TextPrimaryBrush}" HorizontalAlignment="Right" FontFamily="Segoe UI Variable Text, Segoe UI"/>
        </Grid>
        <Rectangle Height="1" Fill="{DynamicResource SeparatorBrush}" Margin="0,4"/>
        <Grid Margin="0,7">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <TextBlock Grid.Column="0" Text="Capacità originale" Foreground="{DynamicResource TextSecondaryBrush}" FontFamily="Segoe UI Variable Text, Segoe UI"/>
          <TextBlock Grid.Column="1" Text="$([math]::Round($design,0).ToString('N0')) mWh" Foreground="{DynamicResource TextPrimaryBrush}" HorizontalAlignment="Right" FontFamily="Segoe UI Variable Text, Segoe UI"/>
        </Grid>
        <Rectangle Height="1" Fill="{DynamicResource SeparatorBrush}" Margin="0,4"/>
        <Grid Margin="0,7">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <TextBlock Grid.Column="0" Text="Cicli di ricarica" Foreground="{DynamicResource TextSecondaryBrush}" FontFamily="Segoe UI Variable Text, Segoe UI"/>
          <TextBlock Grid.Column="1" Text="$cycles" Foreground="{DynamicResource TextPrimaryBrush}" HorizontalAlignment="Right" FontFamily="Segoe UI Variable Text, Segoe UI"/>
        </Grid>
      </StackPanel>
    </Grid>
  </Border>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    # --- Animazione gauge: reveal nativo WPF, senza Geometry.Parse o timer -----
    # Il Path conserva la geometria finale verificata; StrokeDashOffset rivela lo
    # stroke sul render thread. Ogni BeginAnimation sostituisce quella precedente.
    $gaugePanel = $window.FindName("GaugePanel")
    $gaugeScale = $window.FindName("GaugeScale")
    $arcPathEl = $window.FindName("ArcPath")
    $estimatePanel = $window.FindName("EstimatePanel")
    $estimatePanelTranslate = $window.FindName("EstimatePanelTranslate")
    # 100 dash units x 22 px di StrokeThickness = 2200 px: maggiore della
    # circonferenza massima (~628 px). Offset 100 nasconde l'arco, Offset 0 lo mostra.
    $gaugeDashOffset = 100.0

    function New-GaugeEase {
        $ease = New-Object System.Windows.Media.Animation.QuarticEase
        $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
        return $ease
    }

    function New-GaugeRevealEase {
        # Accelerazione e decelerazione morbide per il solo riempimento dell'arco.
        $ease = New-Object System.Windows.Media.Animation.CubicEase
        $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseInOut
        return $ease
    }

    function Start-GaugeScale([double]$target, [int]$durationMs) {
        foreach ($property in @([System.Windows.Media.ScaleTransform]::ScaleXProperty, [System.Windows.Media.ScaleTransform]::ScaleYProperty)) {
            $scaleAnimation = New-Object System.Windows.Media.Animation.DoubleAnimation
            # Snapshot esplicito: anche lo zoom riparte sempre dalla scala visibile.
            $scaleAnimation.From = [double]$gaugeScale.GetValue($property)
            $scaleAnimation.To = $target
            $scaleAnimation.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds($durationMs))
            $scaleAnimation.EasingFunction = New-GaugeEase
            $gaugeScale.BeginAnimation($property, $scaleAnimation)
        }
    }

    $gaugePanel.Add_MouseEnter({
        # Reset e avvio avvengono nello stesso turno UI: WPF renderizza direttamente
        # il primo frame del reveal, senza ricostruire Data o mostrare un frame intermedio.
        $arcPathEl.BeginAnimation([System.Windows.Shapes.Shape]::StrokeDashOffsetProperty, $null)
        $arcPathEl.StrokeDashOffset = $gaugeDashOffset
        $arcAnimation = New-Object System.Windows.Media.Animation.DoubleAnimation
        $arcAnimation.From = $gaugeDashOffset
        $arcAnimation.To = 0.0
        $arcAnimation.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(1350))
        $arcAnimation.EasingFunction = New-GaugeRevealEase
        $arcPathEl.BeginAnimation([System.Windows.Shapes.Shape]::StrokeDashOffsetProperty, $arcAnimation)
        Start-GaugeScale 1.05 320

        $estimatePanel.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
        $estimatePanelTranslate.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
        $estimatePanel.Visibility = [System.Windows.Visibility]::Visible
        $estimatePanel.Opacity = 0
        $estimatePanelTranslate.Y = 5

        $panelFadeIn = New-Object System.Windows.Media.Animation.DoubleAnimation
        $panelFadeIn.To = 1.0
        $panelFadeIn.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(210))
        $estimatePanel.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $panelFadeIn)
        $panelSlideIn = New-Object System.Windows.Media.Animation.DoubleAnimation
        $panelSlideIn.To = 0.0
        $panelSlideIn.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(210))
        $panelSlideIn.EasingFunction = New-GaugeEase
        $estimatePanelTranslate.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $panelSlideIn)
    })

    $gaugePanel.Add_MouseLeave({
        # Ritorno breve e continuo al solo stato statico: arco completo e scala 1.00.
        $arcFinish = New-Object System.Windows.Media.Animation.DoubleAnimation
        $arcFinish.From = [double]$arcPathEl.GetValue([System.Windows.Shapes.Shape]::StrokeDashOffsetProperty)
        $arcFinish.To = 0.0
        $arcFinish.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(220))
        $arcFinish.EasingFunction = New-GaugeRevealEase
        $arcPathEl.BeginAnimation([System.Windows.Shapes.Shape]::StrokeDashOffsetProperty, $arcFinish)
        Start-GaugeScale 1.0 220

        if ($estimatePanel.Visibility -eq [System.Windows.Visibility]::Visible) {
            $panelFadeOut = New-Object System.Windows.Media.Animation.DoubleAnimation
            $panelFadeOut.To = 0.0
            $panelFadeOut.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(160))
            $panelFadeOut.Add_Completed({ $estimatePanel.Visibility = [System.Windows.Visibility]::Collapsed })
            $estimatePanel.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $panelFadeOut)
        }
    })

    # --- Monitor live della carica ----------------------------------------------
    # Un solo DispatcherTimer aggiorna esclusivamente la card quando cambia lo
    # stato Windows; il gauge e i dati diagnostici non vengono mai ricalcolati.
    $chargePercentText = $window.FindName("ChargePercentText")
    $chargeStatusLabel = $window.FindName("ChargeStatusText")
    $batteryFill       = $window.FindName("BatteryFill")
    $chargingIcon      = $window.FindName("ChargingIcon")
    $script:lastBatteryKey = $null

    function Update-LiveBatteryCard($state, [bool]$animate) {
        if (-not $state) { return }

        $charge = [int]$state.Charge
        $width = [math]::Round(33 * ($charge / 100))
        if ($charge -gt 0 -and $width -lt 2) { $width = 2 }

        if ($state.IsCharging) {
            $cardColor = "#FF34C759"; $cardStatus = "In carica"
            $chargingIcon.Visibility = [System.Windows.Visibility]::Visible
        } else {
            $chargingIcon.Visibility = [System.Windows.Visibility]::Collapsed
            if ($charge -ge 20) {
                $cardColor = $null; $cardStatus = "Su batteria"
            } elseif ($charge -ge 10) {
                $cardColor = "#FFFFD60A"; $cardStatus = "Batteria scarica"
            } else {
                $cardColor = "#FFFF453A"; $cardStatus = "Batteria quasi scarica"
            }
        }

        $batteryFill.Width = $width
        $batteryFill.Background = if ($cardColor) {
            [System.Windows.Media.BrushConverter]::new().ConvertFromString($cardColor)
        } else {
            $window.Resources["BatteryDischargingBrush"]
        }
        $chargeStatusLabel.Text = $cardStatus

        if ($chargePercentText.Text -ne "$charge%") {
            if ($animate) { $chargePercentText.Opacity = 0 }
            $chargePercentText.Text = "$charge%"
            if ($animate) {
                $fade = New-Object System.Windows.Media.Animation.DoubleAnimation
                $fade.From = 0; $fade.To = 1
                $fade.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(180))
                $chargePercentText.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
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
        $state = Get-LiveBatteryState
        if (-not $state) { return } # conserva l'ultimo valore valido in caso di errore temporaneo
        $key = "$($state.Charge)|$($state.IsCharging)"
        if ($key -ne $script:lastBatteryKey) {
            Update-LiveBatteryCard $state $true
            $script:lastBatteryKey = $key
        }
    }
    $liveTimer.Add_Tick($liveTimerHandler)
    $liveTimer.Start()

    # Icona finestra (taskbar/Alt-Tab). Utile quando lo script gira come .ps1
    # non compilato - la versione .exe compilata con ps2exe ha gia' l'icona
    # incorporata nel file stesso. Avvolto in try/catch: se il file manca
    # (es. .ps1 spostato senza l'icona accanto) l'app funziona comunque.
    try {
        $iconPath = Join-Path $PSScriptRoot "battery-icon.ico"
        if (Test-Path $iconPath) {
            $window.Icon = New-Object System.Windows.Media.Imaging.BitmapImage (New-Object System.Uri($iconPath))
        }
    } catch { }

    # Associazione eventi pulsante chiusura
    $closeBtn = $window.FindName("CloseButton")
    $closeBtn.Add_Click({ $window.Close() })

    # Associazione eventi pulsante Tema (slider animato Dark/Light)
    $themeBtn = $window.FindName("ThemeButton")
    $knobTranslate = $window.FindName("KnobTranslate")
    $switchTrack    = $window.FindName("SwitchTrack")

    # Assicura che il background del track sia un SolidColorBrush indipendente e animabile
    $switchTrack.Background = New-Object System.Windows.Media.SolidColorBrush `
        ([System.Windows.Media.Color]::FromRgb(0x39,0x39,0x3D))

    $script:isDarkMode = $true

    $darkTheme  = @{
        CardBgBrush = "#FF1C1C1E"; InnerCardBgBrush = "#FF2C2C2E"; TextPrimaryBrush = "#FFFFFFFF"
        TextSecondaryBrush = "#FF8E8E93"; SeparatorBrush = "#FF2C2C2E"; BatteryDischargingBrush = "#FFFFFFFF"
    }
    $lightTheme = @{
        CardBgBrush = "#FFF2F2F7"; InnerCardBgBrush = "#FFFFFFFF"; TextPrimaryBrush = "#FF000000"
        TextSecondaryBrush = "#FF6C6C70"; SeparatorBrush = "#FFE5E5EA"; BatteryDischargingBrush = "#FF000000"
    }
    $trackColorDark  = "#FF39393D"
    $trackColorLight = "#FFD1D1D6"
    $knobOffsetLight = 24.0  # spostamento a destra in modalita' chiara

    function Start-ColorAnim($brush, [string]$hex, [double]$seconds) {
        $target = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
        $anim = New-Object System.Windows.Media.Animation.ColorAnimation
        $anim.To = $target
        $anim.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromSeconds($seconds))
        $anim.EasingFunction = New-Object System.Windows.Media.Animation.CubicEase
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
        $knobAnim = New-Object System.Windows.Media.Animation.DoubleAnimation
        $knobAnim.To = $targetKnobX
        $knobAnim.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromSeconds(0.3))
        $knobEase = New-Object System.Windows.Media.Animation.BackEase
        $knobEase.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
        $knobEase.Amplitude = 0.3
        $knobAnim.EasingFunction = $knobEase
        $knobTranslate.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $knobAnim)

        $script:isDarkMode = -not $script:isDarkMode
    })

    # Permette il trascinamento della finestra
    $dragHandle = $window.FindName("DragHandle")
    $dragHandle.Add_MouseLeftButtonDown({ $window.DragMove() })

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
