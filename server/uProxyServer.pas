{*****************************************************************************}
{*                              uProxyServer.pas                             *}
{*****************************************************************************}

{*===========================================================================*}
{* DESCRIPTION                                                               *}
{*****************************************************************************}
{* PROJECT    : SOCKS5_Proxy_Server-Delphi                                   *}
{* AUTHOR     : J.Pauwels                                                    *}
{*...........................................................................*}
{* DESCRIPTION                                                               *}
{*  SOCKS 5 Server using Netcom7 socket                                      *}
{*                                                                           *}
{* QUICK NOTES:                                                              *}
{* This SOCKS5 proxy server implementation follows the SOCKS5 protocol       *}
{* specification (RFC 1928).                                                 *}
{*                                                                           *}
{* - Only supports CONNECT command (no BIND or UDP)                          *}
{* - Only implements NO_AUTH authentication method                           *}
{* - Limited to IPv4 for bound addresses                                     *}
{*...........................................................................*}
{* HISTORY                                                                   *}
{*     DATE    VERSION  AUTHOR      COMMENT                                  *}
{*                                                                           *}
{* 13/01/2025    1.0   J.Pauwels   Initial start                             *}
{*****************************************************************************}

unit uProxyServer;

interface

uses
  System.Classes, System.SysUtils, System.Math, System.TypInfo,
  System.IOUtils, System.SyncObjs, System.DateUtils, System.Diagnostics,
  System.Generics.Collections, System.Threading, Winapi.Winsock2,
  Winapi.Windows,
  ncLines, ncSocketList, ncSockets;

const
  // Server ports
  DEFAULT_PROXY_PORT = 1080;
  // SOCKS5 Protocol Constants
  SOCKS5_VERSION_NUMBER = $05;
  SOCKS5_RESERVED = $00;
  // Authentication methods
  SOCKS5_AUTH_METHOD_NO_AUTH = $00;
  SOCKS5_AUTH_METHOD_REPLY_NO_ACCEPTABLE_METHODS = $FF;
  // Commands
  SOCKS5_CMD_CONNECT = $01;
  // Address types
  SOCKS5_ADDRTYPE_IPV4 = $01;
  SOCKS5_ADDRTYPE_DOMAIN = $03;
  // Reply Codes
  SOCKS5_CMD_REPLY_SUCCEEDED = $00;
  SOCKS5_CMD_REPLY_GENERAL_SOCKS_SERVER_FAILURE = $01;
  SOCKS5_CMD_REPLY_HOST_UNREACHABLE = $04;
  SOCKS5_CMD_REPLY_COMMAND_NOT_SUPPORTED = $07;
  SOCKS5_CMD_REPLY_ADDRESS_TYPE_NOT_SUPPORTED = $08;

type
  TProxyState = (psNone, psAuthMethod, psAuth, psCommand, psConnecting,
    psForwarding);

  TClientContext = class
  private
    FConnectionId: Integer;
  public
    State: TProxyState;
    TargetClient: TncTCPClient;
    SourceLine: TncLine;
    IsDisconnected: Boolean;
    TargetHost: string;
    TargetPort: Word;
    constructor Create(ALine: TncLine);
    destructor Destroy; override;
    property ConnectionId: Integer read FConnectionId;
  end;

  TProxyServer = class
  public
    class var TCPProxyServer: TncTCPServer;
    class var ClientContexts: TDictionary<TncLine, TClientContext>;
    class var ContextLock: TCriticalSection;
    class var ActiveContextsCount: Integer;

    class procedure InitializeServer;
    class procedure FinalizeServer;
    class procedure Start(Port: Integer);
    class procedure Stop;
    class procedure ClientConnected(Sender: TObject; ALine: TncLine);
    class procedure ClientDisconnected(Sender: TObject; ALine: TncLine);
    class procedure ClientReadData(Sender: TObject; ALine: TncLine;
      const aBuf: TBytes; aBufCount: Integer);
  private
    class function GetClientContext(ALine: TncLine): TClientContext;
    class procedure ShutdownClient(ALine: TncLine;
      const ALogReason: string = '');
    class procedure HandleInitialGreeting(ALine: TncLine; const aBuf: TBytes;
      aBufCount: Integer);
    class procedure SendMethodSelection(ALine: TncLine; Method: Byte);
    class procedure HandleCommand(ALine: TncLine; const aBuf: TBytes;
      aBufCount: Integer);
    class procedure SendCommandResponse(ALine: TncLine; Reply: Byte;
      AddrType: Byte = SOCKS5_ADDRTYPE_IPV4; BoundAddr: string = '0.0.0.0';
      BoundPort: Word = 0);
    class procedure HandleConnect(ALine: TncLine; const aBuf: TBytes;
      aBufCount: Integer);
    class procedure ForwardData(Sender: TObject; ALine: TncLine;
      const aBuf: TBytes; aBufCount: Integer);
    class procedure TargetConnected(Sender: TObject; ALine: TncLine);
    class procedure TargetReadData(Sender: TObject; ALine: TncLine;
      const aBuf: TBytes; aBufCount: Integer);
  end;

