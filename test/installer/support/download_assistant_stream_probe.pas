program DownloadAssistantStreamProbe;
{$mode objfpc}{$H+}
uses Classes, SysUtils;

type
  TProbeFileStream = class(TFileStream)
    Counted: Boolean;
    constructor Create(const AFileName: String; Mode: Word);
    destructor Destroy; override;
    function CopyFrom(Source: TStream; Count: Int64; BufferSize: LongInt): Int64; reintroduce;
  end;
  TWorkPage = class
    procedure SetText(A, B: String);
    procedure SetProgress(A, B: Integer);
  end;

const AppendSliceSize = 1048576; CopyChunkSize = 262144;
var
  WorkPage: TWorkPage;
  CopyMsMeasured, CopyBytesMeasured, JoinCopyLeft: Int64;
  LoadErrorTech, Root, LastDetail: String;
  EtaCalls, ProgressCalls, CopyCalls, DeleteCalls, LinkCalls: Integer;
  LastProgress, LastTotal, MiddleProgress: Integer;
  FailWrite, LinkSucceeds, EnforceWindowsSharing: Boolean;
  GuardedSource: TProbeFileStream;
  GuardedPath: String;
  LiveStreams: Integer;

{ FPC on Unix ignores fmShareDenyWrite; model Windows sharing at the open boundary. }
constructor TProbeFileStream.Create(const AFileName: String; Mode: Word);
begin
  if EnforceWindowsSharing and (Mode = fmCreate) and
    Assigned(GuardedSource) and (AFileName = GuardedPath) then
    raise EFCreateError.Create('source is already open with deny-write sharing');
  inherited Create(AFileName, Mode);
  Counted := True; Inc(LiveStreams);
  if Mode = (fmOpenRead or fmShareDenyWrite) then
  begin GuardedSource := Self; GuardedPath := AFileName; end;
end;
destructor TProbeFileStream.Destroy;
begin
  if GuardedSource = Self then GuardedSource := nil;
  if Counted then Dec(LiveStreams);
  inherited Destroy;
end;

function TProbeFileStream.CopyFrom(Source: TStream; Count: Int64; BufferSize: LongInt): Int64;
begin
  Inc(CopyCalls);
  if FailWrite and (CopyCalls = 2) then
    raise EWriteError.Create('injected disk write failure');
  Result := inherited CopyFrom(Source, Count);
end;
procedure TWorkPage.SetText(A, B: String);
begin LastDetail := B; end;
procedure TWorkPage.SetProgress(A, B: Integer);
begin
  Inc(ProgressCalls);
  if (A > 0) and (A < B) then MiddleProgress := A;
  LastProgress := A; LastTotal := B;
end;
function NowMs(): Int64;
begin Result := GetTickCount64(); end;
function CustomMessage(S: String): String;
begin Result := S; end;
function HumanSize(N: Int64): String;
begin Result := IntToStr(N); end;
function FmtMessage(S: String; A: array of String): String;
begin Result := A[0] + '/' + A[1]; end;
function PostEtaText(): String;
begin Inc(EtaCalls); Result := 'assembly ETA'; end;
function MegaBytes(N: Int64): Integer;
begin Result := N div 1048576; end;
function GetExceptionMessage(): String;
begin Result := Exception(ExceptObject).Message; end;
function CacheDir(): String;
begin Result := Root + '/cache'; end;
function CachePath(Name: String): String;
begin Result := CacheDir() + '/' + Name; end;
function Msg1(A, B: String): String;
begin Result := A + B; end;
procedure Log(S: String);
begin end;
function DeleteFile(Name: String): Boolean;
begin Inc(DeleteCalls); Result := False; end;
function CreateHardLink(Dest, Src: String; Reserved: Integer): Boolean;
begin Inc(LinkCalls); Result := LinkSucceeds; end;

{EXTRACTED_ROUTINES}

procedure Check(Condition: Boolean; Message: String);
begin
  if not Condition then begin Writeln(Message); Halt(1); end;
end;
procedure Put(Name, Bytes: String);
var F: TFileStream;
begin
  F := TFileStream.Create(Name, fmCreate);
  try F.WriteBuffer(Bytes[1], Length(Bytes)); finally F.Free; end;
end;
function Read(Name: String): String;
var F: TFileStream;
begin
  F := TFileStream.Create(Name, fmOpenRead);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then F.ReadBuffer(Result[1], F.Size);
  finally F.Free; end;
