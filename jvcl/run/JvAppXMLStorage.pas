{-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: JvAppXMLStorage.pas, released on 2003-12-06.

The Initial Developer of the Original Code is Olivier Sannier
Portions created by Olivier Sannier are Copyright (C) 2003 Olivier Sannier
All Rights Reserved.

Contributor(s):
  Marcel Bestebroer

Last Modified: 2004-01-18

You may retrieve the latest version of this file at the Project JEDI's JVCL home page,
located at http://jvcl.sourceforge.net

Known Issues:
-----------------------------------------------------------------------------}

{$I jvcl.inc}

unit JvAppXMLStorage;

interface

uses
  {$IFDEF MSWINDOWS}
  Windows,
  {$ENDIF MSWINDOWS}
  {$IFDEF LINUX}
  Libc,
  {$ENDIF LINUX}
  SysUtils, Classes, IniFiles,
  JvAppStorage, JvSimpleXml;

type
  // This is the base class for an in memory XML file storage
  // There is at the moment only one derived class that simply
  // allows to flush into a disk file.
  // But there may be a new descendent that stores into a
  // database field, if anyone is willing to write such
  // a class (nothing much is involved, use the AsString property).
  TJvCustomAppXMLStorage = class(TJvCustomAppMemoryFileStorage)
  protected
    FXml: TJvSimpleXml;
    FCurrentNode: TJvSimpleXmlElem;
    function GetAsString: string; override;
    procedure SetAsString(const Value: string); override;

    function GetRootNodeName: string;
    procedure SetRootNodeName(const Value: string);
    // Returns the last node in path, if it exists.
    // Returns nil in all other cases
    // If StartNode is nil, then FCurrentNode is used as a
    // starting point for Path
    function GetNodeFromPath(Path: string; StartNode: TJvSimpleXmlElem = nil): TJvSimpleXmlElem;
    // Reads the \ separated Key string and sets FCurrentNode to
    // the last one, having created all the required XML nodes
    // including the last one
    procedure CreateAndSetNode(Key: string);
    procedure EnumFolders(const Path: string; const Strings: TStrings;
      const ReportListAsValue: Boolean = True); override;
    procedure EnumValues(const Path: string; const Strings: TStrings;
      const ReportListAsValue: Boolean = True); override;
    function IsFolderInt(Path: string; ListIsValue: Boolean = True): Boolean; override;
    procedure SplitKeyPath(const Path: string; out Key, ValueName: string); override;
    function PathExistsInt(const Path: string): boolean; override;
    function ValueStoredInt(const Path: string): Boolean; override;
    procedure DeleteValueInt(const Path: string); override;
    procedure DeleteSubTreeInt(const Path: string); override;
    function DoReadBoolean(const Path: string; Default: Boolean): Boolean; override;
    procedure DoWriteBoolean(const Path: string; Value: Boolean); override;
    function DoReadInteger(const Path: string; Default: Integer): Integer; override;
    procedure DoWriteInteger(const Path: string; Value: Integer); override;
    function DoReadFloat(const Path: string; Default: Extended): Extended; override;
    procedure DoWriteFloat(const Path: string; Value: Extended); override;
    function DoReadString(const Path: string; Default: string): string; override;
    procedure DoWriteString(const Path: string; Value: string); override;
    function DoReadBinary(const Path: string; var Buf; BufSize: Integer): Integer; override;
    procedure DoWriteBinary(const Path: string; const Buf; BufSize: Integer); override;

    property Xml: TJvSimpleXml read FXml;
    property RootNodeName: string read GetRootNodeName write SetRootNodeName;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

  // This class handles the flushing into a disk file
  // and publishes a few properties for them to be
  // used by the user in the IDE
  TJvAppXMLFileStorage = class (TJvCustomAppXMLStorage)
  protected
    procedure DeleteValueInt(const Path: string); override;
    procedure DeleteSubTreeInt(const Path: string); override;
    procedure DoWriteBoolean(const Path: string; Value: Boolean); override;
    procedure DoWriteInteger(const Path: string; Value: Integer); override;
    procedure DoWriteFloat(const Path: string; Value: Extended); override;
    procedure DoWriteString(const Path: string; Value: string); override;
    procedure DoWriteBinary(const Path: string; const Buf; BufSize: Integer); override;
  public
    property Xml;

    procedure Flush; override;
    procedure Reload; override;
    
    property AsString;
  published
    property AutoFlush;
    property FileName;
    property Location;
    property RootNodeName;

    property OnGetFileName;
  end;