implementation

uses
  ufrmMain;

{ TClientContext }

constructor TClientContext.Create(ALine: TncLine);
begin
  inherited Create;
  State := psNone;
  TargetClient := nil;
  SourceLine := ALine;
  IsDisconnected := False;
  TargetHost := '';
  TargetPort := 0;
  FConnectionId := ALine.Handle;
end;

destructor TClientContext.Destroy;
begin
  FreeAndNil(TargetClient);
  inherited;
end;

{ TProxyServer }

class procedure TProxyServer.InitializeServer;
begin
  ActiveContextsCount := 0;
  ContextLock := TCriticalSection.Create;
  ClientContexts := TDictionary<TncLine, TClientContext>.Create;

  TCPProxyServer := TncTCPServer.Create(nil);
  TCPProxyServer.OnConnected := ClientConnected;
  TCPProxyServer.OnDisconnected := ClientDisconnected;
  TCPProxyServer.OnReadData := ClientReadData;
  TCPProxyServer.NoDelay := True;
  TCPProxyServer.KeepAlive := True;
  TCPProxyServer.Active := False;
  TCPProxyServer.EventsUseMainThread := False;
end;

class procedure TProxyServer.FinalizeServer;
begin
  if Assigned(TCPProxyServer) then
  begin
    FreeAndNil(TCPProxyServer);
    FreeAndNil(ClientContexts);
    FreeAndNil(ContextLock);
    ActiveContextsCount := 0;
  end;
end;

class procedure TProxyServer.Start(Port: Integer);
begin
  if not Assigned(TCPProxyServer) then
    InitializeServer;
  TCPProxyServer.Port := Port;
  TCPProxyServer.Active := True;
end;

class procedure TProxyServer.Stop;
begin
  TCPProxyServer.Active := False;
end;

class function TProxyServer.GetClientContext(ALine: TncLine): TClientContext;
begin
  Result := nil;
  ContextLock.Enter;
  try
    if not ClientContexts.TryGetValue(ALine, Result) then
    begin
      Result := TClientContext.Create(ALine);
      ClientContexts.Add(ALine, Result);
      Inc(ActiveContextsCount); //
    end;
  finally
    ContextLock.Leave;
  end;
end;

class procedure TProxyServer.ClientConnected(Sender: TObject; ALine: TncLine);
var
  Context: TClientContext;
begin
  Context := GetClientContext(ALine);

  // Update connection state
  Context.State := psAuthMethod;
end;

class procedure TProxyServer.ClientDisconnected(Sender: TObject;
  ALine: TncLine);
var
  Context: TClientContext;
  ConnectionId: Integer;
begin
  if not Assigned(ALine) then
    Exit;

  ConnectionId := ALine.Handle;

  // Only mark as disconnected if not already handled
  ContextLock.Enter;
  try
    if not ClientContexts.TryGetValue(ALine, Context) or Context.IsDisconnected
    then
      Exit;

    Context.IsDisconnected := True;
    Context.State := psNone;

    // Remove from ListView
    Form1.RemoveConnection(ConnectionId);

    // Remove context
    ClientContexts.Remove(ALine);

    // Free context
    Context.Free;

  finally
    ContextLock.Leave;
  end;

end;

class procedure TProxyServer.ShutdownClient(ALine: TncLine;
  const ALogReason: string = '');
var
  Context: TClientContext;
  ConnectionId: Integer;
