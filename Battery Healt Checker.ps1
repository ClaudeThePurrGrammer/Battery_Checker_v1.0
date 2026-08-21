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

    # --- Raccolta dati batteria -------------------------------------------------
    function Get-BatteryReportPath {
        $temp = Join-Path $env:TEMP "battery-report.html"
        powercfg /batteryreport /output "$temp" | Out-Null
        if (Test-Path $temp) { return $temp }
        return $null
    }

    $report = Get-BatteryReportPath
    if (-not $report) {
        Show-ErrorBox "Impossibile creare il report della batteria.`nProva ad avviare lo script come amministratore."
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
    $cycles = if ($cycleMatch.Success) { $cycleMatch.Groups[1].Value } else { "N/D" }

    if ($design -le 0 -or $full -le 0) {
        Show-ErrorBox "Non sono riuscito a leggere i dati della batteria dal report.`n`nFile: $report"
        return
    }

    $health = [math]::Round(($full / $design) * 100, 1)
    $wear   = [math]::Round(100 - $health, 1)

    if     ($health -ge 80) { $color = "#FF34C759"; $status = "Ottima" }
    elseif ($health -ge 60) { $color = "#FFFFD60A"; $status = "Buona, da monitorare" }
    elseif ($health -ge 40) { $color = "#FFFF9F0A"; $status = "Usura significativa" }
    else                    { $color = "#FFFF453A"; $status = "Valuta la sostituzione" }

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

    # --- Raccolta dati carica attuale -------------------------------------------
    $powerStatus = [System.Windows.Forms.SystemInformation]::PowerStatus
    $currentCharge = [math]::Round($powerStatus.BatteryLifePercent * 100)
    if ($currentCharge -gt 100) { $currentCharge = 100 }
    if ($currentCharge -lt 0) { $currentCharge = 0 }

    $isCharging = $powerStatus.PowerLineStatus -eq "Online"

    # Calcola larghezza interna dell'icona batteria (max 33px)
    $chargeWidth = [math]::Round(33 * ($currentCharge / 100))
    if ($currentCharge -gt 0 -and $chargeWidth -lt 2) { $chargeWidth = 2 }

    # Colore e stato basati su carica e alimentazione
    if ($isCharging) {
        $chargeColor = "#FF34C759" # Verde iOS
        $chargeStatusText = "In carica"
        $lightningVisibility = "Visible"
    } else {
        $lightningVisibility = "Collapsed"
        if ($currentCharge -ge 20) {
            $chargeColor = "#FFFFFFFF" # Bianco iOS
            $chargeStatusText = "Su batteria"
        } elseif ($currentCharge -ge 10) {
            $chargeColor = "#FFFFD60A" # Giallo iOS
            $chargeStatusText = "Batteria scarica"
        } else {
            $chargeColor = "#FFFF453A" # Rosso iOS
            $chargeStatusText = "Batteria quasi scarica"
        }
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
        Width="460" Height="720"
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
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <Grid x:Name="DragHandle" Grid.Row="0" Height="20" Background="Transparent" Margin="0,0,0,4">
          <!-- Bottone Tema Dark/Light -->
          <Button x:Name="ThemeButton" Width="28" Height="28"
                  HorizontalAlignment="Left" VerticalAlignment="Top"
                  Cursor="Hand">
            <Button.Template>
              <ControlTemplate TargetType="Button">
                <Grid Background="Transparent">
                  <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Grid>
              </ControlTemplate>
            </Button.Template>
            <!-- L'icona iniziale è la Luna (&#xE708;) perché partiamo in Dark Mode -->
            <TextBlock x:Name="ThemeIcon" Text="&#xE708;" FontSize="11" Foreground="{DynamicResource TextSecondaryBrush}" 
                       FontFamily="Segoe MDL2 Assets" RenderTransformOrigin="0.5,0.5"
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

          <!-- Bottone Chiusura -->
          <Button x:Name="CloseButton" Width="28" Height="28"
                  HorizontalAlignment="Right" VerticalAlignment="Top"
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
                <Border CornerRadius="2.5" Background="$chargeColor" HorizontalAlignment="Left" Width="$chargeWidth" Margin="1.5"/>
              </Border>
              <Border Width="2.5" Height="8" CornerRadius="0.8" Background="{DynamicResource TextSecondaryBrush}" HorizontalAlignment="Right" VerticalAlignment="Center"/>
              <TextBlock Text="⚡" Foreground="White" FontSize="11" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="$lightningVisibility" Margin="0,0,4,0"/>
            </Grid>
            <!-- Stato e info carica -->
            <StackPanel Grid.Column="1" VerticalAlignment="Center">
              <TextBlock Text="Livello di Carica" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimaryBrush}" FontFamily="Segoe UI Variable Text, Segoe UI"/>
              <TextBlock Text="$chargeStatusText" FontSize="11" Foreground="{DynamicResource TextSecondaryBrush}" FontFamily="Segoe UI Variable Text, Segoe UI"/>
            </StackPanel>
            <!-- Percentuale -->
            <TextBlock Grid.Column="2" Text="$currentCharge%" FontSize="22" FontWeight="Bold" Foreground="{DynamicResource TextPrimaryBrush}" VerticalAlignment="Center" FontFamily="Segoe UI Variable Display, Segoe UI"/>
          </Grid>
        </Border>

        <Grid Grid.Row="3" Width="260" Height="260" HorizontalAlignment="Center">
          <Canvas Width="260" Height="260">
            <Ellipse Canvas.Left="30" Canvas.Top="30" Width="200" Height="200"
                     Stroke="{DynamicResource SeparatorBrush}" StrokeThickness="22"/>
            <Path Data="$arcData" Stroke="$color" StrokeThickness="22"
                  StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
          </Canvas>
          <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
            <TextBlock Text="$health%" FontSize="42" FontWeight="Bold" Foreground="{DynamicResource TextPrimaryBrush}"
                       HorizontalAlignment="Center" FontFamily="Segoe UI Variable Display, Segoe UI"/>
            <TextBlock Text="capacita' massima" FontSize="11" Foreground="{DynamicResource TextSecondaryBrush}"
                       HorizontalAlignment="Center" FontFamily="Segoe UI Variable Text, Segoe UI"/>
          </StackPanel>
        </Grid>

        <StackPanel Grid.Row="4" Margin="0,14,0,0">
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
          <TextBlock Grid.Column="0" Text="Capacita' attuale" Foreground="{DynamicResource TextSecondaryBrush}" FontFamily="Segoe UI Variable Text, Segoe UI"/>
          <TextBlock Grid.Column="1" Text="$([math]::Round($full,0).ToString('N0')) mWh" Foreground="{DynamicResource TextPrimaryBrush}" HorizontalAlignment="Right" FontFamily="Segoe UI Variable Text, Segoe UI"/>
        </Grid>
        <Rectangle Height="1" Fill="{DynamicResource SeparatorBrush}" Margin="0,4"/>
        <Grid Margin="0,7">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <TextBlock Grid.Column="0" Text="Capacita' originale" Foreground="{DynamicResource TextSecondaryBrush}" FontFamily="Segoe UI Variable Text, Segoe UI"/>
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

    # Associazione eventi pulsante chiusura
    $closeBtn = $window.FindName("CloseButton")
    $closeBtn.Add_Click({ $window.Close() })

    # Associazione eventi pulsante Tema (Luna/Sole)
    $themeBtn = $window.FindName("ThemeButton")
    $themeIcon = $window.FindName("ThemeIcon")
    $script:isDarkMode = $true
    $themeBtn.Add_Click({
        if ($script:isDarkMode) {
            # Passa a Light Mode (Stile chiaro iOS)
            $window.Resources["CardBgBrush"] = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFF2F2F7")
            $window.Resources["InnerCardBgBrush"] = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFFFF")
            $window.Resources["TextPrimaryBrush"] = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF000000")
            $window.Resources["TextSecondaryBrush"] = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF6C6C70")
            $window.Resources["SeparatorBrush"] = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFE5E5EA")
            $window.Resources["BatteryDischargingBrush"] = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF000000")
            $themeIcon.Text = [char]0xE706 # Sole (MDL2 Assets) per la modalità Light
            $themeIcon.FontSize = 13       # Il Sole necessita di una dimensione leggermente maggiore per bilanciamento visivo
            $script:isDarkMode = $false
        } else {
            # Passa a Dark Mode (Stile scuro iOS)
            $window.Resources["CardBgBrush"] = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF1C1C1E")
            $window.Resources["InnerCardBgBrush"] = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF2C2C2E")
            $window.Resources["TextPrimaryBrush"] = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFFFF")
            $window.Resources["TextSecondaryBrush"] = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF8E8E93")
            $window.Resources["SeparatorBrush"] = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF2C2C2E")
            $window.Resources["BatteryDischargingBrush"] = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFFFF")
            $themeIcon.Text = [char]0xE708 # Luna (MDL2 Assets) per la modalità Dark
            $themeIcon.FontSize = 11       # La Luna ha un peso visivo maggiore, perciò la riduciamo leggermente
            $script:isDarkMode = $true
        }
    })

    # Permette il trascinamento della finestra
    $dragHandle = $window.FindName("DragHandle")
    $dragHandle.Add_MouseLeftButtonDown({ $window.DragMove() })

    $window.ShowDialog() | Out-Null
}
catch {
    Show-ErrorBox "Si e' verificato un errore imprevisto:`n`n$($_.Exception.Message)`n`nRiga: $($_.InvocationInfo.ScriptLineNumber)"
}
