{-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: JvDBFilter.PAS, released on 2002-07-04.

The Initial Developers of the Original Code are: Fedor Koshevnikov, Igor Pavluk and Serge Korolev
Copyright (c) 1997, 1998 Fedor Koshevnikov, Igor Pavluk and Serge Korolev
Copyright (c) 2001,2002 SGB Software
All Rights Reserved.

Last Modified: 2002-07-04

You may retrieve the latest version of this file at the Project JEDI's JVCL home page,
located at http://jvcl.sourceforge.net

Known Issues:
-----------------------------------------------------------------------------}

{$I JVCL.INC}

unit JvBDEFilter;

interface

uses
  SysUtils, Classes, Forms,
  Bde, DB, DBTables,
  JvTypes, JvComponent;

type
  TFilterLogicCond = (flAnd, flOr); { for captured DataSet }
  TDBFilterOption = TFilterOption;
  TDBFilterOptions = TFilterOptions;

  TFilterEvent = function(Sender: TObject; DataSet: TDataSet): Boolean of object;

  TDataSetStorage = record { for internal use only }
    FBof: Boolean;
    FEof: Boolean;
    State: TDataSetState;
    CanModify: Boolean;
    BeforePost: TDataSetNotifyEvent;
    BeforeCancel: TDataSetNotifyEvent;
    BeforeInsert: TDataSetNotifyEvent;
    BeforeEdit: TDataSetNotifyEvent;
  end;

  TJvDBFilter = class(TJvComponent)
  private
    FParser: TObject;
    FDataLink: TDataLink;
    FIgnoreDataEvents: Boolean;
    FPriority: Word;
    FOptions: TDBFilterOptions;
    FLogicCond: TFilterLogicCond;
    FFilter: TStrings;
    FExprHandle: hDBIFilter;
    FFuncHandle: hDBIFilter;
    FDataHandle: hDBICur;
    FActive: Boolean;
    FCaptured: Boolean;
    FStreamedActive: Boolean;
    FActivating: Boolean;
    FStorage: TDataSetStorage;
    FOnFiltering: TFilterEvent;
    FOnActivate: TNotifyEvent;
    FOnDeactivate: TNotifyEvent;
    FOnSetCapture: TNotifyEvent;
    FOnReleaseCapture: TNotifyEvent;
    procedure SetDataSource(Value: TDataSource);
    function GetDataSource: TDataSource;
    function BuildTree: Boolean;
    procedure DestroyTree;
    procedure SetFilter(Value: TStrings);
    procedure SetOptions(Value: TDBFilterOptions);
    procedure SetOnFiltering(const Value: TFilterEvent);
    procedure SetPriority(Value: Word);
    procedure SetLogicCond(Value: TFilterLogicCond);
    function GetFilterText: PChar;
    procedure FilterChanged(Sender: TObject);
    function CreateExprFilter: hDBIFilter;
    function CreateFuncFilter: hDBIFilter;
    procedure DropFilters;
    procedure SetFilterHandle(var Filter: HDBIFilter; Value: HDBIFilter);
    procedure RecreateExprFilter;
    procedure RecreateFuncFilter;
    procedure ActivateFilters;
    procedure DeactivateFilters;
    function RecordFilter(RecBuf: Pointer; RecNo: Longint): Smallint;stdcall;
    procedure BeforeDataPost(DataSet: TDataSet);
    procedure BeforeDataChange(DataSet: TDataSet);
    procedure BeforeDataCancel(DataSet: TDataSet);
    procedure SetActive(Value: Boolean);
  protected
    procedure Loaded; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure DoActivate; dynamic;
    procedure DoDeactivate; dynamic;
    procedure ActiveChanged; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Update; virtual;
    procedure UpdateFuncFilter;
    procedure Activate;
    procedure Deactivate;
    procedure SetCapture;
    procedure ReleaseCapture;
    procedure ReadCaptureControls;
    property Captured: Boolean read FCaptured;
    property Handle: hDBIFilter read FExprHandle; { obsolete, use ExprFilter }
    property ExprFilter: hDBIFilter read FExprHandle;
    property FuncFilter: hDBIFilter read FFuncHandle;
  published
    property Active: Boolean read FActive write SetActive default False;
    property DataSource: TDataSource read GetDataSource write SetDataSource;
    property Filter: TStrings read FFilter write SetFilter;
    property LogicCond: TFilterLogicCond read FLogicCond write SetLogicCond default flAnd;
    property Options: TDBFilterOptions read FOptions write SetOptions default [];
    property Priority: Word read FPriority write SetPriority default 0;
    property OnActivate: TNotifyEvent read FOnActivate write FOnActivate;
    property OnDeactivate: TNotifyEvent read FOnDeactivate write FOnDeactivate;
    property OnFiltering: TFilterEvent read FOnFiltering write SetOnFiltering;
    property OnSetCapture: TNotifyEvent read FOnSetCapture write FOnSetCapture;
    property OnReleaseCapture: TNotifyEvent read FOnReleaseCapture write FOnReleaseCapture;
  end;

  EFilterError = class(EJVCLException);