begin
  if not Assigned(ALine) then
    Exit;

  ConnectionId := ALine.Handle;

  // Only mark as disconnected if not already handled
  ContextLock.Enter;
  try
    if not ClientContexts.TryGetValue(ALine, Context) or Context.IsDisconnected
    then
      Exit;

    Context.IsDisconnected := True;
    Context.State := psNone;

    TCPProxyServer.ShutDownLine(ALine);

    // Remove from ListView
    Form1.RemoveConnection(ConnectionId);

    // Remove context
    ClientContexts.Remove(ALine);

    // Free context
    Context.Free;

    Form1.Log(Format('[ShutdownClient] Context cleaned for #%d | %s:%d - %s',
      [ConnectionId, Context.TargetHost, Context.TargetPort, ALogReason]));

  finally
    ContextLock.Leave;
  end;

end;

class procedure TProxyServer.ClientReadData(Sender: TObject; ALine: TncLine;
  const aBuf: TBytes; aBufCount: Integer);
var
  Context: TClientContext;
  LocalState: TProxyState;
begin
  ContextLock.Enter;
  try
    if not ClientContexts.TryGetValue(ALine, Context) then
      Exit;
    if Context.IsDisconnected then
      Exit;
    LocalState := Context.State;
  finally
    ContextLock.Leave;
  end;

  case LocalState of
    psAuthMethod:
      HandleInitialGreeting(ALine, aBuf, aBufCount);
    psCommand:
      HandleCommand(ALine, aBuf, aBufCount);
    psForwarding:
      ForwardData(Sender, ALine, aBuf, aBufCount);
  end;
end;

class procedure TProxyServer.SendMethodSelection(ALine: TncLine; Method: Byte);
var
  Response: TBytes;
begin
  SetLength(Response, 2);
  Response[0] := SOCKS5_VERSION_NUMBER;
  Response[1] := Method;
  TCPProxyServer.Send(ALine, Response[0], Length(Response));
end;

class procedure TProxyServer.HandleInitialGreeting(ALine: TncLine;
  const aBuf: TBytes; aBufCount: Integer);
var
  Ver, NMethods: Byte;
  Methods: TBytes;
  Context: TClientContext;
  I: Integer;
  HasNoAuth: Boolean;
begin

  // First check: Must have at least 2 bytes (VER and NMETHODS)
  if aBufCount < 2 then
  begin
    Form1.Log(Format
      ('[HandleInitialGreeting] Buffer too short for client #%d: %d bytes',
      [ALine.Handle, aBufCount]));
    ShutdownClient(ALine, 'Greeting too short');
    Exit;
  end;

  // Second check: Version must be 5
  Ver := aBuf[0];
  if Ver <> SOCKS5_VERSION_NUMBER then
  begin
    SendMethodSelection(ALine, SOCKS5_AUTH_METHOD_REPLY_NO_ACCEPTABLE_METHODS);
    ShutdownClient(ALine, Format('Unsupported SOCKS version: %d', [Ver]));
    Exit;
  end;

  // Third check: Must have all method bytes
  NMethods := aBuf[1];
  if aBufCount < (2 + NMethods) then
  begin
    Form1.Log(Format
      ('[HandleInitialGreeting] Methods incomplete for client #%d',
      [ALine.Handle]));
    ShutdownClient(ALine, 'Incomplete methods');
    Exit;
  end;

  // Get the context AFTER version validation
  Context := GetClientContext(ALine);
  if not Assigned(Context) then
  begin
    Form1.Log(Format
      ('[HandleInitialGreeting] Failed to get context for client #%d',
      [ALine.Handle]));
    ShutdownClient(ALine, 'Context creation failed');
    Exit;
  end;

  // Now we know we have a valid SOCKS5 greeting, process the methods
  SetLength(Methods, NMethods);
  Move(aBuf[2], Methods[0], NMethods);

  HasNoAuth := False;
  for I := 0 to NMethods - 1 do
  begin
    if Methods[I] = SOCKS5_AUTH_METHOD_NO_AUTH then
    begin
      HasNoAuth := True;
      Break;
    end;
  end;

  if HasNoAuth then
  begin

    SendMethodSelection(ALine, SOCKS5_AUTH_METHOD_NO_AUTH);

    // Update connection state
    Context.State := psCommand;

  end
  else
  begin
    SendMethodSelection(ALine, SOCKS5_AUTH_METHOD_REPLY_NO_ACCEPTABLE_METHODS);
    ShutdownClient(ALine, 'No acceptable authentication methods');
  end;
end;

class procedure TProxyServer.HandleCommand(ALine: TncLine; const aBuf: TBytes;
  aBufCount: Integer);
