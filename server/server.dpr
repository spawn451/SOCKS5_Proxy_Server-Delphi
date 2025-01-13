program server;

uses
  Vcl.Forms,
  ufrmMain in 'ufrmMain.pas' {Form1},
  uProxyServer in 'uProxyServer.pas';

{$R *.res}

begin
  {$IFDEF DEBUG}
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.




