unit ufrmMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.StdCtrls,
  Vcl.Samples.Spin, Vcl.ComCtrls, ncSockets, uProxyServer;

type
  TForm1 = class(TForm)
    pnlToolBar: TPanel;
    pnlPort: TPanel;
    btnActivateProxyServer: TButton;
    prxPort: TSpinEdit;
    ListView1: TListView;
    memLog: TMemo;
    procedure btnActivateProxyServerClick(Sender: TObject);
    procedure prxPortChange(Sender: TObject);
    procedure Log(const AMessage: string);
    procedure memLogKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure AddConnection(const ConnectionId: Integer;
      const TargetHost: string; const TargetPort: Word);
    procedure RemoveConnection(const ConnectionId: Integer);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

procedure TForm1.FormCreate(Sender: TObject);
begin
  // Initialize Proxy Server
  TProxyServer.InitializeServer;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  TProxyServer.FinalizeServer;
end;

// *****************************************************************************
// Start/Stop proxy server
// *****************************************************************************

procedure TForm1.btnActivateProxyServerClick(Sender: TObject);
begin
  if Assigned(TProxyServer.TCPProxyServer) and TProxyServer.TCPProxyServer.Active
  then
  begin
    // Stop the Proxy server
    TProxyServer.Stop;

    Log('Proxy Server deactivated');
    btnActivateProxyServer.Caption := 'Start Proxy Server';
  end
  else
  begin
    // Start the Proxy server
    TProxyServer.Start(prxPort.Value);

    Log('Proxy Server activated');
    Log(Format('Proxy Server port: %d', [prxPort.Value]));
    btnActivateProxyServer.Caption := 'Stop Proxy Server';
  end;
end;

// *****************************************************************************
// Change proxy server port
// *****************************************************************************

procedure TForm1.prxPortChange(Sender: TObject);
begin
  try
    if Assigned(TProxyServer.TCPProxyServer) then
      TProxyServer.TCPProxyServer.Port := prxPort.Value;
  except
    Log('Cannot set Port property while the connection is active.');
  end;
end;

// *****************************************************************************
// Add connection to Listview
// *****************************************************************************
procedure TForm1.AddConnection(const ConnectionId: Integer;
  const TargetHost: string; const TargetPort: Word);
var
  Item: TListItem;
begin
  TThread.Queue(nil,
    procedure
    begin
      // Check if item already exists
      for var i := 0 to ListView1.Items.Count - 1 do
        if ListView1.Items[i].Caption = ConnectionId.ToString then
          Exit;

      Item := ListView1.Items.Add;
      Item.Caption := ConnectionId.ToString;
      Item.SubItems.Add(TargetHost);
      Item.SubItems.Add(TargetPort.ToString);
      Item.SubItems.Add('SOCKS5');
    end);
end;

// *****************************************************************************
// Remove connection from Listview
// *****************************************************************************
procedure TForm1.RemoveConnection(const ConnectionId: Integer);
begin
  TThread.Queue(nil,
    procedure
    begin
      for var i := ListView1.Items.Count - 1 downto 0 do
        if ListView1.Items[i].Caption = ConnectionId.ToString then
        begin
          ListView1.Items.Delete(i);
          Break;
        end;
    end);
end;

// *****************************************************************************
// Memo Log
// *****************************************************************************

procedure TForm1.Log(const AMessage: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      try
        memLog.Lines.Add(Format('[%s] %s', [FormatDateTime('hh:nn:ss.zzz', Now),
          AMessage]));
      finally
      end;
    end);
end;

procedure TForm1.memLogKeyDown(Sender: TObject; var Key: Word;
Shift: TShiftState);
begin
  if (Shift = [ssCtrl]) and (Key = Ord('A')) then
    memLog.SelectAll
  else if (Shift = [ssCtrl]) and (Key = Ord('C')) then
    memLog.CopyToClipboard;
end;

end.