var
  Ver, Cmd: Byte;
begin
  if aBufCount < 4 then
  begin
    SendCommandResponse(ALine, SOCKS5_CMD_REPLY_GENERAL_SOCKS_SERVER_FAILURE);
    ShutdownClient(ALine,
      Format('Command too short: expected at least 4 bytes, got %d',
      [aBufCount]));
    Exit;
  end;

  Cmd := aBuf[1];
  case Cmd of
    SOCKS5_CMD_CONNECT:
      HandleConnect(ALine, aBuf, aBufCount);
  else
    begin
      SendCommandResponse(ALine, SOCKS5_CMD_REPLY_COMMAND_NOT_SUPPORTED);
      ShutdownClient(ALine, 'Command not supported: ' + IntToStr(Cmd));
    end;
  end;
end;

class procedure TProxyServer.SendCommandResponse(ALine: TncLine; Reply: Byte;
  AddrType: Byte; BoundAddr: string; BoundPort: Word);
var
  Response: TBytes;
  I: Integer;
  AddrBytes: TBytes;
begin
  case AddrType of
    SOCKS5_ADDRTYPE_IPV4:
      begin
        SetLength(Response, 10);
        AddrBytes := TBytes.Create(0, 0, 0, 0);
        if BoundAddr <> '0.0.0.0' then
        begin
          var
          Parts := BoundAddr.Split(['.']);
          if Length(Parts) = 4 then
            for I := 0 to 3 do
              AddrBytes[I] := StrToIntDef(Parts[I], 0);
        end;
      end;
  else
    SetLength(Response, 10);
    AddrBytes := TBytes.Create(0, 0, 0, 0);
  end;

  Response[0] := SOCKS5_VERSION_NUMBER;
  Response[1] := Reply;
  Response[2] := SOCKS5_RESERVED;
  Response[3] := AddrType;
  Move(AddrBytes[0], Response[4], 4);
  Response[8] := BoundPort shr 8;
  Response[9] := BoundPort and $FF;

  TCPProxyServer.Send(ALine, Response[0], Length(Response));
end;

class procedure TProxyServer.HandleConnect(ALine: TncLine; const aBuf: TBytes;
  aBufCount: Integer);
var
  AddrType: Byte;
  Context: TClientContext;
  I, DomainLen: Integer;
begin

  if aBufCount < 7 then
  begin
    SendCommandResponse(ALine, SOCKS5_CMD_REPLY_GENERAL_SOCKS_SERVER_FAILURE);
    ShutdownClient(ALine,
      Format('Connect request too short: expected at least 7 bytes, got %d',
      [aBufCount]));
    Exit;
  end;

  Context := GetClientContext(ALine);

  AddrType := aBuf[3];
  I := 4;

  try
    case AddrType of
      SOCKS5_ADDRTYPE_IPV4:
        begin
          if aBufCount < 10 then
          begin
            SendCommandResponse(ALine,
              SOCKS5_CMD_REPLY_GENERAL_SOCKS_SERVER_FAILURE);
            ShutdownClient(ALine, 'IPv4 address incomplete');
            Exit;
          end;
          Context.TargetHost := Format('%d.%d.%d.%d',
            [aBuf[4], aBuf[5], aBuf[6], aBuf[7]]);
          I := 8;
        end;

      SOCKS5_ADDRTYPE_DOMAIN:
        begin
          DomainLen := aBuf[4];
          if aBufCount < (5 + DomainLen + 2) then
          begin
            SendCommandResponse(ALine,
              SOCKS5_CMD_REPLY_GENERAL_SOCKS_SERVER_FAILURE);
            ShutdownClient(ALine, 'Domain name incomplete');
            Exit;
          end;
          SetString(Context.TargetHost, PAnsiChar(@aBuf[5]), DomainLen);
          I := 5 + DomainLen;
        end;
    else
      SendCommandResponse(ALine, SOCKS5_CMD_REPLY_ADDRESS_TYPE_NOT_SUPPORTED);
      ShutdownClient(ALine, Format('Address type not supported: %d',
        [AddrType]));
      Exit;
    end;

    Context.TargetPort := (aBuf[I] shl 8) or aBuf[I + 1];

    TncTCPBase.DefaultReadBufferLen := 8192;

    Context.TargetClient := TncTCPClient.Create(nil);

    with Context.TargetClient do
    begin
      OnConnected := TargetConnected;
      OnDisconnected := nil;
      OnReadData := TargetReadData;
      Tag := NativeInt(ALine);
      Line.ConnectTimeout := 5000;
      UseReaderThread := True;
      Reconnect := False;
      NoDelay := True;
      KeepAlive := False;
      EventsUseMainThread := False;
      Host := Context.TargetHost;
      Port := Context.TargetPort;
    end;

    // Update connection state
    Context.State := psConnecting;

    Context.TargetClient.Active := True;

  except
    on E: Exception do
    begin
      SendCommandResponse(ALine, SOCKS5_CMD_REPLY_HOST_UNREACHABLE);
      ShutdownClient(ALine,
        Format('[HandleConnect]Connect error for %s:%d  : %s',
        [Context.TargetHost, Context.TargetPort,E.Message]));
    end;
  end;