procedure DropAllFilters(DataSet: TDataSet);

implementation

uses
  DBConsts, Dialogs, DbCommon,
  JvConsts, JvJVCLUtils, JvDBUtils, JvBdeUtils;

procedure DropAllFilters(DataSet: TDataSet);
begin
  if (DataSet <> nil) and DataSet.Active then
  begin
    DataSet.Filtered := False;
    DbiDropFilter((DataSet as TBDEDataSet).Handle, nil);
    DataSet.CursorPosChanged;
    DataSet.Resync([]);
  end;
end;

procedure FilterError(const Ident: string);
begin
  raise EFilterError.Create(Ident);
end;

procedure FilterErrorFmt(const Ident: string; const Args: array of const);
begin
  raise EFilterError.CreateFmt(Ident, Args);
end;

const
  SExprNothing = '""'; { nothing token name }
  cQuota = ''''; { quotas for string constants }
  cFldQuotaLeft = '['; { left qouta for field names }
  cFldQuotaRight = ']'; { right qouta for field names }

{$HINTS OFF}

type
  THackDataSet = class(TDataSet);

{ TNastyDataSet }

{*******************************************************}
{ !! ATTENTION Nasty implementation                     }
{*******************************************************}
{                                                       }
{ These class definitions were copied from TDataSet     }
{ (DB.PAS) and TBDEDataSet (DBTABLES.PAS).              }
{ It is needed to access FState, FBOF, FEOF, FBuffers,  }
{ FRecordCount, FActiveRecord, FCanModify private       }
{ fields of TDataSet.                                   }
{                                                       }
{ Any changes in the underlying classes may cause       }
{ errors in this implementation!                        }
{                                                       }
{*******************************************************}

  PBufferList = TBufferList;

  TNastyDataSet = class(TComponent)
  private
    FFields: TFields;
    FAggFields: TFields;
    FFieldDefs: TFieldDefs;
    FFieldDefList: TFieldDefList;
    FFieldList: TFieldList;
    FDataSources: TList;
    FFirstDataLink: TDataLink;
    FBufferCount: Integer;
    FRecordCount: Integer;
    FActiveRecord: Integer;
    FCurrentRecord: Integer;
    FBuffers: TBufferList;
    FCalcBuffer: PChar;
    FBookmarkSize: Integer;
    FCalcFieldsSize: Integer;
    FDesigner: TDataSetDesigner;
    FDisableCount: Integer;
    FBlobFieldCount: Integer;
    FFilterText: string;
    FBlockReadSize: Integer;
    FConstraints: TCheckConstraints;
    FDataSetField: TDataSetField;
    FNestedDataSets: TList;
    FNestedDatasetClass: TClass;
    FReserved: Pointer;
    FFieldNoOfs: Integer;
    { Byte sized data members (for alignment) }
    FFilterOptions: TFilterOptions;
    FState: TDataSetState;
    FEnableEvent: TDataEvent;
    FDisableState: TDataSetState;
    FBOF: Boolean;
    FEOF: Boolean;
  end;

  TBDENastyDataSet = class(TDataSet)
  private
    FHandle: HDBICur;
    FStmtHandle: HDBIStmt;
    FRecProps: RecProps;
    FLocale: TLocale;
    FExprFilter: HDBIFilter;
    FFuncFilter: HDBIFilter;
    FFilterBuffer: PChar;
    FIndexFieldMap: DBIKey;
    FExpIndex: Boolean;
    FCaseInsIndex: Boolean;
    FCachedUpdates: Boolean;
    FInUpdateCallback: Boolean;
    FCanModify: Boolean;
  end;

{$HINTS ON}

procedure dsSetState(DataSet: TDataSet; Value: TDataSetState);
begin
  TNastyDataSet(DataSet).FState := Value;
end;

procedure dsSetBOF(DataSet: TDataSet; Value: Boolean);
begin
  TNastyDataSet(DataSet).FBOF := Value;
end;

procedure dsSetEOF(DataSet: TDataSet; Value: Boolean);
begin
  TNastyDataSet(DataSet).FEOF := Value;
end;

procedure AssignBuffers(const Source: TBufferList; var Dest: TBufferList);
var
  Len: Integer;
begin
  Len := High(Source) + 1;
  SetLength(Dest, Len);
  Move(Pointer(Source)^, Pointer(Dest)^, Len * SizeOf(PChar));
end;

procedure dsGetBuffers(DataSet: TDataSet; var ABuf: TBufferList);
begin
  with TNastyDataSet(DataSet) do
    AssignBuffers(FBuffers, ABuf);
end;

procedure dsSetBuffers(DataSet: TDataSet; const Value: TBufferList);
begin
  AssignBuffers(Value, TNastyDataSet(DataSet).FBuffers);
end;

function dsGetRecordCount(DataSet: TDataSet): Integer;
begin
  Result := TNastyDataSet(DataSet).FRecordCount;
end;

procedure dsSetRecordCount(DataSet: TDataSet; Value: Integer);
begin
  TNastyDataSet(DataSet).FRecordCount := Value;
end;

function dsGetActiveRecord(DataSet: TDataSet): Integer;
begin
  Result := TNastyDataSet(DataSet).FActiveRecord;
end;

procedure dsSetActiveRecord(DataSet: TDataSet; Value: Integer);
begin
  TNastyDataSet(DataSet).FActiveRecord := Value;
end;

function dsGetCanModify(DataSet: TBDEDataSet): Boolean;
begin
  Result := TBDENastyDataSet(DataSet).FCanModify;
end;

procedure dsSetCanModify(DataSet: TBDEDataSet; Value: Boolean);
begin
  TBDENastyDataSet(DataSet).FCanModify := Value;
end;

//=== TJvFilterDataLink ======================================================

type
  TJvFilterDataLink = class(TDataLink)
  private
    FFilter: TJvDBFilter;
  protected
    procedure ActiveChanged; override;
  public
    constructor Create(Filter: TJvDBFilter);
    destructor Destroy; override;
  end;

constructor TJvFilterDataLink.Create(Filter: TJvDBFilter);
begin
  inherited Create;
  FFilter := Filter;
end;

destructor TJvFilterDataLink.Destroy;
begin
  FFilter := nil;
  inherited Destroy;
end;

procedure TJvFilterDataLink.ActiveChanged;
begin
  if FFilter <> nil then
    FFilter.ActiveChanged;
end;

//=== TJvDBFilter ============================================================

constructor TJvDBFilter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDataLink := TJvFilterDataLink.Create(Self);
  FFilter := TStringList.Create;
  TStringList(FFilter).OnChange := FilterChanged;
  FLogicCond := flAnd;
  FIgnoreDataEvents := False;
end;

destructor TJvDBFilter.Destroy;
begin
  TStringList(FFilter).OnChange := nil;
  Deactivate;
  DropFilters;
  FFilter.Free;
  FDataLink.Free;
  inherited Destroy;
end;

procedure TJvDBFilter.Loaded;
begin
  inherited Loaded;
  try
    if FStreamedActive then
      Active := True;
  except
    if csDesigning in ComponentState then
      Application.HandleException(Self)
    else
      raise;
  end;
end;

function TJvDBFilter.GetDataSource: TDataSource;
begin
  Result := FDataLink.DataSource;
end;

procedure TJvDBFilter.SetDataSource(Value: TDataSource);
var
  DSChange: Boolean;
begin
  if not (csLoading in ComponentState) then
    ReleaseCapture;
  DSChange := True;
  if (Value <> nil) and (DataSource <> nil) then
    DSChange := (Value.DataSet <> FDataLink.DataSet);
  FIgnoreDataEvents := not DSChange;
  try
    if not (csLoading in ComponentState) then
      ActiveChanged;
    FDataLink.DataSource := Value;
    if Value <> nil then
      Value.FreeNotification(Self);
  finally
    FIgnoreDataEvents := False;
  end;
end;

procedure TJvDBFilter.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FDataLink <> nil) then
  begin
    if AComponent = DataSource then
      DataSource := nil;
  end;
end;

function TJvDBFilter.CreateExprFilter: hDBIFilter;
begin
  Result := nil;
  if FFilter.Count > 0 then
    if BuildTree then
    try
      Check(DbiAddFilter((FDatalink.DataSet as TBDEDataSet).Handle,
        Longint(Self), FPriority, False, pCANExpr(TExprParser(FParser).FilterData), nil,
        Result));
      FDataHandle := TBDEDataSet(FDatalink.DataSet).Handle;
    finally
      DestroyTree;
    end;
end;

function TJvDBFilter.CreateFuncFilter: hDBIFilter;
var
  FuncPriority: Word;
begin
  if (FPriority < $FFFF) and (FExprHandle <> nil) then
    FuncPriority := FPriority + 1
  else
    FuncPriority := FPriority;
  Check(DbiAddFilter((FDataLink.DataSet as TBDEDataSet).Handle, Longint(Self),
    FuncPriority, False, nil, PFGENFilter(@TJvDBFilter.RecordFilter),
    Result));
  FDataHandle := TBDEDataSet(FDatalink.DataSet).Handle;
end;

procedure TJvDBFilter.SetFilterHandle(var Filter: HDBIFilter;
  Value: HDBIFilter);
var
  Info: FilterInfo;
begin
  if FActive and FDataLink.Active then
  begin
    FDataLink.DataSet.CursorPosChanged;
    DbiSetToBegin((FDataLink.DataSet as TBDEDataSet).Handle);
    if (Filter <> nil) and (Filter <> Value) then
      DbiDropFilter((FDataLink.DataSet as TBDEDataSet).Handle, Filter);
    Filter := Value;
    if Filter <> nil then
      DbiActivateFilter((FDataLink.DataSet as TBDEDataSet).Handle, Filter);
  end
  else
  if FActive and (Filter <> nil) and (FDataHandle <> nil) and
    (FDataLink.DataSet = nil) and (Value = nil) then
  begin
    if DbiGetFilterInfo(FDataHandle, Filter, 0, 0, Info) = DBIERR_NONE then
      DbiDeactivateFilter(FDataHandle, Filter);
    Filter := Value;
  end
  else
  begin
    Filter := Value;
  end;
end;

procedure TJvDBFilter.DropFilters;
begin
  SetFilterHandle(FExprHandle, nil);
  SetFilterHandle(FFuncHandle, nil);
  FDataHandle := nil;
  FActive := False;
end;

procedure TJvDBFilter.ActivateFilters;
begin
  if FExprHandle <> nil then
    DbiActivateFilter((FDataLink.DataSet as TBDEDataSet).Handle, FExprHandle);
  if FFuncHandle <> nil then
    DbiActivateFilter((FDataLink.DataSet as TBDEDataSet).Handle, FFuncHandle);
end;

procedure TJvDBFilter.DeactivateFilters;
begin
  if FFuncHandle <> nil then
    DbiDeactivateFilter(TBDEDataSet(FDatalink.DataSet).Handle, FFuncHandle);
  if FExprHandle <> nil then
    DbiDeactivateFilter(TBDEDataSet(FDatalink.DataSet).Handle, FExprHandle);
end;

function TJvDBFilter.RecordFilter(RecBuf: Pointer; RecNo: Longint): Smallint;
var
  ACanModify: Boolean;
  Buffers: PBufferList;
  BufPtr: TBufferList;
  ActiveRecord: Integer;
  RecCount: Integer;
  DS: TBDEDataSet;
begin
  Result := Ord(True);
  if Assigned(FOnFiltering) and (FFuncHandle <> nil) then
  try
    DS := FDatalink.DataSet as TBDEDataSet;
    { save current DataSet's private fields values }
    dsGetBuffers(DS, Buffers);
    ActiveRecord := dsGetActiveRecord(DS);
    RecCount := dsGetRecordCount(DS);
    ACanModify := dsGetCanModify(DS);
    try
      dsSetActiveRecord(DS, 0);
      dsSetRecordCount(DS, 1); { FActiveRecord + 1 }
      dsSetCanModify(DS, False);
      SetLength(BufPtr, 1);
      BufPtr[0] := PChar(RecBuf);
      dsSetBuffers(DS, BufPtr);
      { call user defined function }
      Result := Ord(FOnFiltering(Self, DS));
    finally
      dsSetCanModify(DS, ACanModify);
      dsSetActiveRecord(DS, ActiveRecord);
      dsSetRecordCount(DS, RecCount);
      dsSetBuffers(DS, Buffers);
    end;
  except
    Application.HandleException(Self);
    Result := ABORT; { BDE constant, not SysUtils.pas procedure }
  end;
end;

procedure TJvDBFilter.FilterChanged(Sender: TObject);
begin
  RecreateExprFilter;
end;

procedure TJvDBFilter.SetOnFiltering(const Value: TFilterEvent);
begin
  if Assigned(FOnFiltering) <> Assigned(Value) then
  begin
    FOnFiltering := Value;
    RecreateFuncFilter;
  end
  else
    FOnFiltering := Value;
end;

procedure TJvDBFilter.RecreateFuncFilter;
var
  Filter: HDBIFilter;
begin
  if FDataLink.Active and not (csReading in ComponentState) then
  begin
    if not FCaptured then
      FDataLink.DataSet.CheckBrowseMode;
    if Assigned(FOnFiltering) then
      Filter := CreateFuncFilter
    else
      Filter := nil;
    SetFilterHandle(FFuncHandle, Filter);
  end;
  if FDataLink.Active and Active and not FCaptured then
    FDataLink.DataSet.First;
end;

procedure TJvDBFilter.RecreateExprFilter;
var
  Filter: HDBIFilter;
begin
  if FDataLink.Active and not (csReading in ComponentState) then
  begin
    if not FCaptured then
      FDataLink.DataSet.CheckBrowseMode;
    if FFilter.Count > 0 then
    try
      Filter := CreateExprFilter;
    except
      if Active or FActivating then
        raise
      else
        Filter := nil;
    end
    else
      Filter := nil;
    SetFilterHandle(FExprHandle, Filter);
  end;
  if FDataLink.Active and Active and not FCaptured then
    FDataLink.DataSet.First;
end;

procedure TJvDBFilter.SetFilter(Value: TStrings);
begin
  FFilter.Assign(Value);
end;

procedure TJvDBFilter.SetOptions(Value: TDBFilterOptions);
begin
  if Value <> FOptions then
  begin
    FOptions := Value;
    RecreateExprFilter;
  end;
end;

procedure TJvDBFilter.SetLogicCond(Value: TFilterLogicCond);
begin
  FLogicCond := Value;
end;

procedure TJvDBFilter.SetPriority(Value: Word);
begin
  if FPriority <> Value then
  begin
    FPriority := Value;
    Update;
  end;
end;

function TJvDBFilter.GetFilterText: PChar;
var
  BufLen: Word;
  I: Integer;
  StrEnd: PChar;
  StrBuf: array [0..255] of Char;
begin
  BufLen := 1;
  for I := 0 to FFilter.Count - 1 do
    Inc(BufLen, Length(Filter.Strings[I]) + 1);
  Result := StrAlloc(BufLen);
  try
    StrEnd := Result;
    for I := 0 to Filter.Count - 1 do
    begin
      if Filter.Strings[I] <> '' then
      begin
        StrPCopy(StrBuf, Filter.Strings[I]);
        StrEnd := StrECopy(StrEnd, StrBuf);
        StrEnd := StrECopy(StrEnd, ' ');
      end;
    end;
  except
    StrDispose(Result);
    raise;
  end;
end;

procedure TJvDBFilter.DestroyTree;
begin
  if FParser <> nil then
  begin
    FParser.Free;
    FParser := nil;
  end;
end;

procedure TJvDBFilter.BeforeDataPost(DataSet: TDataSet);
begin
  ReadCaptureControls;
  ReleaseCapture;
  Activate;
  SysUtils.Abort;
end;

procedure TJvDBFilter.BeforeDataChange(DataSet: TDataSet);
begin
  FilterError(SCaptureFilter);
end;

procedure TJvDBFilter.BeforeDataCancel(DataSet: TDataSet);
begin
  ReleaseCapture;
end;

function TJvDBFilter.BuildTree: Boolean;
var
  Expr: PChar;
  I: Integer;
begin
  Result := True;
  if not FDataLink.Active then
    _DBError(SDataSetClosed);
  TStringList(FFilter).OnChange := nil;
  try
    for I := FFilter.Count - 1 downto 0 do
      if FFilter[I] = '' then
        FFilter.Delete(I);
  finally
    TStringList(FFilter).OnChange := FilterChanged;
  end;
  if FFilter.Count = 0 then
  begin
    Result := False;
    Exit;
  end;
  Expr := GetFilterText;
  try
    if StrLen(Expr) = 0 then
    begin
      Result := False;
      Exit;
    end;
    FParser := TExprParser.Create(FDataLink.DataSet, Expr,
      TFilterOptions(FOptions), [], '', nil, FldTypeMap);
  finally
    StrDispose(Expr);
  end;
end;

procedure TJvDBFilter.DoActivate;
begin
  if Assigned(FOnActivate) then
    FOnActivate(Self);
end;

procedure TJvDBFilter.DoDeactivate;
begin
  if Assigned(FOnDeactivate) then
    FOnDeactivate(Self);
end;

procedure TJvDBFilter.SetActive(Value: Boolean);
var
  Bookmark: TBookmark;
begin
  if csReading in ComponentState then
    FStreamedActive := Value
  else
  if FDatalink.Active then
  begin
    FDatalink.DataSet.CheckBrowseMode;
    if FActive <> Value then
    begin
      if Value then
      begin
        FActivating := True;
        try
          if FCaptured then
            FilterError(SCaptureFilter);
          DbiSetToBegin((FDatalink.DataSet as TBDEDataSet).Handle);
          if FExprHandle = nil then
            RecreateExprFilter;
          if FFuncHandle = nil then
            RecreateFuncFilter;
          ActivateFilters;
          FDatalink.DataSet.First;
          FActive := Value;
          DoActivate;
        finally
          FActivating := False;
        end;
      end
      else
      begin
        if not IsDataSetEmpty(FDatalink.DataSet) then
          Bookmark := FDatalink.DataSet.GetBookmark
        else
          Bookmark := nil;
        try
          DbiSetToBegin((FDatalink.DataSet as TBDEDataSet).Handle);
          DeactivateFilters;
          if not SetToBookmark(FDatalink.DataSet, Bookmark) then
            FDatalink.DataSet.First;
        finally
          FDatalink.DataSet.FreeBookmark(Bookmark);
        end;
        FActive := Value;
        DoDeactivate;
      end;
      FActive := Value;
    end;
  end
  else
    FActive := Value;
end;

procedure TJvDBFilter.Activate;
begin
  SetActive(True);
end;

procedure TJvDBFilter.Deactivate;
begin
  SetActive(False);
end;

procedure TJvDBFilter.SetCapture;
begin
  if not FCaptured and (FDataLink <> nil) then
  begin
    if not FDataLink.Active then
      _DBError(SDataSetClosed);
    DataSource.DataSet.CheckBrowseMode;
    Deactivate;
    FIgnoreDataEvents := True;
    { store private fields values }
    with FStorage do
    begin
      FBof := DataSource.DataSet.Bof;
      FEof := DataSource.DataSet.Eof;
      State := DataSource.DataSet.State;
      CanModify := dsGetCanModify(FDatalink.DataSet as TBDEDataSet);
      BeforePost := DataSource.DataSet.BeforePost;
      BeforeCancel := DataSource.DataSet.BeforeCancel;
      BeforeInsert := DataSource.DataSet.BeforeInsert;
      BeforeEdit := DataSource.DataSet.BeforeEdit;
    end;
    DbiInitRecord((DataSource.DataSet as TBDEDataSet).Handle,
      DataSource.DataSet.ActiveBuffer);
    dsSetBOF(DataSource.DataSet, True);
    dsSetEOF(DataSource.DataSet, True);
    dsSetState(DataSource.DataSet, dsEdit);
    dsSetCanModify(DataSource.DataSet as TBDEDataSet, True);
    DataSource.DataSet.BeforeCancel := BeforeDataCancel;
    DataSource.DataSet.BeforePost := BeforeDataPost;
    DataSource.DataSet.BeforeInsert := BeforeDataChange;
    DataSource.DataSet.BeforeEdit := BeforeDataChange;
    THackDataSet(DataSource.DataSet).DataEvent(deUpdateState, 0);
    THackDataSet(DataSource.DataSet).DataEvent(deDataSetChange, 0);
    {DataSource.DataSet := DataSource.DataSet;}
    FCaptured := True;
    if Assigned(FOnSetCapture) then
      FOnSetCapture(Self);
  end;
end;

procedure TJvDBFilter.ReleaseCapture;
begin
  if (DataSource <> nil) and (DataSource.DataSet <> nil) and FCaptured then
  begin
    { restore private fields values stored in SetCapture }
    with FStorage do
    begin
      dsSetBOF(DataSource.DataSet, FBof);
      dsSetEOF(DataSource.DataSet, FEof);
      dsSetState(DataSource.DataSet, State);
      dsSetCanModify(DataSource.DataSet as TBDEDataSet, CanModify);
      DataSource.DataSet.BeforePost := BeforePost;
      DataSource.DataSet.BeforeCancel := BeforeCancel;
      DataSource.DataSet.BeforeInsert := BeforeInsert;
      DataSource.DataSet.BeforeEdit := BeforeEdit;
    end;
    FCaptured := False;
    FIgnoreDataEvents := False;
    DataSource.DataSet.Resync([]);
    THackDataSet(DataSource.DataSet).DataEvent(deUpdateState, 0);
    THackDataSet(DataSource.DataSet).DataEvent(deDataSetChange, 0);
    {DataSource.DataSet := DataSource.DataSet;}
    if Assigned(FOnReleaseCapture) then
      FOnReleaseCapture(Self);
    ActiveChanged;
  end;
end;

procedure TJvDBFilter.ReadCaptureControls;
const
  LogicStr: array [TFilterLogicCond] of string[4] = (' AND', ' OR');
var
  I: Integer;
  Field: TField;
  S: string;
begin
  if FCaptured then
  begin
    FFilter.BeginUpdate;
    try
      FFilter.Clear;
      with FDatalink.DataSet do
      begin
        UpdateRecord;
        for I := 0 to FieldCount - 1 do
        begin
          Field := Fields[I];
          if not (Field.IsNull or Field.Calculated
            or Field.Lookup) then
          begin
            S := '(' + cFldQuotaLeft + Field.FieldName + cFldQuotaRight +
              '=' + cQuota + Field.AsString + cQuota + ')';
            if FFilter.Count > 0 then
              S := S + LogicStr[FLogicCond];
            FFilter.Insert(0, S);
          end;
        end;
      end;
    finally
      FFilter.EndUpdate;
    end;
  end
  else
    FilterError(SNotCaptureFilter);
end;

procedure TJvDBFilter.UpdateFuncFilter;
begin
  if FDataLink.Active and Active and (FFuncHandle <> nil) then
    with FDatalink.DataSet as TBDEDataSet do
    begin
      DisableControls;
      try
        DbiDeactivateFilter(Handle, FFuncHandle);
        DbiActivateFilter(Handle, FFuncHandle);
        {CursorPosChanged; Resync([]);}
        First;
      finally
        EnableControls;
      end;
    end;
end;

procedure TJvDBFilter.Update;
begin
  if FDataLink.Active and Active then
  begin
    FDatalink.DataSet.DisableControls;
    try
      RecreateExprFilter;
      RecreateFuncFilter;
      {DeactivateFilters; ActivateFilters;}
    finally
      FDatalink.DataSet.EnableControls;
    end;
  end
  else
    DeactivateFilters;
end;

procedure TJvDBFilter.ActiveChanged;
var
  WasActive: Boolean;
begin
  if not FIgnoreDataEvents then
  begin
    WasActive := Active;
    DropFilters;
    if not (csDestroying in ComponentState) then
    begin
      RecreateExprFilter;
      RecreateFuncFilter;
      if WasActive then
        Activate;
    end;
  end;
end;

end.