implementation

uses
  TypInfo,
  JclStrings,
  JvTypes, JvConsts, JvResources;

const
  cNullDigit = '0';
  cCount = 'Count';
  cEmptyPath = 'EmptyPath';

function BinStrToBuf(Value: string; var Buf; BufSize: Integer): Integer;
var
  P: PChar;
begin
  if Odd(Length(Value)) then
    Value := cNullDigit + Value;
  if (Length(Value) div 2) < BufSize then
    BufSize := Length(Value) div 2;
  Result := 0;
  P := PChar(Value);
  while (BufSize > 0) do
  begin
    PChar(Buf)[Result] := Chr(StrToInt('$' + P[0] + P[1]));
    Inc(Result);
    Dec(BufSize);
    Inc(P, 2);
  end;
end;

function BufToBinStr(const Buf; BufSize: Integer): string;
var
  P: PChar;
  S: string;
begin
  SetLength(Result, BufSize * 2);
  P := PChar(Result);
  Inc(P, (BufSize - 1) * 2); // Point to end of string ^
  while BufSize > 0 do
  begin
    S := IntToHex(Ord(PChar(Buf)[BufSize]), 2);
    P[0] := S[1];
    P[1] := S[2];
    Dec(P, 2);
    Dec(BufSize);
  end;
end;

//=== TJvAppXMLStorage =======================================================

constructor TJvCustomAppXMLStorage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FXml := TJvSimpleXml.Create(nil);
  RootNodeName := 'Configuration';
  FCurrentNode := FXml.Root;
end;

destructor TJvCustomAppXMLStorage.Destroy;
begin
  inherited Destroy;
  // delete after the inherited call, see comment in
  // the base class, TJvCustomMemoryFileAppStorage
  FXml.Free;
end;

procedure TJvCustomAppXMLStorage.SetRootNodeName(const Value: string);
begin
  if Value = '' then
    raise EPropertyError.Create(RsENodeCannotBeEmpty)
  else
  begin
    StringReplace(Value, ' ', '_', [rfReplaceAll]);
    FXml.Root.Name := Value;
  end;
end;

procedure TJvCustomAppXMLStorage.SplitKeyPath(const Path: string; out Key, ValueName: string);
begin
  inherited SplitKeyPath(Path, Key, ValueName);
  if Key = '' then
    Key := Path;
end;

function TJvCustomAppXMLStorage.ValueStoredInt(const Path: string): Boolean;
var
  Section: string;
  Key: string;
  Node: TJvSimpleXmlElem;
begin
  SplitKeyPath(Path, Section, Key);
  Result := False;
  Node := GetNodeFromPath(Section);
  if Assigned(Node) then
    Result := Assigned(Node.Items.ItemNamed[Key]);
end;

procedure TJvCustomAppXMLStorage.DeleteValueInt(const Path: string);
var
  Node: TJvSimpleXmlElem;
  Section: string;
  Key: string;
begin
  if ValueStored(Path) then
  begin
    SplitKeyPath(Path, Section, Key);
    Node := GetNodeFromPath(Section);
    if Assigned(Node) then
      Node.Items.Delete(Key);
  end;
end;

procedure TJvCustomAppXMLStorage.DeleteSubTreeInt(const Path: string);
var
  TopNode: string;
  Node: TJvSimpleXmlElem;
  Parent: TJvSimpleXmlElem;
  Name: string;
begin
  TopNode := GetAbsPath(Path);
  if TopNode = '' then
    TopNode := Path;
  Node := GetNodeFromPath(TopNode);
  if Assigned(Node) then
  begin
    Name := Node.Name;
    Parent := Node.Parent;
    if Assigned(Parent) then
      Parent.Items.Delete(Name);
  end;