end;

class procedure TProxyServer.ForwardData(Sender: TObject; ALine: TncLine;
  const aBuf: TBytes; aBufCount: Integer);
var
  Context: TClientContext;
  LocalTarget: TncTCPClient;
begin
  // Keep the lock during the entire operation to prevent race conditions
  ContextLock.Enter;
  try
    // Validate we have a context for this connection
    if not ClientContexts.TryGetValue(ALine, Context) then
      Exit;

    // Check if client already disconnected
    if Context.IsDisconnected then
      Exit;

    // Get target client and validate it's still valid and active
    LocalTarget := Context.TargetClient;
    if not Assigned(LocalTarget) or not LocalTarget.Active then
    begin
      ShutdownClient(ALine, '[ForwardData] Target not available');
      Exit;
    end;

    // Forward the data to target while still holding the lock
    try
      LocalTarget.Send(aBuf[0], aBufCount);
    except
      on E: Exception do
      begin
        ShutdownClient(ALine, Format('[ForwardData] Send failed: %s',
          [E.Message]));
      end;
    end;

  finally
    ContextLock.Leave;
  end;
end;

class procedure TProxyServer.TargetConnected(Sender: TObject; ALine: TncLine);
var
  Context: TClientContext;
  SourceLine: TncLine;
begin
  if not Assigned(Sender) or not(Sender is TncTCPClient) then
    Exit;

  // Get the source line from the target client's Tag
  SourceLine := TncLine(TncTCPClient(Sender).Tag);
  if not Assigned(SourceLine) then
    Exit;

  // Get the client context
  ContextLock.Enter;
  try
    if not ClientContexts.TryGetValue(SourceLine, Context) then
      Exit;

    // Add to ListView
    Form1.AddConnection(Context.ConnectionId, Context.TargetHost,
      Context.TargetPort);

    // Update connection state
    Context.State := psForwarding;

    // Send successful connection response back to the client
    SendCommandResponse(SourceLine, SOCKS5_CMD_REPLY_SUCCEEDED,
      SOCKS5_ADDRTYPE_IPV4, Context.TargetHost, Context.TargetPort);

  finally
    ContextLock.Leave;
  end;
end;

class procedure TProxyServer.TargetReadData(Sender: TObject; ALine: TncLine;
  const aBuf: TBytes; aBufCount: Integer);
var
  SourceLine: TncLine;
  Context: TClientContext;
begin
  // Get the source line from the target client's Tag
  if not Assigned(Sender) or not(Sender is TncTCPClient) then
    Exit;

  // When a TargetClient receives data, we need to get back to the original source line
  // that was stored in the Tag when we created the TargetClient
  SourceLine := TncLine(TncTCPClient(Sender).Tag);
  if not Assigned(SourceLine) then
    Exit;

  // Try to find the context directly by iterating through contexts to match TargetClient
  ContextLock.Enter;
  try
    Context := nil;
    for var Ctx in ClientContexts.Values do
    begin
      if Assigned(Ctx.TargetClient) and (Ctx.TargetClient = Sender) then
      begin
        Context := Ctx;
        Break;
      end;
    end;

    if not Assigned(Context) or Context.IsDisconnected then
      Exit;

    try
      // Forward received data back to the original client through the proxy server
      TCPProxyServer.Send(Context.SourceLine, aBuf[0], aBufCount);

    except
      on E: Exception do
      begin
        ShutdownClient(Context.SourceLine,
          Format('[TargetReadData] Send failed: %s', [E.Message]));
      end;
    end;
  finally
    ContextLock.Leave;
  end;
end;

end.
