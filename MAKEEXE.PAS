{$A+,B-,D+,E-,F-,G+,I-,L+,N-,O-,P-,Q-,R-,S+,T-,V+,X+,Y+}
{$M 16384,0,0}
Program MakeExe;

Uses
  Dos,
  Crt,
  ExeUtil;

Const
  Debug         = False;
  BuffSize      = 8192;
  IDString      = 'xpanded by OBSESSiON DumpExe V. ' + Version;
  CodeFileName  = 'Code.$$$';
  DoOverlay     : Boolean = True;
  DoRename      : Boolean = True;
  DoOverWrite   : Boolean = False;

Type
  ExeHeaderType = Record
    ExeSign        , { Signature of the executable file (MZ or ZM)}
    ByteOnLastPage , { Number of bytes on the last page of the file}
    FileSizeDIV512 , { Size of the file in 512-byte blocks}
    NumberOfRel    , { Number of relocation entries}
    HeaderSizeInP  , { Size of the header in paragraphs}
    MinMemInP      , { Minimum amount of memory required in paragraphs}
    MaxMemInP      , { Maximum amount of memory required in paragraphs}
    SS             , { Initial value of the SS register}
    SP             , { Initial value of the SP register}
    ChkSum         , { Checksum of the file (optional)}
    IP             , { Initial value of the IP register}
    CS             , { Initial value of the CS register}
    RelocTabel     , { Offset of the relocation table (optional)}
    Overlay        : Word; { Overlay number (optional)}
    MyIdString     : String [Length (IDString)]; { ID string (optional)}
  End;

Var
  Buff1         ,
  Buff2         : Array [1..BuffSize+1] of Byte;
  ExeInfo       : Array [1..2] Of ExeInfoRecType;
  ExeHeader     ,
  ExeHeaderOrg  : ExeHeaderType;
  File1         ,
  File2         ,
  ExeFile       ,
  TmpFile       ,
  OutFile       : File;
  Dump1Name     ,
  Dump2Name     ,
  OrgName       ,
  NewName       : String;
  ThePath  : PathStr;
  TheDir   : DirStr;
  TheName  : NameStr;
  TheExt   : ExtStr;

Function UpStr (InStr : String) : String;
Var
  Ct : Byte;

Begin
  For Ct := 1 To Length(InStr) Do
    InStr[Ct] := Upcase(InStr[Ct]);
  UpStr := InStr;
End;

Procedure CleanUp;
Begin
  Close (File1);
  Close (File2);
  Close (ExeFile);
  Close (TmpFile);
  Close (OutFile);
  If NOT Debug Then Erase (TmpFile);
End;

Procedure Error (ErrNr : Byte; FileName : String);
Begin
  TextColor(LightRed);
  WriteLn;
  Write ('ERROR (', ErrNr, ') : Can''t ');
  Case ErrNr Of
    1 ,
    2 : WriteLn ('open ', FileName);
    3 ,
    4 ,
    9 : WriteLn ('read from ', FileName);
    5 ,
    8 : WriteLn ('find ', FileName);
    7 ,
   12 : WriteLn ('create ', FileName);
   10 ,
   11 : WriteLn ('write to ', FileName);
   14 : WriteLn ('recognize ',FileName,' as a dumpfile.');
   15 : WriteLn ('proceed. ',Dump1Name,' and ', Dump2Name,' must have same size.');
   16 : WriteLn ('rename ', FileName);
  Else
    WriteLn ('find error text, programmer is a jerk :-)');
  End;
  CleanUp;
  Erase (OutFile);
  Halt (ErrNr);
End;

Function Ask (TextStr : String; Legal : String) : Char;
Var
  Ch : Char; { Declare a variable Ch of type Char}

Begin
  Write (TextStr); { Display the value of TextStr on the screen}
  Repeat
    Ch := UpCase (ReadKey); { Read a key from the keyboard and convert it to uppercase}
  Until Pos (Ch, Legal) <> 0; { Repeat until the key pressed is found in Legal string}
  WriteLn (Ch); { Display the value of Ch on the screen and move to the next line}
  Ask := Ch; { Return the value of Ch as the result of the function}
End;