end;

function TJvCustomAppXMLStorage.DoReadInteger(const Path: string; Default: Integer): Integer;
var
  ParentPath: string;
  ValueName: string;
  Node: TJvSimpleXmlElem;
begin
  SplitKeyPath(Path, ParentPath, ValueName);

  Node := GetNodeFromPath(ParentPath);

  if Assigned(Node) and Assigned(Node.Items.ItemNamed[ValueName]) then
  begin
    try
      Result := Node.Items.ItemNamed[ValueName].IntValue;
    except
      if StorageOptions.DefaultIfReadConvertError then
        Result := Default
      else
        raise;
    end;
  end
  else
  if StorageOptions.DefaultIfValueNotExists then
    Result := Default
  else
    raise EJVCLException.CreateFmt(RsEPathDoesntExists, [Path]);
end;

procedure TJvCustomAppXMLStorage.DoWriteInteger(const Path: string; Value: Integer);
var
  ParentPath: string;
  ValueName: string;
begin
  SplitKeyPath(Path, ParentPath, ValueName);
  CreateAndSetNode(ParentPath);
  FXml.Options := [sxoAutoCreate, sxoAutoIndent];
  FCurrentNode.Items.ItemNamed[ValueName].IntValue := Value;
  FXml.Options := [sxoAutoIndent];
end;

function TJvCustomAppXMLStorage.DoReadFloat(const Path: string; Default: Extended): Extended;
var
  ParentPath: string;
  ValueName: string;
  StrValue: string;
  Node: TJvSimpleXmlElem;
begin
  SplitKeyPath(Path, ParentPath, ValueName);

  Node := GetNodeFromPath(ParentPath);

  if Assigned(Node) and Assigned(Node.Items.ItemNamed[ValueName]) then
  begin
    try
      StrValue := Node.Items.ItemNamed[ValueName].Value;
      Result := StrToFloat(StrValue);
    except
      if StorageOptions.DefaultIfReadConvertError then
        Result := Default
      else
        raise;
    end;
  end
  else
  if StorageOptions.DefaultIfValueNotExists then
    Result := Default
  else
    raise EJVCLException.CreateFmt(RsEPathDoesntExists, [Path]);
end;

procedure TJvCustomAppXMLStorage.DoWriteFloat(const Path: string; Value: Extended);
var
  ParentPath: string;
  ValueName: string;
begin
  SplitKeyPath(Path, ParentPath, ValueName);
  CreateAndSetNode(ParentPath);
  FXml.Options := [sxoAutoCreate, sxoAutoIndent];
  FCurrentNode.Items.ItemNamed[ValueName].Value := FloatToStr(Value);
  FXml.Options := [sxoAutoIndent];
end;

function TJvCustomAppXMLStorage.DoReadString(const Path: string; Default: string): string;
var
  ParentPath: string;
  ValueName: string;
  Node: TJvSimpleXmlElem;
begin
  SplitKeyPath(Path, ParentPath, ValueName);

  Node := GetNodeFromPath(ParentPath);

  if Assigned(Node) and Assigned(Node.Items.ItemNamed[ValueName]) then
  begin
    try
      Result := Node.Items.ItemNamed[ValueName].Value;
    except
      if StorageOptions.DefaultIfReadConvertError then
        Result := Default
      else
        raise;
    end;
  end
  else
  if StorageOptions.DefaultIfValueNotExists then
    Result := Default
  else
    raise EJVCLException.CreateFmt(RsEPathDoesntExists, [Path]);
end;

procedure TJvCustomAppXMLStorage.DoWriteString(const Path: string; Value: string);
var
  ParentPath: string;
  ValueName: string;
begin
  SplitKeyPath(Path, ParentPath, ValueName);
  CreateAndSetNode(ParentPath);
  FXml.Options := [sxoAutoCreate, sxoAutoIndent];
  FCurrentNode.Items.ItemNamed[ValueName].Value := Value;
  FXml.Options := [sxoAutoIndent];
end;

