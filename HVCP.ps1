Add-Type -AssemblyName PresentationFramework
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
function Get-MyPrinter
{
  Get-Printer | select Name | ForEach-Object {$window.lv2.addchild($_)}
}
function Set-WindowPosition
{
  $window.Left = $([System.Windows.SystemParameters]::WorkArea.Width-$window.Width)
  $window.Top = $([System.Windows.SystemParameters]::WorkArea.Height-$window.Height)
}
function Convert-XAMLtoWindow
{
  param
  (
    [Parameter(Mandatory)]
    [string]
    $XAML,
    [switch]
    $PassThru
  )
  $reader = [XML.XMLReader]::Create([IO.StringReader]$XAML)
  $result = [Windows.Markup.XAMLReader]::Load($reader)
  
  [xml]$XmlXaml = $xaml
  $NamedElement = $XmlXaml.SelectNodes("//*[@Name]")
  foreach($Name in $NamedElement){
    $result | Add-Member NoteProperty -Name $Name.Name -Value $result.FindName($Name.Name) -Force
  }
  if ($PassThru){
    $result
  }
  else{
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
$xaml = @'
<Window
   xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
   xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
   Height="400" Width ="600"
   Title="Printer" Topmost="True">
    <Grid>
        <TabControl Name="tabControl" HorizontalAlignment="Stretch" VerticalAlignment="Stretch">
            <TabItem Header="Verfügbare Drucker">
                <Grid Background="#FFE5E5E5">
                    <TextBox Name="textBox" HorizontalAlignment="Left" Height="23" Margin="10,10,0,0" TextWrapping="Wrap" Text="TextBox" VerticalAlignment="Top" Width="194"/>
                    <ListView Name="lv1" HorizontalAlignment="Stretch" Margin="10,40,10,40" VerticalAlignment="Stretch">
                        <ListView.ContextMenu>
                            <ContextMenu>
                                <MenuItem Name ="Verbinden" Header="Verbinden"/>
                                <MenuItem Name ="Eigenschaften" Header="Eigenschaften"/>
                            </ContextMenu>
                        </ListView.ContextMenu>
                        <ListView.View>
                            <GridView>
                                <GridViewColumn Header="Name" DisplayMemberBinding ="{Binding 'Name'}" Width="120"/>
                                <GridViewColumn Header="Beschreibung" DisplayMemberBinding ="{Binding 'Beschreibung'}" Width="120"/>
                            </GridView>
                        </ListView.View>
                    </ListView>
                    <Button Name="button" Content="Button" HorizontalAlignment="Right" Margin="0,0,10,10" VerticalAlignment="Bottom" Width="75"/>
                </Grid>
            </TabItem>
            <TabItem Header="Meine Drucker">
                <Grid Background="#FFE5E5E5">
                    <ListView Name="lv2" HorizontalAlignment="Stretch" Margin="10,10,10,40" VerticalAlignment="Stretch">
                        <ListView.ContextMenu>
                            <ContextMenu>
                                <MenuItem Name ="MyTrennen" Header="Trennen"/>
                                <MenuItem Name ="MyEigenschaften" Header="Eigenschaften"/>
                            </ContextMenu>
                        </ListView.ContextMenu>
                        <ListView.View>
                            <GridView>
                                <GridViewColumn Header="Name" DisplayMemberBinding ="{Binding 'Name'}" Width="120"/>
                                <GridViewColumn Header="Beschreibung" DisplayMemberBinding ="{Binding 'Beschreibung'}" Width="120"/>
                            </GridView>
                        </ListView.View>
                    </ListView>
                    <Button Name="button2" Content="Button" HorizontalAlignment="Right" Margin="0,0,10,10" VerticalAlignment="Bottom" Width="75"/>
                </Grid>
            </TabItem>
        </TabControl>
    </Grid>
</Window>
'@

$window = Convert-XAMLtoWindow -XAML $xaml -PassThru

$Window.Add_ContentRendered({  
    Set-WindowPosition
    Get-MyPrinter
})


Set-Console -hide
$result = Show-WPFWindow -Window $window
if($Host.Name -notlike '*ISE*'){
  Stop-Process -Id $PID
}
