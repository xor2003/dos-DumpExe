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
  IDString      = 'DumpExe V.' + Version;
  CodeFileName  = 'Code.$$$';
  DoOverlay     : Boolean = True;
  DoRename      : Boolean = True;
  DoOverWrite   : Boolean = False;

Type
  ExeHeaderType = Record
    ExeSign        ,
    ByteOnLastPage ,
    FileSizeDIV512 ,
    NumberOfRel    ,
    HeaderSizeInP  ,
    MinMemInP      ,
    MaxMemInP      ,
    SS             ,
    SP             ,
    ChkSum         ,
    IP             ,
    CS             ,
    RelocTabel     ,
    Overlay        : Word;
    MyIdString     : String [Length (IDString)];
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
  Ch : Char;

Begin
  Write (TextStr);
  Repeat
    Ch := UpCase (ReadKey);
  Until Pos (Ch, Legal) <> 0;
  WriteLn (Ch);
  Ask := Ch;
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
  Ct             ,   { Counter used for iterating over the buffer. }
  Diff           ,   { Difference between corresponding bytes in the two files. }
  Got            : Word;  { Stores the number of bytes read by BlockRead. }
  Written        : Integer;  { Stores the number of bytes written by BlockWrite. }
  FPos           ,  { Keeps track of the current file position. }
  Relocation     : LongInt;  { Stores the calculated relocation offset. }
  OrgExeFileSize : LongInt;  { Stores the original size of the executable file. }
  TempStr        : String;  { Temporary string variable. }
  RmFile         : File;  { File handle for an output file. }

Begin
  FPos      := 0;  { Initialize file position to zero. }
  Diff      := 0;  { Initialize difference to zero. }

  WriteLn('� Write relocations');  { Output a message indicating relocation is being written. }
  Repeat
    BlockRead (File1, Buff1, BuffSize, Got);  { Read a block of data from File1 into Buff1. }
    BlockRead (File2, Buff2, Got, Got);  { Read the same number of bytes from File2 into Buff2. }
    For Ct := 1 To Got Do Begin  { Loop through each byte in the buffers. }
      Inc (FPos);  { Increment the file position. }
      If Buff1[Ct] <> Buff2[Ct] Then Begin  { If the current byte in the two buffers is different... }
        If Ct = Got Then Begin  { If we are at the last byte of the buffer... }
          BlockRead (File1, Buff1[ct+1], 1);  { Read the next byte from File1. }
          BlockRead (File2, Buff2[ct+1], 1);  { Read the next byte from File2. }
        End;

        If Diff = 0 Then Diff := Word(Addr (Buff2[Ct])^) - Word(Addr (Buff1[Ct])^);  
        { If this is the first difference found, calculate and store the difference. }

        If Diff <> 1937 Then Begin
          Continue;
        End;
        {WriteLn(Diff);   Output the current difference. }

        { If Diff is not 4096, skip the rest of the loop. (This line is commented out) }
        Word(Addr (Buff1[Ct])^) := Word(Addr (Buff1[Ct])^) - (ExeInfo[1].PSP + $10);  
        { Adjust the value at Buff1[Ct] by subtracting the program segment prefix and offset. }

        Relocation := FPos-1; {MUST be done like this !}  
        { Store the relocation position as the current file position minus one. }

        Relocation := (Relocation SHR 16 SHL 28) + (Relocation SHL 16 SHR 16);  
        { Shift the relocation value to the required format. }

        BlockWrite (OutFile, Byte(Relocation), SizeOf (Relocation), Written);  
        { Write the relocation value to the output file. }

        If Written <> SizeOf (Relocation) Then Error (10, NewName);  
        { If the number of bytes written is incorrect, output an error with code 10. }

        Inc (Ct);  { Increment the counter. }
        Inc (FPos);  { Increment the file position. }
        Inc (ExeHeader.NumberOfRel);  { Increment the number of relocations in the header. }

        If Ct > BuffSize Then  { If the counter exceeds the buffer size... }
          Break;  { Exit the loop. }
      End;
    End;
    BlockWrite (TmpFile, Buff1, Ct, Written);  { Write the buffer contents to a temporary file. }

    If Written <> Ct Then Error (11,CodeFileName);  
    { If the number of bytes written is not as expected, output an error with code 11. }

  Until Got <> BuffSize;  
  { Repeat the process until fewer bytes than BuffSize are read (end of file). }

  WriteLn('� Write zero data');
  Got := 0;
  While FilePos (OutFile) MOD 16 <> 0 Do Begin
    BlockWrite (OutFile, Got, 1, Written);
    If Written <> 1 Then Error (10, NewName);
  End;
  ExeHeader.HeaderSizeInP := FilePos (OutFile) DIV 16;

  Close (TmpFile);
  Reset (TmpFile,1);
  WriteLn('� Write code');
  Repeat
    BlockRead  (TmpFile, Buff1, BuffSize, Got);
    BlockWrite (OutFile, Buff1, Got, Written);
    If Got <> Written Then Error (10, NewName);
  Until Written <> BuffSize;
  Close (OutFile);

  FPos := SizeOfFile (NewName);

  ExeHeader.ByteOnLastPage := SizeOfFile (NewName) MOD $200;
  ExeHeader.FileSizeDIV512 := SizeOfFile (NewName) DIV $200;
  If ExeHeader.ByteOnLastPage <> 0 Then Inc (ExeHeader.FileSizeDIV512);

{  OOOOOOH !!!! If (ExeHeader.NumberOfRel = $FFFF) Then ExeHeader.NumberOfRel := 0; {Because of none found !!}
  WriteLn('� Write new header');
  Reset (OutFile, 1);
  BlockWrite (OutFile, ExeHeader, SizeOf (ExeHeaderType), Written);
  If Written <> SizeOf (ExeHeaderType) Then Error (10,NewName);

  If ExeHeaderOrg.ByteOnLastPage <> 0 Then Dec (ExeHeaderOrg.FileSizeDIV512);
  OrgExeFileSize := (ExeHeaderOrg.FileSizeDIV512 * $200 + ExeHeaderOrg.ByteOnLastPage);
  If (OrgExeFileSize <> SizeOfFile(OrgName)) AND DoOverLay Then Begin
    TextColor(LightRed);
    WriteLn('� Write overlay. Use /no if you want to skip it.');
    TextColor(White);
    Seek(ExeFile, OrgExeFileSize);
    Seek(OutFile, FPos);
    Repeat
      BlockRead (ExeFile, Buff1, BuffSize, Got);
      BlockWrite (OutFile Buff1, Got, Written);
    Until Written <> BuffSize;
  End;
  WriteLn ('� Number of relocations ',d2h(ExeHeader.NumberOfRel,4),'h');
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
  WriteLn ('� Read dump info');
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

  WriteLn('� Read exe info');
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

  WriteLn('� Create new file');
  Assign (OutFile, NewName);
  ReWrite (OutFile, 1);
  If IOResult <> 0 Then Error (7, NewName);
  BlockWrite (OutFile, ExeHeader, SizeOf (ExeHeaderType), Written);
  If Written <> SizeOf (ExeHeaderType) Then Error (10, NewName);

  WriteLn('� Create tempfile');
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