function TJvCustomAppXMLStorage.DoReadBinary(const Path: string; var Buf; BufSize: Integer): Integer;
var
  Value: string;
begin
  Value := DoReadString(Path, '');
  Result := BinStrToBuf(Value, Buf, BufSize);
end;

procedure TJvCustomAppXMLStorage.DoWriteBinary(const Path: string; const Buf; BufSize: Integer);
begin
  DoWriteString(Path, BufToBinStr(Buf, BufSize));
end;

procedure TJvCustomAppXMLStorage.EnumFolders(const Path: string;
  const Strings: TStrings; const ReportListAsValue: Boolean);
var
  RefPath: string;
  I: Integer;
  Node: TJvSimpleXmlElem;
begin
  RefPath := GetAbsPath(Path);
  if RefPath = '' then
    RefPath := cEmptyPath;

  Node := GetNodeFromPath(RefPath, FXml.Root);

  if Node <> nil then
  begin
    Strings.BeginUpdate;
    try
      Strings.Clear;
      for I := 0 to Node.Items.Count - 1 do
        Strings.Add(Node.Items[I].Name);
    finally
      Strings.EndUpdate;
    end;
  end
  else
    raise EJVCLException.CreateFmt(RsEPathDoesntExists, [RefPath]);
end;

procedure TJvCustomAppXMLStorage.EnumValues(const Path: string;
  const Strings: TStrings; const ReportListAsValue: Boolean);
var
  PathIsList: Boolean;
  RefPath: string;
  I: Integer;
  Node: TJvSimpleXmlElem;
  Name: string;
begin
  PathIsList := ReportListAsValue and ListStored(Path);
  RefPath := GetAbsPath(Path);
  if RefPath = '' then
    RefPath := cEmptyPath;

  Node := GetNodeFromPath(RefPath, FXml.Root);

  if Node <> nil then
  begin
    Strings.BeginUpdate;
    try
      Strings.Clear;
      for I := 0 to Node.Items.Count - 1 do
      begin
        Name := Node.Items[I].Name;
        if (not PathIsList or (not AnsiSameText(cCount, Name) and
          not NameIsListItem(Name))) then
          Strings.Add(Name);
      end;
    finally
      Strings.EndUpdate;
    end;
  end
  else
    raise EJVCLException.CreateFmt(RsEPathDoesntExists, [RefPath]);
end;

function TJvCustomAppXMLStorage.IsFolderInt(Path: string;
  ListIsValue: Boolean): Boolean;
var
  RefPath: string;
  ValueNames: TStrings;
  I: Integer;
  Node: TJvSimpleXmlElem;
  Name: string;
begin
  RefPath := GetAbsPath(Path);
  if RefPath = '' then
    RefPath := cEmptyPath;

  Node := GetNodeFromPath(RefPath);
  Result := False;
  if Assigned(Node) and ListIsValue and
    Assigned(Node.Items.ItemNamed[cCount]) then
  begin
    ValueNames := TStringList.Create;
    try
      I := 0;
      repeat
        Name := Node.Items[I].Name;
        Result := not AnsiSameText(cCount, Name) and
          not NameIsListItem(Name);
        Inc(I);
      until (I = Node.Items.Count) or Result;
    finally
      ValueNames.Free;
    end;
  end;
end;

function TJvCustomAppXMLStorage.GetRootNodeName: string;
begin
  Result := FXml.Root.Name;
end;

procedure TJvCustomAppXMLStorage.CreateAndSetNode(Key: string);
begin
  FXml.Options := [sxoAutoCreate, sxoAutoIndent];
  FCurrentNode := GetNodeFromPath(Key, FXml.Root);
  FXml.Options := [sxoAutoIndent];
end;

function TJvCustomAppXMLStorage.GetNodeFromPath(Path: string; StartNode: TJvSimpleXmlElem = nil): TJvSimpleXmlElem;
var
  NodeList: TStringList;
  I: Integer;
  Node: TJvSimpleXmlElem;