Procedure AskCont (TextStr : String);
Begin
  Write (TextStr);
  If Ask (', continue anyway ? ','YN') <> 'Y' Then Begin
    CleanUp;
    Halt(1);
  End;
End;

Procedure FindReloc;
Var
  Ct             , {Counter}
  Diff           , {Difference between Buff1 and Buff2}
  Got            : Word; {Number of bytes read from file}
  Written        : Integer; {Number of bytes written to file}
  FPos           , {Position in file}
  Relocation     : LongInt; {Relocation information}
  OrgExeFileSize : LongInt; {Original size of the EXE file}
  TempStr        : String; {Temporary string variable}
  RmFile         : File; {File variable}

Begin
  FPos      := 0; {Initialize position in file to zero}
  Diff      := 0; {Initialize difference between Buff1 and Buff2 to zero}

  WriteLn('þ Write relocations'); {Write a message to the console}

  Repeat
    BlockRead (File1, Buff1, BuffSize, Got); {Read a block of data from File1 into Buff1}
    If Got = 0 Then Break; {If we've reached the end of the buffer... exit loop.}
    BlockRead (File2, Buff2, BuffSize, Got); {Read a block of data from File2 into Buff2}

    For Ct := 1 To Got Do Begin {Loop through each byte in the block of data}
      Inc (FPos); {Increment position in file}

      If Buff1[Ct] <> Buff2[Ct] Then Begin {If the bytes are different...}
        If Ct = Got Then Begin {If this is the last byte in the block...}
          BlockRead (File1, Buff1[ct+1], 1); {Read second byte from File1 into Buff1}
          BlockRead (File2, Buff2[ct+1], 1); {Read second byte from File2 into Buff2}
        End;

        Diff := Word(Addr (Buff2[Ct])^) - Word(Addr (Buff1[Ct])^); 
       {If Diff = 863 Then Begin hardcore required diff here }
        Write('þ Ct=', Ct, ' diff=', Word(Addr (Buff2[Ct])^) - Word(Addr (Buff1[Ct])^));

        If Diff <> Word(Addr (Buff2[Ct])^) - Word(Addr (Buff1[Ct])^) Then Begin 
          {If the difference between Buff1 and Buff2 has changed...}
          {Dec (FPos); Decrement position in file}
          {Got := 0; Set number of bytes read from file to zero}
          Write(' End of valid data! Exit loop');
          {Break; End of valid data! Exit loop.}
        End;
        WriteLn;
        Word(Addr (Buff1[Ct])^) := Word(Addr (Buff1[Ct])^) - (ExeInfo[1].PSP + $10); 
        {Calculate relocation information for this byte in Buff1}
        Relocation := FPos-1; {Calculate relocation information for this byte in Buff2. MUST be done like this!}

        Relocation := (Relocation SHR 16 SHL 28) + (Relocation SHL 16 SHR 16);

        BlockWrite (OutFile, Byte(Relocation), SizeOf (Relocation), Written); {Write relocation information to output file}

        If Written <> SizeOf (Relocation) Then Error (10, NewName); {If there was an error writing to the output file...}

        Inc (Ct); {Skip next byte of word}
        Inc (FPos); {Increment position in file}
        Inc (ExeHeader.NumberOfRel); {Increment number of relocations}

        If Ct > BuffSize Then Break; {If we've reached the end of the buffer... exit loop.}
       End;
      {End; uncomment here}
    End;
    BlockWrite (TmpFile, Buff1, Ct, Written); {Write block of data from File1 to TmpFile}
    If Written <> Ct Then Error (11,CodeFileName); {If there was an error writing to TmpFile...}
  Until Got <> BuffSize; {Until we've reached the end of both files...}

  WriteLn('þ Write zero data'); {Write a message to the console}
  Got := 0;
  While FilePos (OutFile) MOD 16 <> 0 Do Begin {While position in output file is not divisible by 16...}
    BlockWrite (OutFile, Got, 1, Written); {Write a zero byte to output file. This is padding.}

    If Written <> 1 Then Error (10, NewName); {If there was an error writing to}
  End;
  ExeHeader.HeaderSizeInP := FilePos (OutFile) DIV 16;

  Close (TmpFile);
  Reset (TmpFile,1);
  WriteLn('þ Write code');
  Repeat
    BlockRead  (TmpFile, Buff1, BuffSize, Got);
    If Got <> 0 Then BlockWrite (OutFile, Buff1, Got, Written);
    {If Got <> Written Then Error (10, NewName);}
  Until Got = 0;
  Close (OutFile);

  FPos := SizeOfFile (NewName);

  ExeHeader.ByteOnLastPage := SizeOfFile (NewName) MOD $200;
  ExeHeader.FileSizeDIV512 := SizeOfFile (NewName) DIV $200;
  If ExeHeader.ByteOnLastPage <> 0 Then Inc (ExeHeader.FileSizeDIV512);

{  OOOOOOH !!!! If (ExeHeader.NumberOfRel = $FFFF) Then ExeHeader.NumberOfRel := 0; {Because of none found !!}
  WriteLn('þ Write new header');
  Reset (OutFile, 1);
  BlockWrite (OutFile, ExeHeader, SizeOf (ExeHeaderType), Written);
  If Written <> SizeOf (ExeHeaderType) Then Error (10,NewName);

  If ExeHeaderOrg.ByteOnLastPage <> 0 Then Dec (ExeHeaderOrg.FileSizeDIV512);
  OrgExeFileSize := (ExeHeaderOrg.FileSizeDIV512 * $200 + ExeHeaderOrg.ByteOnLastPage);
  If (OrgExeFileSize <> SizeOfFile(OrgName)) AND DoOverLay Then Begin
    TextColor(LightRed);
    WriteLn('þ Write overlay. Use /no if you want to skip it.');
    TextColor(White);
    Seek(ExeFile, OrgExeFileSize);
    Seek(OutFile, FPos);
    Repeat
      BlockRead (ExeFile, Buff1, BuffSize, Got);
      BlockWrite (OutFile, Buff1, Got, Written);
    Until Written <> BuffSize;
  End;
  WriteLn ('þ Number of relocations ',d2h(ExeHeader.NumberOfRel,4),'h');
  If (ExeHeader.NumberOfRel = 0) Then Begin
    TextColor(LightRed);
    WriteLn ('WARNING : There are no relocations, it looks like somthing went wrong.');
    WriteLn ('          Try to start all over again with DUMPEXE.');
    WriteLn ('          If you still don''t get any relocations, it might be right !.');
    TextColor(White);
  End;
End;

Procedure MakeTheExe;
Var
  Written  ,
  IdStr    : Word;

Begin
  TextColor (White);
  FSplit (ParamStr(1), TheDir, TheName, TheExt);

  If TheExt <> '' Then
    OrgName := TheDir + TheName + TheExt
  Else
    OrgName := TheDir + TheName + '.EXE';
  Dump1Name := TheDir + TheName + '.1';
  Dump2Name := TheDir + TheName + '.2';
  NewName   := ParamStr(2);

  OrgName   := UpStr (OrgName);
  Dump1Name := UpStr (Dump1Name);
  Dump2Name := UpStr (Dump2Name);
  NewName   := UpStr (NewName);

  If NOT FileExist (Dump1Name) Then Begin
    If FileExist (TheDir + '#NONAME#.1') Then
      Dump1Name := TheDir + '#NONAME#.1'
    Else
      Error (5, Dump1Name);
  End;
  If NOT FileExist (Dump2Name) Then Begin
    If FileExist (TheDir + '#NONAME#.2') Then
      Dump2Name := TheDir + '#NONAME#.2'
    Else
      Error (5, Dump2Name);
  End;

  If SizeOfFile (Dump1Name) <> SizeOfFile(Dump2Name) Then Error (15,'');

  TextColor (LightGreen);
  WriteLn ('Unpacking ',OrgName,' into ', NewName);
  TextColor (White);
  WriteLn;
  WriteLn ('þ Read dump info');
  Assign (File1, Dump1Name);
  Reset  (File1, 1);
  If IOResult <> 0 Then Error (1,Dump1Name);
  BlockRead (File1, IdStr, SizeOf (IdStr));
  If IDStr <> DumpID Then Error (14,Dump1Name);
  BlockRead (File1, ExeInfo[1], SizeOf (ExeInfoRecType), Written);
  If Written <> SizeOf(ExeInfoRecType) Then Error (3,Dump1Name);

  IdStr := 0;
  Assign (File2, Dump2Name);
  Reset  (File2, 1);
  If IOResult <> 0 Then Error (2,Dump2Name);
  BlockRead (File2, IdStr, SizeOf (IdStr));
  If IDStr <> DumpID Then Error (14,Dump2Name);
  BlockRead (File2, ExeInfo[2], SizeOf (ExeInfoRecType), Written);
  If Written <> SizeOf(ExeInfoRecType) Then Error (4,Dump2Name);

  WriteLn('þ Read exe info');
  If NOT FileExist (OrgName) Then Error (8,OrgName);
  FileMode := 0;
  Assign (ExeFile, OrgName);
  Reset (ExeFile, 1);
  FileMode := 2;
  BlockRead (ExeFile, ExeHeader, SizeOf (ExeHeaderType), Written);
  If Written <> SizeOf(ExeHeaderType) Then Error (9,OrgName);
  Move (ExeHeader, ExeHeaderOrg, SizeOf(ExeHeaderType));

  With ExeHeader Do Begin
    SP             := ExeInfo[1].SP;
    IP             := ExeInfo[1].IP;
    SS             := ExeInfo[1].SS - (ExeInfo[1].PSP + $10);
    CS             := ExeInfo[1].CS - (ExeInfo[1].PSP + $10);
    RelocTabel     := SizeOf (ExeheaderType);
    MyIdString     := IDString;
    MyIdString[0]  := 'E';        {He he}

    ByteOnLastPage := $FFFF; { Changed later }
    FileSizeDIV512 := $FFFF; { Changed later }
{   OOOOH BUG BUG MakeExe has ALWAYS been one reloc short !!!}
{    NumberOfRel    := $FFFF; { Changed later }
    NumberOfRel    := $0   ; { Changed later }
    HeaderSizeInP  := $FFFF; { Changed later }
  End;

  WriteLn('þ Create new file');
  Assign (OutFile, NewName);
  ReWrite (OutFile, 1);
  If IOResult <> 0 Then Error (7, NewName);
  BlockWrite (OutFile, ExeHeader, SizeOf (ExeHeaderType), Written);
  If Written <> SizeOf (ExeHeaderType) Then Error (10, NewName);

  WriteLn('þ Create tempfile');
  Assign (TmpFile, CodeFileName);
  ReWrite (TmpFile, 1);
  If IOResult <> 0 Then Error (12, CodeFileName);

  FindReloc;
  WriteLn;
  WriteLn ('All done!');
  CleanUp;
End;

Procedure WriteHelpScr;
Begin
  TextColor(LightGreen);
  Write   ('Usage : ');
  TextColor(LightCyan);
  WriteLn ('MAKEEXE ExeFile OutFile [/no]');
  WriteLn;
  TextColor(White);
  WriteLn ('        ExeFile  Name of the original exefile.');
  WriteLn ('        OutFile  Name of the new exefile.');
  WriteLn ('        /no      If any overlay found, don''t copy it');
  WriteLn;
  WriteLn ('ExeFile will be used to demind name and location of the dumpfiles.');
  WriteLn ('Dumpfiles are searched as ExeFile.[1,2] and then #NoName#.[1,2]');
  LastInitText;
  Halt(1);
End;

Procedure DoParam;
Var
  Ct : Byte;
  InStr : String;

Begin
  InStr := '';
  If (ParamCount >= 2) AND (ParamCount <= 3) Then Begin
    If ParamCount > 2 Then Begin
      For Ct := 3 TO ParamCount Do InStr := InStr + UpStr(ParamStr(Ct));
      If Pos ('/NO',InStr) <> 0 Then Begin
        DoOverlay := False;
        Delete (InStr, Pos ('/NO',InStr), 3);
      End;
      If InStr <> '' Then WriteHelpScr;
    End Else
      If UpStr(ParamStr(2)) = '/NO'Then WriteHelpScr;

    MakeTheExe;
  End Else
    WriteHelpScr;
End;

Begin
  Clrscr;
  WriteTitleText(2);
  WriteLn;
  DoParam;
End.
