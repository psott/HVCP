Import-Module -Name Hyper-V
$Script:hvcpName = 'Hyper-V Console Plus'
$Script:hvcpVersion = 'v0.1'

If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")){
  $arguments = "& '" + $myinvocation.mycommand.definition + "'"
  Start-Process powershell -Verb runAs -ArgumentList $arguments
  Stop-Process -Id $PID
}

#region Functions
function Set-Overlay
{
  param(
    [switch]$hide,
    [switch]$show,
    [string]$message
  )
  if($hide){
    $window.overlay.Visibility = 'Hidden'
    $window.overLogo.Visibility = 'Hidden'
    $window.overVersion.Visibility = 'Hidden'
    $window.overVersion.Text = ''
    $window.overtext.Visibility = 'Hidden'
    $window.overtext.Text = ''
    
  }
  if($show){
    $window.overlay.Visibility = 'Visible'
    $window.overLogo.Visibility = 'Visible'
    $window.overVersion.Visibility = 'Visible'
    $window.overVersion.Text = "$Script:hvcpName $Script:hvcpVersion"
    $window.overtext.Visibility = 'Visible'
    $window.overtext.Text = $message
  }
  $window.Dispatcher.Invoke([Action]{},'Render')
}
function Set-Console
{
  param(
    [switch]$show,
    [switch]$hide
  )
  Add-Type -Name Window -Namespace Console -MemberDefinition '
    [DllImport("Kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
  '
  $consolePtr = [Console.Window]::GetConsoleWindow()
  if($show){
    [Console.Window]::ShowWindow($consolePtr, 1)
  }
  if($hide){
    [Console.Window]::ShowWindow($consolePtr, 0)
  }
  
  
}

function Get-Preferences
{
  if(!($PSVersionTable.PSVersion.Major -ge 4)){
    Get-Popup -mes 'HVCP needs Powershell 4 or higher.' -info 'Old Powershell version'
  }
}
function Get-Popup
{
    param(
      $mes,  
      $info
    )
    $wshell = New-Object -ComObject Wscript.Shell
    $wshell.Popup("$mes",0,"$info",0)
}
function Convert-XAMLtoWindow
{
  param
  (
    [Parameter(Mandatory)]
    [string]
    $XAML,
    
    [string[]]
    $NamedElement=$null,
    
    [switch]
    $PassThru
  )
  
  Add-Type -AssemblyName PresentationFramework
  
  $reader = [XML.XMLReader]::Create([IO.StringReader]$XAML)
  $result = [Windows.Markup.XAMLReader]::Load($reader)
  foreach($Name in $NamedElement)
  {
    $result | Add-Member NoteProperty -Name $Name -Value $result.FindName($Name) -Force
  }
  
  if ($PassThru)
  {
    $result
  }
  else
  {
    $null = $window.Dispatcher.InvokeAsync{
      $result = $window.ShowDialog()
      Set-Variable -Name result -Value $result -Scope 1
    }.Wait()
    $result
  }
}

function Show-WPFWindow
{
  param
  (
    [Parameter(Mandatory)]
    [Windows.Window]
    $Window
  )
  
  $result = $null
  $null = $window.Dispatcher.InvokeAsync{
    $result = $window.ShowDialog()
    Set-Variable -Name result -Value $result -Scope 1
  }.Wait()
  $result
}
function Get-VMScreenshot
{
  param(
    $HyperVParent, #localhost
    $HyperVGuest, #Win10-Insider
    $xRes, #640
    $yRes #480
  )
  #Credits Taylor Brown
  $HyperVParent = ($window.lvs.SelectedItem).Name
  if($HyperVParent -ne $null){
    $HyperVGuest = ($window.lv.SelectedItem).Name
    if($HyperVGuest -ne $null){
      [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
      $ImagePath = "C:\Temp\hvcp" 
      $VMManagementService = Get-WmiObject -class "Msvm_VirtualSystemManagementService" -namespace "root\virtualization\v2" -ComputerName $HyperVParent 
      $Vm = Get-WmiObject -Namespace "root\virtualization\v2" -ComputerName $HyperVParent -Query "Select * From Msvm_ComputerSystem Where ElementName='$HyperVGuest'" 
      $VMSettingData = Get-WmiObject -Namespace "root\virtualization\v2" -Query "Associators of {$Vm} Where ResultClass=Msvm_VirtualSystemSettingData AssocClass=Msvm_SettingsDefineState" -ComputerName $HyperVParent 
      $RawImageData = $VMManagementService.GetVirtualSystemThumbnailImage($VMSettingData, "$xRes", "$yRes")
      $VMThumbnail = New-Object System.Drawing.Bitmap($xRes, $yRes, [System.Drawing.Imaging.PixelFormat]::Format16bppRgb565)
      $rectangle = New-Object System.Drawing.Rectangle(0,0,$xRes,$yRes) 
      [System.Drawing.Imaging.BitmapData] $VMThumbnailBitmapData = $VMThumbnail.LockBits($rectangle, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format16bppRgb565) 
      [System.Runtime.InteropServices.marshal]::Copy($RawImageData.ImageData, 0, $VMThumbnailBitmapData.Scan0, $xRes*$yRes*2) 
      $VMThumbnail.UnlockBits($VMThumbnailBitmapData)
      $rnd = Get-Random -Minimum 100 -Maximum 999
      $VMThumbnail.Save("$ImagePath\$HyperVGuest-$rnd-vmtemp.png")

      $window.image.Source = "$ImagePath\$HyperVGuest-$rnd-vmtemp.png"
    }
  }
}
function Get-VMList
{
  $selIndex = $window.lv.SelectedIndex
  $window.lv.Items.Clear()
  $selHost = ($window.lvs.SelectedItem).Name
  if($selHost -ne $null){
    $GetVM = Get-VM -ComputerName $selHost | ForEach-Object {
      $ma = ($_.MemoryAssigned)/1MB
      $md = ($_.MemoryDemand)/1MB
      $ut = "$($_.Uptime.Days)d $($_.Uptime.Hours)h $($_.Uptime.Minutes)m $($_.Uptime.Seconds)s"
      [PSCustomObject]@{
        Name = $_.Name
        State = $_.State
        Uptime = $ut
        ProcessorCount = $_.ProcessorCount
        CPUUsage = $_.CPUUsage
        MemoryAssigned = $ma
        MemoryDemand = $md
        Version = $_.Version
        VirtualMachineSubType = $_.VirtualMachineSubType
      }
    }
    $GetVM | ForEach-Object {$window.lv.AddChild($_)}
  }
  $window.lv.SelectedIndex = $selIndex
}
function Start-Timer
{
    Add-Type -AssemblyName System.Windows.Forms
    $Script:timer = New-Object System.Windows.Forms.Timer
    $Script:timer.Interval = 5000 #5sek
    $Script:timer.add_tick({Get-VMList})
    $Script:timer.Start()
}
#endregion 

#region Windows
function Get-AddServer
{
  $xamladdserver = @'
<Window
   xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
   xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
   Height="220" Width ="400" Title="add Hyper-V server" ResizeMode="NoResize" WindowStartupLocation="CenterScreen">
    <Grid>
        <Label Content="Server Name or IP:" HorizontalAlignment="Left" Margin="10,10,0,0" VerticalAlignment="Top"/>
        <TextBox Name="TBnewServer" HorizontalAlignment="Left" Height="23" Margin="123,13,0,0" TextWrapping="Wrap" Text="" VerticalAlignment="Top" Width="240"/>

        <Label Content="User name:" HorizontalAlignment="Left" Margin="49,41,0,0" VerticalAlignment="Top"/>
        <TextBox Name="TBuser" HorizontalAlignment="Left" Height="23" Margin="123,45,0,0" TextWrapping="Wrap" Text="" VerticalAlignment="Top" Width="240"/>
        
        <Label Content="Password:" HorizontalAlignment="Left" Margin="56,72,0,0" VerticalAlignment="Top"/>
        <PasswordBox Name="TBpass" HorizontalAlignment="Left" Margin="123,73,0,0" VerticalAlignment="Top" Width="240" Height="23"/>
        
        <CheckBox Name="CBWinCred" Content="Use Windows session credentials" HorizontalAlignment="Left" Margin="123,101,0,0" VerticalAlignment="Top"/>
        <CheckBox Name="CBsaveCred" Content="Save credentials" HorizontalAlignment="Left" Margin="123,121,0,0" VerticalAlignment="Top"/>
        
        <Button Name="BAddServer" IsDefault="True" Content="add server" HorizontalAlignment="Left" Margin="10,158,0,0" VerticalAlignment="Top" Width="164"/>
        <Button Name="BCancle" IsDefault="True" Content="cancle" HorizontalAlignment="Left" Margin="211,158,0,0" VerticalAlignment="Top" Width="152"/>
    </Grid>
</Window>
'@
  $winaddserver = Convert-XAMLtoWindow -XAML $xamladdserver -NamedElement 'BAddServer', 'BCancle', 'CBsaveCred', 'CBWinCred', 'TBnewServer', 'TBpass', 'TBuser' -PassThru

  function Get-ServerConnection
  {
    $srv = $winaddserver.TBnewServer.Text
    if($srv -ne ''){
      if(Test-Connection -ComputerName $srv -Count 1 -ErrorAction SilentlyContinue){
        Write-Host 'ping ok'
        if($true){ #creds prüfen
          Write-Output $true
        }
        else{
          Get-Popup -mes 'Server is empty' -info 'error'
          Write-Output $false
        }
      }
      else{
        Get-Popup -mes "Could not connect to $srv" -info 'Ping error'
        Write-Output $false
      }
    }
    else{
      Get-Popup -mes 'Server is empty' -info 'Input error'
    }
  }
  
  $winaddserver.CBWinCred.add_Checked{
    $winaddserver.TBuser.IsEnabled = $false
    $winaddserver.TBpass.IsEnabled = $false
    $winaddserver.CBsaveCred.IsEnabled = $false
    $winaddserver.TBuser.Text = ''
    $winaddserver.TBpass.Password = ''
  }
  $winaddserver.CBWinCred.add_UnChecked{
    $winaddserver.TBuser.IsEnabled = $true
    $winaddserver.TBpass.IsEnabled = $true
    $winaddserver.CBsaveCred.IsEnabled = $true
  }
  $winaddserver.CBsaveCred.add_Checked{
    $winaddserver.CBWinCred.IsEnabled = $false
  }
  $winaddserver.CBsaveCred.add_UnChecked{
    $winaddserver.CBWinCred.IsEnabled = $true
  }

  $winaddserver.BAddServer.add_Click{
    Get-ServerConnection
  }

  $winaddserver.BCancle.add_Click{
    $winaddserver.DialogResult = $false
  }

  $result = Show-WPFWindow -Window $winaddserver

  if ($result -eq $true)
  {
    [PSCustomObject]@{
      Server = $winaddserver.TBnewServer.Text
      User = $winaddserver.TBuser.Text
      Password = $winaddserver.TBpass.Password
      WinCred = $winaddserver.CBWinCred.IsChecked
      SaveCred = $winaddserver.CBsaveCred.IsChecked
    }
  }
  else
  {
    #Write-Warning 'User aborted dialog.'
  }
}
function Get-NewVM
{
  $xamlnewvm = @'
<Window
   xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
   xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
   Height="540"
   Width ="500"
   Title="Create Virtual Machine"
   Topmost="True" WindowStartupLocation="CenterScreen">
    <Grid>
        <Label Content="Name" HorizontalAlignment="Left" Margin="30,39,0,0" VerticalAlignment="Top" Background="{x:Null}" Foreground="#FF2C92D8" FontSize="18"/>
        <TextBox Name="textBox" HorizontalAlignment="Left" Height="37" Margin="36,78,0,0" TextWrapping="Wrap" Text="New Virtual Machine" VerticalAlignment="Top" Width="194" FontSize="16" Padding="11,4,0,0"/>
        <Label Content="Operating System" HorizontalAlignment="Left" Margin="36,143,0,0" VerticalAlignment="Top" Background="{x:Null}" Foreground="#FF2C92D8" FontSize="18"/>
        <Label Content="You can install from an ISO image file (.iso) or a virtual hard disk file (.vhd or .vhdx)." HorizontalAlignment="Left" Margin="36,182,0,0" VerticalAlignment="Top"/>
        <Button Name="button" Content="Change installation source..." HorizontalAlignment="Left" Margin="113,213,0,0" VerticalAlignment="Top" Width="309" Height="43" FontSize="14"/>
        <CheckBox Name="checkBox" Content="This virtual machine will run Windows (enables Windows Secure Boot)" HorizontalAlignment="Left" Margin="36,270,0,0" VerticalAlignment="Top"/>
        <Label Content="Network" HorizontalAlignment="Left" Margin="36,317,0,0" VerticalAlignment="Top" Background="{x:Null}" Foreground="#FF2C92D8" FontSize="18"/>
        <ComboBox Name="comboBox" HorizontalAlignment="Left" Margin="36,356,0,0" VerticalAlignment="Top" Width="194"/>
        <Button Name="BCreateVM" Content="Create Virtual Machine" HorizontalAlignment="Left" Margin="30,447,0,0" VerticalAlignment="Top" Width="215" Height="40" FontSize="16" Foreground="White" Background="#FF1969DC"/>
        <Button Name="BCloseVM" Content="Close" HorizontalAlignment="Left" Margin="256,447,0,0" VerticalAlignment="Top" Width="215" Height="40" FontSize="16"/>
    </Grid>
</Window>
'@
  $windowNewVM = Convert-XAMLtoWindow -XAML $xamlnewvm -NamedElement 'button', 'BCreateVM', 'BCloseVM', 'checkBox', 'comboBox', 'textBox' -PassThru
  $resultNewVM = Show-WPFWindow -Window $windowNewVM
}
function Get-Options
{
  $xamloptions = @'
<Window
   xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
   Height="400"
   Width ="400"
   Title="Options" ResizeMode="NoResize"
   Topmost="True" WindowStartupLocation="CenterScreen">
    <Grid>
        <Label Content="Options..." HorizontalAlignment="Left" Margin="166,157,0,0" VerticalAlignment="Top"/>
        <Button Name="BOptOK" Content="OK" HorizontalAlignment="Left" Margin="229,341,0,0" VerticalAlignment="Top" Width="75"/>
        <Button Name="BOptCan" Content="Cancel" HorizontalAlignment="Left" Margin="309,341,0,0" VerticalAlignment="Top" Width="75"/>
    </Grid>
</Window>
'@
  $winoptions = Convert-XAMLtoWindow -XAML $xamloptions -NamedElement 'BOptCan', 'BOptOK' -PassThru

  $winoptions.BOptOK.add_Click{
    $winoptions.Close()
  }
  $winoptions.BOptCan.add_Click{
    $winoptions.Close()
  }

  $result = Show-WPFWindow -Window $winoptions
}
function Get-About
{
  $xamlabout = @'
<Window
   xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
   Height="400"
   Width ="400"
   Title="About" ResizeMode="NoResize"
   Topmost="True" WindowStartupLocation="CenterScreen">
    <Grid>
        <TextBlock Name="github" HorizontalAlignment="Left" Margin="168,158,0,0" TextWrapping="Wrap" Text="github link" VerticalAlignment="Top" TextDecorations="Underline" Cursor="Hand"/>
        <Button Name="BAbCan" Content="Cancel" HorizontalAlignment="Left" Margin="309,341,0,0" VerticalAlignment="Top" Width="75"/>
    </Grid>
</Window>
'@
  $winabout = Convert-XAMLtoWindow -XAML $xamlabout -NamedElement 'BAbCan', 'github' -PassThru

  $winabout.github.add_MouseLeftButtonUp{
    [System.Diagnostics.Process]::Start("https://github.com/psott/HVCP")
  }
  
  $winabout.BAbCan.add_Click{
    $winabout.Close()
  }
  
  $result = Show-WPFWindow -Window $winabout
}
function Get-VMSettings
{
  $xamlvmsettings = @'
<Window
   xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
   xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
   Height="410" MinHeight="410" Width ="500" MinWidth ="500"
    Title="Settings" WindowStartupLocation="CenterScreen">
    <Grid>
        <TextBlock HorizontalAlignment="Left" Margin="243,152,0,0" TextWrapping="Wrap" Text="soon..." VerticalAlignment="Top"/>
        <ComboBox x:Name="VSvmname" HorizontalAlignment="Left" Margin="10,10,0,0" VerticalAlignment="Top" Width="120"/>

        <ListView x:Name="VSlv2" HorizontalAlignment="Left" Margin="10,37,0,50" VerticalAlignment="Stretch" Width="120">
            <ListViewItem>
                <StackPanel Orientation="Horizontal">
                    <Path Width="15" Height="15" Stretch="Uniform" Fill="Black" Data="M10.8,21.500014L22.3,21.500014 22.3,24.500016 24.7,24.500016 24.7,26.700018 8.4000001,26.700018 8.4000001,24.500016 10.8,24.500016z M1.9000006,1.8999996L1.9000006,17.600011 30.1,17.600011 30.1,1.8999996z M0,0L32,0 32,19.500013 0,19.500013z" />
                    <TextBlock Margin="5,0,0,0"><Run Text="BIOS"/></TextBlock>
                </StackPanel>
            </ListViewItem>
            <ListViewItem>
                <StackPanel Orientation="Horizontal">
                    <Path Width="15" Height="15" Stretch="Uniform" Fill="Black" Data="M12.408653,6.1999965C12.408653,6.1999965 16.608697,8.7999954 19.308725,8.2999954 19.308725,8.2999957 20.608739,17.199991 12.408653,24.399988 4.2085681,17.099991 5.5085816,8.2999957 5.5085816,8.2999954 8.2086098,8.6999955 12.408653,6.1999965 12.408653,6.1999965z M12.408653,2.6999979C12.408653,2.6999979 6.4085913,6.3999968 2.5085506,5.6999969 2.5085506,5.6999969 0.608531,18.399991 12.408653,28.799985 24.308777,18.399991 22.308756,5.6999969 22.308756,5.6999969 18.508717,6.2999964 12.408653,2.6999979 12.408653,2.6999979z M12.408653,0L14.00867,0.99999905C15.608686,1.8999987,18.708719,3.3999977,20.708739,3.3999977L21.108744,3.3999977 24.208776,2.8999987 24.708781,5.9999967C24.808783,6.5999966,26.608802,19.59999,14.508675,30.199985L12.408653,31.999984 10.308632,30.199985C-1.7914944,19.59999,0.10852528,6.4999967,0.10852528,5.9999967L0.608531,2.8999987 3.7085629,3.3999977 4.1085672,3.3999977C6.1085877,3.3999977,9.5086232,1.7999983,10.808637,0.99999905z" />
                    <TextBlock Margin="5,0,0,0"><Run Text="Security"/></TextBlock>
                </StackPanel>
            </ListViewItem>
            <ListViewItem>
                <StackPanel Orientation="Horizontal">
                    <Path Width="15" Height="15" Stretch="Uniform" Fill="Black" Data="M22.999985,6.0000229L22.999985,12.000023 24.999985,12.000023 24.999985,6.0000229z M14.999985,6.0000229L14.999985,12.000023 16.999985,12.000023 16.999985,6.0000229z M6.9999852,6.0000229L6.9999852,12.000023 8.9999847,12.000023 8.9999847,6.0000229z M20.999985,4.0000229L26.999985,4.0000229 26.999985,14.000023 20.999985,14.000023z M12.999985,4.0000229L18.999985,4.0000229 18.999985,14.000023 12.999985,14.000023z M4.9999852,4.0000229L10.999985,4.0000229 10.999985,14.000023 4.9999852,14.000023z M2,2L2,8.2669678C2.6410217,8.9699707,3,9.8809814,3,10.830017L3,11.169983C3,12.119019,2.6410217,13.029968,2,13.732971L2,20 4,20 4,19C4,17.346008 5.3460083,16 7,16 8.6540222,16 10,17.346008 10,19L10,20 13,20 13,19C13,17.346008 14.346008,16 16,16 17.654022,16 19,17.346008 19,19L19,20 22,20 22,19C22,17.346008 23.346008,16 25,16 26.654022,16 28,17.346008 28,19L28,20 30,20 30,13.732971C29.359009,13.029968,29,12.119019,29,11.169983L29,10.830017C29,9.8809814,29.359009,8.9699707,30,8.2669678L30,2z M0,0L32,0 32,9.1469727 31.649994,9.4469604C31.231018,9.8059692,31,10.296997,31,10.830017L31,11.169983C31,11.703003,31.231018,12.19397,31.649994,12.552979L32,12.852966 32,22 26,22 26,19C26,18.447998 25.550995,18 25,18 24.449005,18 24,18.447998 24,19L24,22 17,22 17,19C17,18.447998 16.550995,18 16,18 15.449005,18 15,18.447998 15,19L15,22 8,22 8,19C8,18.447998 7.5509949,18 7,18 6.4490051,18 6,18.447998 6,19L6,22 0,22 0,12.852966 0.3500061,12.552979C0.76901245,12.19397,1,11.703003,1,11.169983L1,10.830017C1,10.296997,0.76901245,9.8059692,0.3500061,9.4469604L0,9.1469727z"/>
                    <TextBlock Margin="5,0,0,0"><Run Text="Memory"/></TextBlock>
                </StackPanel>
            </ListViewItem>
            <ListViewItem>
                <StackPanel Orientation="Horizontal">
                    <Path Width="15" Height="15" Stretch="Uniform" Fill="Black" Data="M11.000003,10.999997L11.000003,20.999997 21.000003,20.999997 21.000003,10.999997z M9.0000027,8.9999969L23.000003,8.9999969 23.000003,22.999997 9.0000027,22.999997z M6.0000002,5.9999993L6.0000002,25.999999 26.000001,25.999999 26.000001,5.9999993z M6.0000002,0L7.9999998,0 7.9999998,3.9999995 15,3.9999995 15,0 17,0 17,3.9999995 24,3.9999995 24,0 26.000001,0 26.000001,3.9999995 28.000001,3.9999995 28.000001,7.9999998 32.000001,7.9999998 32.000001,9.9999993 28.000001,9.9999993 28.000001,15 32.000001,15 32.000001,17 28.000001,17 28.000001,22 32.000001,22 32.000001,24 28.000001,24 28.000001,27.999999 26.000001,27.999999 26.000001,31.999999 24,31.999999 24,27.999999 17,27.999999 17,31.999999 15,31.999999 15,27.999999 8.0000002,27.999999 8.0000002,31.999999 6.0000002,31.999999 6.0000002,27.999999 4,27.999999 4,24 0,24 0,22 4,22 4,17 0,17 0,15 4,15 4,9.9999999 0,9.9999999 0,7.9999998 4,7.9999998 4,3.9999995 6.0000002,3.9999995z"/>
                    <TextBlock Margin="5,0,0,0"><Run Text="Processor"/></TextBlock>
                </StackPanel>
            </ListViewItem>
            <ListViewItem>
                <StackPanel Orientation="Horizontal">
                    <Path Width="15" Height="15" Stretch="Uniform" Fill="Black" Data="M11.918032,18.540007C10.815031,18.540007 9.9180317,19.437006 9.9180317,20.540007 9.9180317,21.643007 10.815031,22.540007 11.918032,22.540007 13.021031,22.540007 13.918032,21.643007 13.918032,20.540007 13.918032,19.437006 13.021031,18.540007 11.918032,18.540007z M11.918032,17.540007C13.572031,17.540007 14.918032,18.886007 14.918032,20.540007 14.918032,22.194006 13.572031,23.540007 11.918032,23.540007 10.264031,23.540007 8.9180317,22.194006 8.9180317,20.540007 8.9180317,18.886007 10.264031,17.540007 11.918032,17.540007z M11.918032,12.006998C12.281032,12.006998 12.646032,12.029998 13.000032,12.073997 13.273033,12.109998 13.468034,12.359998 13.433033,12.633998 13.397034,12.907998 13.138033,13.095998 12.873033,13.066998 12.561032,13.026999 12.241032,13.006998 11.918032,13.006998 7.7640262,13.006998 4.3850222,16.386 4.3850222,20.540001 4.3850222,24.694002 7.7640262,28.073004 11.918032,28.073004 16.072036,28.073004 19.451041,24.694002 19.451041,20.540001 19.451041,17.709999 17.889039,15.143999 15.373035,13.843999 15.128036,13.716998 15.031035,13.414998 15.158035,13.169998 15.286036,12.922998 15.589036,12.830998 15.832036,12.954998 18.68204,14.427999 20.451041,17.334 20.451041,20.540001 20.451041,25.245003 16.623036,29.073004 11.918032,29.073004 7.2130256,29.073004 3.385021,25.245003 3.3850207,20.540001 3.385021,15.834999 7.2130256,12.006998 11.918032,12.006998z M16.497003,5.0240541C16.546391,5.0232878 16.596885,5.0299091 16.647132,5.0447221 16.912118,5.1217241 17.06511,5.3987308 16.988114,5.6637373L13.933269,16.169991C13.870273,16.387997 13.670283,16.529999 13.453294,16.529999 13.407296,16.529999 13.360299,16.524 13.313301,16.509998 13.049314,16.432997 12.895322,16.154991 12.973318,15.889984L16.027164,5.3847303C16.089723,5.1694126,16.282987,5.0273738,16.497003,5.0240541z M2.7669997,2C2.3439956,2,2.0000012,2.3439941,2.000001,2.7660065L2.000001,29.233994C2.0000012,29.656006,2.3439956,30,2.7669997,30L21.068006,30C21.49101,30,21.833997,29.656006,21.833997,29.233994L21.833997,2.7660065C21.833997,2.3439941,21.49101,2,21.068006,2z M2.7669997,0L21.068006,0C22.593001,0,23.833999,1.2409973,23.833999,2.7660065L23.833999,29.233994C23.833999,30.759003,22.593001,32,21.068006,32L2.7669997,32C1.2419746,32,1.7007551E-08,30.759003,0,29.233994L0,2.7660065C1.7007551E-08,1.2409973,1.2419746,0,2.7669997,0z"/>
                    <TextBlock Margin="5,0,0,0"><Run Text="Drives"/></TextBlock>
                </StackPanel>
            </ListViewItem>
            <ListViewItem>
                <StackPanel Orientation="Horizontal">
                    <Path Width="15" Height="15" Stretch="Uniform" Fill="Black" Data="M22,24L22,30 30,30 30,24z M2,24L2,30 10,30 10,24z M10,2L10,10 22,10 22,2z M8,0L24,0 24,12 17,12 17,16 26,16 27,16.000008 27,22 32,22 32,32 20,32 20,22 25,22 25,18 7,18 7,22 12,22 12,32 0,32 0,22 5,22 5,16 6.011013,16 7,16 15,16 15,12 8,12z"/>
                    <TextBlock Margin="5,0,0,0"><Run Text="Network"/></TextBlock>
                </StackPanel>
            </ListViewItem>
        </ListView>

        <Button x:Name="VSok" Content="ok" HorizontalAlignment="Right" Margin="0,0,170,10" VerticalAlignment="Bottom" Width="75"/>
        <Button x:Name="VScan" Content="cancel" HorizontalAlignment="Right" Margin="0,0,90,10" VerticalAlignment="Bottom" Width="75"/>
        <Button x:Name="VSapp" Content="apply" HorizontalAlignment="Right" Margin="0,0,10,10" VerticalAlignment="Bottom" Width="75"/>
        <TabControl x:Name="tabControl" HorizontalAlignment="Stretch" Margin="150,15,5,45" VerticalAlignment="Stretch" BorderBrush="{x:Null}" >
            <TabItem Header="1">
                <Grid>
                    <TextBlock HorizontalAlignment="Left" Margin="52,43,0,0" TextWrapping="Wrap" Text="BIOS soon..." VerticalAlignment="Top"/>
                </Grid>
            </TabItem>
            <TabItem Header="2">
                <Grid>
                    <TextBlock HorizontalAlignment="Left" Margin="52,43,0,0" TextWrapping="Wrap" Text="Sec soon..." VerticalAlignment="Top"/>
                </Grid>
            </TabItem>
            <TabItem Header="3">
                <Grid>
                    <TextBlock HorizontalAlignment="Left" Margin="52,43,0,0" TextWrapping="Wrap" Text="Mem soon..." VerticalAlignment="Top"/>
                </Grid>
            </TabItem>
            <TabItem Header="4">
                <Grid>
                    <TextBlock HorizontalAlignment="Left" Margin="10,10,0,0" TextWrapping="Wrap" Text="Number of virtual processors:" VerticalAlignment="Top"/>
                    <StackPanel HorizontalAlignment="Left" VerticalAlignment="Top" Height="20" Width="70" Orientation="Horizontal" Margin="251,6,0,0">
                        <TextBox Name="CPUcores" IsReadOnly="True" Width="30" Text="1"/>
                        <Button Name="CPUup" Content="˄" Width="20" />
                        <Button Name="CPUdown" Content="˅" Width="20" />
                    </StackPanel>
                    <Separator Height="10" Width="311"  HorizontalAlignment="Left" VerticalAlignment="Top" Margin="10,27,0,0"/>
                    <CheckBox Name="CBnested"  HorizontalAlignment="Left" VerticalAlignment="Top" Content="Enable nested virtualisation" Margin="10,42,0,0"/>
                </Grid>
            </TabItem>
            <TabItem Header="5">
                <Grid>
                    <TextBlock HorizontalAlignment="Left" Margin="52,43,0,0" TextWrapping="Wrap" Text="Drive soon..." VerticalAlignment="Top"/>
                </Grid>
            </TabItem>
            <TabItem Header="6">
                <Grid>
                    <TextBlock HorizontalAlignment="Left" Margin="52,43,0,0" TextWrapping="Wrap" Text="Net soon..." VerticalAlignment="Top"/>
                </Grid>
            </TabItem>
        </TabControl>
        <Rectangle Fill="White" HorizontalAlignment="Stretch" Height="25" Margin="150,13,5,0" VerticalAlignment="Top"/>
    </Grid>
</Window>
'@
  $winvmsettings = Convert-XAMLtoWindow -XAML $xamlvmsettings -NamedElement 'CBnested', 'CPUcores', 'CPUdown', 'CPUup', 'tabControl', 'VSapp', 'VScan', 'VSlv2', 'VSok', 'VSvmname' -PassThru
  $winvmsettings.CPUup.add_Click{
    [int]$current = $winvmsettings.CPUcores.Text
    if($current -le 15){
      $winvmsettings.CPUcores.Text = $current + 1 
    }  
  }
  $winvmsettings.CPUdown.add_Click{
    [int]$current = $winvmsettings.CPUcores.Text
    if($current -ge 2){
      $winvmsettings.CPUcores.Text = $current - 1
    }
  }
  $winvmsettings.VSvmname.add_SelectionChanged{
    $winvmsettings.Title = "Settings for $($winvmsettings.VSvmname.SelectedItem)"
  }
  $winvmsettings.VSlv2.add_SelectionChanged{
    $winvmsettings.tabControl.SelectedIndex = $winvmsettings.VSlv2.SelectedIndex
  }
  $winvmsettings.VSlv2.SelectedIndex = 0
  
  $selHost = ($window.lvs.SelectedItem).Name
  Get-VM -ComputerName $selHost | select -ExpandProperty Name | foreach{$winvmsettings.VSvmname.AddChild($_)}
  $winvmsettings.VSvmname.SelectedItem = $window.lv.SelectedItem.Name
  $winvmsettings.Title = "Settings for $($window.lv.SelectedItem.Name)"
  
  $result = Show-WPFWindow -Window $winvmsettings
}

#endregion Windows


#region XAML
$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Width="1150" MinWidth="1000"
    Height ="400" MinHeight ="400"
    SizeToContent="Height"
    Title="Hyper-V Console Plus"
    Background="#FFCBCBCB" WindowStartupLocation="CenterScreen">
    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition MinWidth="150" Width="200" />
            <ColumnDefinition Width="5" />
            <ColumnDefinition Width="*" />
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="20" />
            <RowDefinition Height="*" />
        </Grid.RowDefinitions>
        <DockPanel Grid.ColumnSpan="3">
            <Menu DockPanel.Dock="Top">
                <MenuItem Header="_File">
                    <MenuItem Name="MOptions" Header="Options" />
                    <MenuItem Name="MExit" Header="Exit" />
                </MenuItem>
                <MenuItem Header="Action">
                    <MenuItem Name="MQuick" Header="Quick Create" />
                </MenuItem>
                <MenuItem Header="Help">
                    <MenuItem Name="MAbout" Header="About Hyper-V Console Plus" /> 
                </MenuItem>
            </Menu>
        </DockPanel>
        <Grid Grid.Column="0" Grid.Row="1">
          <ListView Name="lvs" Margin="5,5,5,30">
                <ListView.ContextMenu>
                    <ContextMenu>
                        <MenuItem Name ="CMSConnect" Header="Connect"/>
                        <MenuItem Name ="CMSDisconnect" Header="Disconnect"/>
                        <MenuItem Name ="CMSDelete" Header="Delete"/>
                    </ContextMenu>
                </ListView.ContextMenu>
                <ListView.View>
                    <GridView>
                        <GridViewColumn Header="Name" DisplayMemberBinding="{Binding 'Name'}" Width="180"/>
                    </GridView>
                </ListView.View>
            </ListView>
            <Button Name="BAdd" Content="add server" HorizontalAlignment="Left" Margin="5,0,0,5" VerticalAlignment="Bottom" Width="65"/>
        </Grid>
        <GridSplitter Grid.Column="1" Grid.Row="1" Width="5" HorizontalAlignment="Stretch" />
        <Grid Grid.Column="2" Grid.Row="1">
            <ListView Name="lv" HorizontalAlignment="Stretch" Margin="5,5,00,190" VerticalAlignment="Stretch">
                <ListView.ContextMenu>
                    <ContextMenu>
                        <MenuItem Name ="CMConnect" Header="Connect"/>
                        <Separator/>
                        <MenuItem Name ="CMStart" Header="Start"/>
                        <MenuItem Name ="CMRestart" Header="HardRestart"/>
                        <MenuItem Name ="CMShutdown" Header="Shutdown"/>
                        <MenuItem Name ="CMPowerOff" Header="Power off"/>
                        <MenuItem Name ="CMSave" Header="Save (to disk)"/>
                        <MenuItem Name ="CMPause" Header="Pause (keep in RAM)"/>
                        <Separator/>
                        <MenuItem Name ="CMSnapshot" Header="Take Snapshot"/>
                        <Separator/>
                        <MenuItem Name ="CMMove" Header="Move"/>
                        <MenuItem Name ="CMExport" Header="Export"/>
                        <MenuItem Name ="CMDelete" Header="Delete"/>
                        <MenuItem Name ="CMDeleteDisk" Header="Delete from disk"/>
                        <Separator/>
                        <MenuItem Name ="CMSettings" Header="Settings"/>
                    </ContextMenu>
                </ListView.ContextMenu>
                <ListView.View>
                    <GridView>
                        <GridViewColumn Header="Name" DisplayMemberBinding="{Binding 'Name'}" Width="180"/>
                        <GridViewColumn Header="State" DisplayMemberBinding="{Binding 'State'}" Width="60"/>
                        <GridViewColumn Header="Uptime" DisplayMemberBinding="{Binding 'Uptime'}" Width="120"/>
                        <GridViewColumn Header="CPU Cores" DisplayMemberBinding="{Binding 'ProcessorCount'}" Width="60"/>
                        <GridViewColumn Header="CPUUsage" DisplayMemberBinding="{Binding 'CPUUsage'}" Width="60"/>
                        <GridViewColumn Header="MemoryAssigned" DisplayMemberBinding="{Binding 'MemoryAssigned'}" Width="auto"/>
                        <GridViewColumn Header="MemoryDemand" DisplayMemberBinding="{Binding 'MemoryDemand'}" Width="auto"/>
                        <GridViewColumn Header="Version" DisplayMemberBinding="{Binding 'Version'}" Width="60"/>
                        <GridViewColumn Header="VMGeneration" DisplayMemberBinding="{Binding 'VirtualMachineSubType'}" Width="140"/>
                    </GridView>
                </ListView.View>
            </ListView>
            <Rectangle Height="180" Width="240" HorizontalAlignment="Left" VerticalAlignment="Bottom" Margin="5" Fill="#FFBDBDBD"/>
            <Image x:Name="image" Height="180" Width="240" HorizontalAlignment="Left" VerticalAlignment="Bottom" Margin="5"/>
        </Grid>

        <Rectangle Name="overlay" Grid.ColumnSpan="3" Grid.RowSpan="3" Fill="#D8497199" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Visibility="Visible"/>

        <Path Name="overLogo" Grid.ColumnSpan="3" Grid.RowSpan="3" HorizontalAlignment="Center" VerticalAlignment="Center" Stretch="Uniform" Fill="#FFFCFCFC" Width="138" Height="138" Margin="0,-100,0,0" Visibility="Visible" RenderTransformOrigin="0.5,0.5" Data="F1 M 20,20L 56,20L 56,56L 20,56L 20,20 Z M 24,24L 24,52L 52,52L 52,24L 24,24 Z M 31,36L 36,36L 36,31L 40,31L 40,36L 45,36L 45,40L 40,40L 40,45L 36,45L 36,40L 31,40L 31,36 Z " />
        <TextBlock Name="overVersion" Grid.ColumnSpan="3" Grid.RowSpan="3" HorizontalAlignment="Center" Margin="0,70,0,0" TextWrapping="Wrap" Text="Hyper-V Console Plus " VerticalAlignment="Center" FontSize="20" Foreground="White" FontWeight="Bold" FontStyle="Italic" Visibility="Visible"/>
        <TextBlock Name="overtext" Grid.ColumnSpan="3" Grid.RowSpan="3" HorizontalAlignment="Center" Margin="0,150,0,0" TextWrapping="Wrap" Text="loading database . . . " VerticalAlignment="Center" FontSize="20" Foreground="White" Visibility="Visible"/>
        
    </Grid>
</Window>
'@

#endregion
$window = Convert-XAMLtoWindow -XAML $xaml -NamedElement 'overlay','overLogo','overVersion','overtext','CMPause','MOptions','MExit','MAbout','CMSDelete','CMSDisconnect','CMSConnect','CMConnect','CMRestart','CMSave','CMShutdown','CMPowerOff','CMSnapshot','CMMove','CMExport','CMDelete','CMDeleteDisk','CMSettings','CMStart','image','lv','lvs','BAdd','MQuick' -PassThru

$window.MOptions.add_Click{
  $Script:timer.Stop()
  Get-Options
  $Script:timer.Start()
  
}
$window.MExit.add_Click{
  $window.Close()
}
$window.MAbout.add_Click{
  $Script:timer.Stop()
  Get-About
  $Script:timer.Start()
}
$window.MQuick.add_Click{
  $Script:timer.Stop()
  Get-NewVM
  $Script:timer.Start()
}

$window.CMConnect.add_Click{
  $selItem = ($window.lv.SelectedItem).Name
  Start-Process vmconnect -ArgumentList "localhost $selItem"
}
$window.lv.add_MouseDoubleClick{
  $selItem = ($window.lv.SelectedItem).Name
  Start-Process vmconnect -ArgumentList "localhost $selItem"
}

$window.CMStart.add_Click{
  $selItem = $window.lv.SelectedItem
  if($selItem.State -eq 'Paused'){
    Resume-VM -Name $selItem.Name -AsJob
  }
  else{
    Start-VM -Name $selItem.Name -AsJob
  }
}
$window.CMRestart.add_Click{
  $selItem = ($window.lv.SelectedItem).Name
  Restart-VM -Name $selItem -Force -AsJob #hardreset
}
$window.CMShutdown.add_Click{
  $selItem = ($window.lv.SelectedItem).Name
  Stop-VM -Name $selItem -AsJob #guest shutdown 
}
$window.CMPowerOff.add_Click{
  $selItem = ($window.lv.SelectedItem).Name
  Stop-VM -Name $selItem -TurnOff -AsJob #power down
}
$window.CMSave.add_Click{
  $selItem = ($window.lv.SelectedItem).Name
  Save-VM -Name $selItem -AsJob #save to disk
}
$window.CMPause.add_Click{
  $selItem = ($window.lv.SelectedItem).Name
  Suspend-VM -Name $selItem -AsJob #save in ram
}
$window.CMDelete.add_Click{
  $selItem = ($window.lv.SelectedItem).Name
  if((Get-VM -Name $selItem).state -ne "Off"){
    Stop-VM -Name $selItem -TurnOff
  }
  Remove-VM -Name $selItem -AsJob -Force
}
$window.CMDeleteDisk.add_Click{
  $selItem = ($window.lv.SelectedItem).Name
  if((Get-VM -Name $selItem).state -ne "Off"){
    Stop-VM -Name $selItem -TurnOff
  }
  if(Get-VMSnapshot -VMName $selItem){
    Remove-VMSnapshot -VMName $selItem
  }
  $VHDs = (Get-VM -Name $selItem).Harddrives.Path
  Remove-VM -Name $selItem -Force
  Remove-Item $VHDs -ErrorAction SilentlyContinue
}
$window.CMSnapshot.add_Click{
  $selItem = ($window.lv.SelectedItem).Name
  Read-Host
  Add-Type -AssemblyName Microsoft.VisualBasic
  $SnapText = [Microsoft.VisualBasic.Interaction]::InputBox('Enter a name for the snapshot', 'Snapshot name', "New Snapshot")
  Checkpoint-VM -Name $selItem -SnapshotName $SnapText -AsJob
}
$window.CMMove.add_Click{
  Get-Popup -mes 'Not implemented yet' -info '(╯°□°）╯︵ ┻━┻'
}
$window.CMExport.add_Click{
  Get-Popup -mes 'Not implemented yet' -info '(╯°□°）╯︵ ┻━┻'
  
}
$window.CMSettings.add_Click{
  $Script:timer.Stop()
  $selItem = ($window.lv.SelectedItem).Name
  Get-VMSettings
  $Script:timer.Start()
}

$window.lv.add_MouseRightButtonDown{
  $window.lv.SelectedItems.Clear()
    $window.CMConnect.IsEnabled = $false
    $window.CMStart.IsEnabled = $false
    $window.CMRestart.IsEnabled = $false
    $window.CMShutdown.IsEnabled = $false
    $window.CMPowerOff.IsEnabled = $false
    $window.CMSave.IsEnabled = $false
    $window.CMPause.IsEnabled = $false
    $window.CMSnapshot.IsEnabled = $false
    $window.CMMove.IsEnabled = $false
    $window.CMExport.IsEnabled = $false
    $window.CMDelete.IsEnabled = $false
    $window.CMDeleteDisk.IsEnabled = $false
    $window.CMSettings.IsEnabled = $false
}
$window.lv.add_MouseRightButtonUp{
  $window.CMConnect.IsEnabled = $true
  $window.CMStart.IsEnabled = $true
  $window.CMRestart.IsEnabled = $true
  $window.CMShutdown.IsEnabled = $true
  $window.CMPowerOff.IsEnabled = $true
  $window.CMSave.IsEnabled = $true
  $window.CMPause.IsEnabled = $true
  $window.CMSnapshot.IsEnabled = $true
  $window.CMMove.IsEnabled = $true
  $window.CMExport.IsEnabled = $true
  $window.CMDelete.IsEnabled = $true
  $window.CMDeleteDisk.IsEnabled = $true
  $window.CMSettings.IsEnabled = $true
  
  $sel = $window.lv.SelectedItem
  if($sel.Name -ne $null){
    if($sel.State -eq 'Off'){
      $window.CMRestart.IsEnabled = $false
      $window.CMShutdown.IsEnabled = $false
      $window.CMPowerOff.IsEnabled = $false
      $window.CMSave.IsEnabled = $false
      $window.CMPause.IsEnabled = $false
    }
    if($sel.State -eq 'Running'){
      $window.CMStart.IsEnabled = $false
    }
    if($sel.State -eq 'Paused'){
      $window.CMPause.IsEnabled = $false
    }
    if($sel.State -eq 'Saved'){
      $window.CMSave.IsEnabled = $false
    }
  }
  else{
    $window.lv.SelectedItems.Clear()
    $window.CMConnect.IsEnabled = $false
    $window.CMStart.IsEnabled = $false
    $window.CMRestart.IsEnabled = $false
    $window.CMShutdown.IsEnabled = $false
    $window.CMPowerOff.IsEnabled = $false
    $window.CMSave.IsEnabled = $false
    $window.CMPause.IsEnabled = $false
    $window.CMSnapshot.IsEnabled = $false
    $window.CMMove.IsEnabled = $false
    $window.CMExport.IsEnabled = $false
    $window.CMDelete.IsEnabled = $false
    $window.CMDeleteDisk.IsEnabled = $false
    $window.CMSettings.IsEnabled = $false
  }
}

$window.lv.add_MouseLeftButtonUp{
  $window.image.Source = $null
  $sel = $window.lv.SelectedItem
  if($sel.State -eq 'Running' -or $sel.State -eq 'Saved'){
    Get-VMScreenshot -HyperVParent localhost -HyperVGuest $sel.Name -xRes 640 -yRes 480
  }
}
$window.lvs.add_MouseLeftButtonUp{
  Get-VMList
}
$window.BAdd.add_Click{
  $Script:timer.Stop()
  Get-AddServer
  $Script:timer.Start()
}


$Window.Add_ContentRendered{    
  #Set-Console -hide
  Set-Overlay -show -message 'connecting to Server ...'
  Get-Preferences
  $lhname = Get-WmiObject -Class Win32_Computersystem | select Name
  $window.lvs.AddChild($lhname)
  Start-Timer
  Set-Overlay -hide
}

$result = Show-WPFWindow -Window $window
$Script:timer.Stop()
$Script:timer = $null
