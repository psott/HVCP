Import-Module -Name Hyper-V
$xaml = @'
<Window
   xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
   xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
   Width="1000" MinWidth="1000"
   Height ="400" MinHeight ="400"
   SizeToContent="Height"
   Title="Hyper-V"
   Topmost="True" Background="#FFCBCBCB">
    <Grid>
        <ListView Name="lv" HorizontalAlignment="Stretch" Margin="10,10,10,200" VerticalAlignment="Stretch">
            <ListView.ContextMenu>
              <ContextMenu>
                <MenuItem Name ="CMConnect" Header="Connect"/>
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
    </Grid>
</Window>

'@
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
$window = Convert-XAMLtoWindow -XAML $xaml -NamedElement 'CMConnect', 'CMRestart', 'CMShutdown', 'CMStart','CMSave', 'lv' -PassThru

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
function Get-VMList
{
  $selIndex = $window.lv.SelectedIndex
  $window.lv.Items.Clear()
  
  $GetVM = Get-VM | ForEach-Object {
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

Get-VMList
Start-Timer

$result = Show-WPFWindow -Window $window
$Script:timer.Stop()
$Script:timer = $null
