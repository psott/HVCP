Import-Module -Name Hyper-V

#region Funktions
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
function Get-VMList
{
  param(
    $vmservers
  )
  $selIndex = $window.lv.SelectedIndex
  $window.lv.Items.Clear()
  
  foreach($vmserver in $vmservers){
    $GetVM = Get-VM -ComputerName $vmservers | ForEach-Object {
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
  $Script:timer.add_tick({Get-VMList -vmservers localhost})
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
        
        <Button Name="BAddServer" Content="add server" HorizontalAlignment="Left" Margin="10,158,0,0" VerticalAlignment="Top" Width="164"/>
        <Button Name="BCancle" Content="cancle" HorizontalAlignment="Left" Margin="211,158,0,0" VerticalAlignment="Top" Width="152"/>
    </Grid>
</Window>
'@
  $winaddserver = Convert-XAMLtoWindow -XAML $xamladdserver -NamedElement 'BAddServer', 'BCancle', 'CBsaveCred', 'CBWinCred', 'TBnewServer', 'TBpass', 'TBuser' -PassThru
  function Get-Popup
  {
    param(
      $info,
      $mes
    )
    $wshell = New-Object -ComObject Wscript.Shell
    $wshell.Popup("$mes",0,"$info",0)
  }
  
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
    <#if($winaddserver.CBWinCred.IsChecked -eq $true -or $winaddserver.CBsaveCred.IsChecked -eq $true){
        Write-Host 'passt'
        #$winaddserver.DialogResult = $true
        }
        else{
        Write-Host 'neeee'
    }#>  
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
    Write-Warning 'User aborted dialog.'
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

#endregion Windows


#region XAML
$xaml = @'
<Window
   xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
   xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
   Width="1150" MinWidth="1000"
   Height ="400" MinHeight ="400"
   SizeToContent="Height"
   Title="Hyper-V Console Plus 0.1"
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
                        <MenuItem Name ="CMRestart" Header="Restart"/>
                        <MenuItem Name ="CMShutdown" Header="Shutdown"/>
                        <MenuItem Name ="CMSave" Header="Save"/>
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
    </Grid>
</Window>
'@


#endregion
$window = Convert-XAMLtoWindow -XAML $xaml -NamedElement 'MOptions','MExit','MAbout','CMSDelete','CMSDisconnect','CMSConnect','CMConnect', 'CMRestart', 'CMSave', 'CMShutdown', 'CMStart', 'image', 'lv','lvs','BAdd', 'MQuick' -PassThru

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

$window.CMStart.add_Click{
  $selItem = ($window.lv.SelectedItem).Name
  Start-VM -Name $selItem
}
$window.CMRestart.add_Click{
  $selItem = ($window.lv.SelectedItem).Name
  Restart-VM -Name $selItem
}
$window.CMShutdown.add_Click{
  $selItem = ($window.lv.SelectedItem).Name
  Stop-VM -Name $selItem
}
$window.CMSave.add_Click{
  $selItem = ($window.lv.SelectedItem).Name
  Save-VM -Name $selItem
}

$window.lv.add_MouseRightButtonDown{
  $window.lv.SelectedItems.Clear()
  $window.CMConnect.IsEnabled = $false
  $window.CMRestart.IsEnabled = $false
  $window.CMShutdown.IsEnabled = $false
  $window.CMStart.IsEnabled = $false
}
$window.lv.add_MouseRightButtonUp{
  if(($window.lv.SelectedItem).Name -ne $null){
    $window.CMConnect.IsEnabled = $true
    $window.CMRestart.IsEnabled = $true
    $window.CMShutdown.IsEnabled = $true
    $window.CMStart.IsEnabled = $true
  }
}

$window.lv.add_MouseLeftButtonUp{
  $window.image.Source = $null
  $sel = $window.lv.SelectedItem
  if($sel.State -eq 'Running' -or $sel.State -eq 'Saved'){
    Get-VMScreenshot -HyperVParent localhost -HyperVGuest $sel.Name -xRes 640 -yRes 480
  }
}

$window.BAdd.add_Click{
  $Script:timer.Stop()
  Get-AddServer
  $Script:timer.Start()
}

$lhname = Get-WmiObject -Class Win32_Computersystem | select Name
$window.lvs.AddChild($lhname)
Get-VMList -vmservers $lhname.Name
Start-Timer

$result = Show-WPFWindow -Window $window
$Script:timer.Stop()
$Script:timer = $null