end;
var Scenario, Dest, Src, Payload: String; Ok: Boolean;
begin
  Scenario := ParamStr(1); Root := ParamStr(2);
  ForceDirectories(CacheDir()); ForceDirectories(Root + '/out');
  WorkPage := TWorkPage.Create;
  Src := CachePath('file');
  { CopyToOutput uses Windows separators; Unix treats the backslash as part of the name. }
  Dest := Root + '/out\file';
  Payload := 'new content'; Put(Src, Payload); Put(Dest, 'old data that must go');
  JoinCopyLeft := 12345678;
  if Scenario = 'append' then
  begin
    Put(Dest, 'prefix');
    JoinCopyLeft := 2 * Length(Payload);
    Ok := WriteFileTo(Dest, Src, fmOpenWrite, Length(Payload), 6, 28, 'join');
    Check(Ok and (Read(Dest) = 'prefix' + Payload), 'append lost prefix');
    Check(JoinCopyLeft = Length(Payload), 'append did not consume assembly budget');
    Ok := WriteFileTo(Dest, Src, fmOpenWrite, Length(Payload), 17, 28, 'join');
    Check(Ok and (Read(Dest) = 'prefix' + Payload + Payload), 'second append failed');
    Check((JoinCopyLeft = 0) and (EtaCalls = 2), 'assembly ETA/budget incorrect');
  end
  else if (Scenario = 'short-input') or (Scenario = 'write-failure') then
  begin
    if Scenario = 'write-failure' then
    begin
      Payload := StringOfChar('x', 3 * AppendSliceSize); Put(Src, Payload); FailWrite := True;
    end;
    Ok := WriteFileTo(Dest, Src, fmCreate, Length(Payload) + 1, 0, Length(Payload) + 1, 'copy');
    Check(not Ok, 'incomplete transfer reported success');
    Check(LoadErrorTech <> '', 'failure has no diagnostic');
    Check(Read(Src) = Payload, 'failure modified cache source');
    Check(JoinCopyLeft = 12345678, 'failed copy consumed assembly budget');
  end
  else if Scenario = 'shared-source' then
  begin
    EnforceWindowsSharing := True;
    Ok := WriteFileTo(Src, Src, fmCreate, Length(Payload), 0, Length(Payload), 'copy');
    Check(not Ok, 'source alias was opened for overwrite');
    Check(Read(Src) = Payload, 'source alias was truncated');
  end
  else if Scenario = 'source-open-failure' then
  begin
    Ok := WriteFileTo(Dest, Root + '/missing/source', fmCreate, 11, 0, 11, 'copy');
    Check(not Ok and (LoadErrorTech <> ''), 'missing source reported success');
    Check(Read(Dest) = 'old data that must go', 'missing source destroyed existing destination');
  end
  else if Scenario = 'unwritable' then
  begin
    Ok := WriteFileTo(Root + '/missing/target', Src, fmCreate, Length(Payload), 0, 20, 'copy');
    Check(not Ok and (LoadErrorTech <> ''), 'unwritable target reported success');
    Check(Read(Src) = Payload, 'open failure modified source');
  end
  else
  begin
    if Scenario = 'progress' then
    begin Payload := StringOfChar('x', 3 * AppendSliceSize); Put(Src, Payload); end;
    LinkSucceeds := Scenario = 'hardlink';
    if Scenario = 'cache' then
      Ok := CopyToOutput('file', CacheDir(), 'copy', Length(Payload), 0, Length(Payload))
    else
      Ok := CopyToOutput('file', Root + '/out', 'copy', Length(Payload), 0, Length(Payload));
    Check(Ok, 'copy failed: ' + LoadErrorTech);
    Check(Read(Src) = Payload, 'copy modified cache source');
    Check(JoinCopyLeft = 12345678, 'copy consumed pending assembly budget');
    Check(EtaCalls = 0, 'copy displayed unrelated assembly ETA');
    if (Scenario = 'cache') or (Scenario = 'hardlink') then
    begin
      Check(CopyCalls = 0, 'fast path copied bytes');
      if Scenario = 'cache' then Check(DeleteCalls = 0, 'cache fast path tried deleting source');
    end
    else
    begin
      Check((DeleteCalls = 1) and (LinkCalls = 1), 'fallback boundaries not exercised');
      Check(Read(Dest) = Payload, 'existing destination was appended instead of replaced');
      if Scenario = 'copy-before-join' then
      begin
        Put(Dest, 'prefix');
        Ok := WriteFileTo(Dest, Src, fmOpenWrite, Length(Payload), 6, 28, 'join');
        Check(Ok and (Read(Dest) = 'prefix' + Payload), 'assembly after copy failed');
        Check(JoinCopyLeft = 12345678 - Length(Payload), 'assembly budget after copy drifted');
      end;
      if Scenario = 'progress' then
        Check((ProgressCalls = 4) and (MiddleProgress > 0) and
          (LastProgress = LastTotal) and (LastDetail = '3145728/3145728'), 'byte progress missing');
    end;
  end;
  Check(LiveStreams = 0, 'stream leaked after success or failure');
  WorkPage.Free;
  Writeln('PASS ', Scenario);
end.