begin
  NodeList := TStringList.Create;
  if StartNode <> nil then
    Node := StartNode
  else
    Node := FCurrentNode;

  try
    try
      StrToStrings(Path, '\', NodeList, false);
      for I := 0 to NodeList.Count - 1 do
      begin
        if Assigned(Node.Items.ItemNamed[NodeList[i]]) then
          Node := Node.Items.ItemNamed[NodeList[i]]
        else
        begin
          Result := nil;
          Exit;
        end;
      end;
    finally
      NodeList.Free;
    end;
  except
    Node := nil;
  end;
  Result := Node;
end;

function TJvCustomAppXMLStorage.PathExistsInt(const Path: string): boolean;
var
  SubKey: string;
  ValueName: string;
  Node: TJvSimpleXmlElem;
begin
  SplitKeyPath(Path, SubKey, ValueName);
  Result := False;
  Node := GetNodeFromPath(Path, FCurrentNode);
  if Assigned(Node) then
    Result := Assigned(Node.Items.ItemNamed[ValueName]);
end;

function TJvCustomAppXMLStorage.DoReadBoolean(const Path: string;
  Default: Boolean): Boolean;
var
  ParentPath: string;
  ValueName: string;
  Node: TJvSimpleXmlElem;
begin
  SplitKeyPath(Path, ParentPath, ValueName);

  Node := GetNodeFromPath(ParentPath);

  if Assigned(Node) and Assigned(Node.Items.ItemNamed[ValueName]) then
  begin
    try
      Result := Node.Items.ItemNamed[ValueName].BoolValue;
    except
      if StorageOptions.DefaultIfReadConvertError then
        Result := Default
      else
        raise;
    end;
  end
  else
  if StorageOptions.DefaultIfValueNotExists then
    Result := Default
  else
    raise EJVCLException.CreateFmt(RsEPathDoesntExists, [Path]);
end;

procedure TJvCustomAppXMLStorage.DoWriteBoolean(const Path: string;
  Value: Boolean);
var
  ParentPath: string;
  ValueName: string;
begin
  SplitKeyPath(Path, ParentPath, ValueName);
  CreateAndSetNode(ParentPath);
  FXml.Options := [sxoAutoCreate, sxoAutoIndent];
  FCurrentNode.Items.ItemNamed[ValueName].BoolValue := Value;
  FXml.Options := [sxoAutoIndent];
end;

function TJvCustomAppXMLStorage.GetAsString: string;
begin
  Result := FXml.SaveToString;
end;

procedure TJvCustomAppXMLStorage.SetAsString(const Value: string);
begin
  FXml.LoadFromString(Value);
end;

{ TJvAppXMLFileStorage }

procedure TJvAppXMLFileStorage.DeleteSubTreeInt(const Path: string);
begin
  inherited;
  if AutoFlush then Flush;
end;

procedure TJvAppXMLFileStorage.DeleteValueInt(const Path: string);
begin
  inherited;
  if AutoFlush then Flush;
end;

procedure TJvAppXMLFileStorage.DoWriteBinary(const Path: string; const Buf;
  BufSize: Integer);
begin
  inherited;
  if AutoFlush then Flush;
end;

procedure TJvAppXMLFileStorage.DoWriteBoolean(const Path: string;
  Value: Boolean);
begin
  inherited;
  if AutoFlush then Flush;
end;

procedure TJvAppXMLFileStorage.DoWriteFloat(const Path: string;
  Value: Extended);
begin
  inherited;
  if AutoFlush then Flush;
end;

procedure TJvAppXMLFileStorage.DoWriteInteger(const Path: string;
  Value: Integer);
begin
  inherited;
  if AutoFlush then Flush;
end;

procedure TJvAppXMLFileStorage.DoWriteString(const Path: string;
  Value: string);
begin
  inherited;
  if AutoFlush then Flush;
end;

procedure TJvAppXMLFileStorage.Flush;
begin
  if FullFileName <> '' then
    FXml.SaveToFile(FullFileName);
end;

procedure TJvAppXMLFileStorage.Reload;
begin
  if FileExists(FullFileName) then
    FXml.LoadFromFile(FullFileName);
end;

end.

