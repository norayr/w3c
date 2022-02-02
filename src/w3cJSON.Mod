MODULE w3cJSON;

(* This module provides a simple W3C standards conformant JSON parser and stringifier.
J. Templ, 2018-05-04 *)

IMPORT Out, Strings := oocStrings, IntStr := oocIntStr, RealStr := oocRealStr, (*Files, Log,*)
	ErrorHandlers := w3cErrorHandlers,
	Objects := w3cObjects,
	Streams := w3cStreams,
	DStrings := w3cDStrings;

CONST
	MimeType* = "application/json";
	
	(* String pooling settings *)
	StrKey* = 0; (* a good candidate for string pooling *)
	StrString* = 1;
	
	DefaultStringPooling* = {StrKey};

	(* scanner symbol types *)
	Eos = 0; BeginObj = 1; EndObj = 2; BeginArr = 3; EndArr = 4;
	ValSep = 5; NameSep = 6; False = 7; Null = 8; True = 9; NumVal = 10; StringVal = 11;
	Invalid = 12;
	
	(* escapable control characters *)
	BS = 08X; TAB = 09X; LF = 0AX; FF = 0CX; CR = 0DX;
	
	MaxNesting = 1000; (* for detection of cyclic structures and insane nesting *)

TYPE
	Value* = POINTER TO ValueDesc;
  ValueDesc = RECORD END;
	
	Literal* = POINTER TO LiteralDesc;
  LiteralDesc = RECORD (ValueDesc) END;
	
	Number* = POINTER TO NumberDesc;
  NumberDesc = RECORD (ValueDesc)
		isInt*: BOOLEAN;
		(*intVal*: HUGEINT;*)
		intVal*: LONGINT;
		realVal*: REAL
	END;
	
	String* = POINTER TO StringDesc;
  StringDesc = RECORD (ValueDesc)
		val*: DStrings.String
	END;
	
	Array* = POINTER TO ArrayDesc;
  ArrayDesc = RECORD (ValueDesc)
		elems*: Objects.Collection; (**<val:Value>*)
	END;
	
	Object* = POINTER TO ObjectDesc;
  ObjectDesc = RECORD (ValueDesc)
		entries*: Objects.Dictionary; (**<key:String, val:Value>*)
	END;

	ErrorHandler* = ErrorHandlers.ErrorHandler;

	Scanner = RECORD
		r: Streams.Reader;
		e: ErrorHandler;
		line, col, pos, startPos: LONGINT;
		nextCh: CHAR;
		sym: SHORTINT;
		isInt: BOOLEAN;
		dynstr: DStrings.DynamicString; (* key, string, literal *)
		(*intVal: HUGEINT;*)
		intVal: LONGINT;
		realVal: REAL;
		stringPool: DStrings.Pool;
		stringPooling: SET
	END;
	
	Parser* = POINTER TO ParserDesc;
  ParserDesc = RECORD
		errorHandler-: ErrorHandler;
		reader-: Streams.Reader;
		scanner: Scanner;
	END;

VAR
	false-, null-, true-: Literal; (* literal singletons, immutable *)


PROCEDURE Error(VAR s: Scanner; VAR msg: ARRAY OF CHAR);
BEGIN
	s.e.HandleError(s.startPos, s.line, s.col, msg);
	IF ~s.e.cont THEN s.nextCh := 0X; s.r.ok := FALSE END
END Error;

PROCEDURE NextCh(VAR s: Scanner);
	VAR ch: CHAR;
  tmpstr: Streams.String;
BEGIN
	IF ~s.r.ok THEN
    tmpstr := s.r.GetError();
		IF tmpstr # NIL THEN Error(s, tmpstr^) END;
		s.nextCh := 0X; s.sym := Eos
	ELSE
		ch := s.nextCh;
		IF (ch = CR) OR (ch = LF) THEN INC(s.line); s.col := 0;
		ELSE INC(s.col)
		END;
		s.nextCh := s.r.Get(); INC(s.pos);
		IF (ch = CR) & (s.nextCh = LF) THEN (* CR+LF detected *) DEC(s.line) END
	END
END NextCh;

PROCEDURE InitScanner(VAR s: Scanner; r: Streams.Reader; e: ErrorHandler);
BEGIN
	(*IF e = NIL THEN NEW(e); e.Init END;*) (* TODO: need to debug voc to understand what is going wrong:
  NEW(e) here compiles to 
   __NEW( *e, w3cJSON__1);
    which given an error during C compilation:
   w3cJSON.c:166:27: error: ‘w3cJSON__1__typ’ undeclared (first use in this function)
   had to 'invent' ErrorHandlers.Create() to do creation the old way.
 *)
	IF e = NIL THEN e := ErrorHandlers.Create(); e.Init END;
	s.r := r; s.e := e; s.line := 1; s.col := 0; s.pos := 0; s.startPos := 0;
	s.dynstr := DStrings.NewDynamicString(); NextCh(s); s.sym := Invalid;
	s.stringPool := NIL; s.stringPooling := {};
END InitScanner;

PROCEDURE SetStringPooling(VAR s: Scanner; stringPooling: SET);
BEGIN
	s.stringPooling := stringPooling;
	IF (stringPooling = {}) THEN
		s.stringPool := NIL;
	ELSIF (s.stringPool = NIL) THEN
		s.stringPool := DStrings.NewPool();
	END;
	ASSERT((s.stringPool = NIL) = (stringPooling = {}));
END SetStringPooling;

PROCEDURE ScanString(VAR s: Scanner);
	VAR hex4: ARRAY 6 OF CHAR; i, val: LONGINT; res: SHORTINT; ch: CHAR;
  errMsg, errMsg2, errMsg3: ARRAY 32 OF CHAR;
BEGIN
  COPY("invalid escape sequence", errMsg);
  COPY("unescaped control character", errMsg2);
  COPY("string not closed", errMsg3);
	ASSERT(s.nextCh = '"');
	NextCh(s);
	WHILE (s.nextCh # '"') & s.r.ok DO
		IF s.nextCh = "\" THEN (* escape sequence *)
			NextCh(s); ch := s.nextCh;
			IF ch = 'u' THEN
				FOR i := 0 TO 3 DO NextCh(s); hex4[i] := s.nextCh END;
				IF s.r.ok THEN
					hex4[4] := "H"; hex4[5] := 0X; 
          (*Strings.ToUpper(hex4, hex4);*)
          Strings.Capitalize(hex4);
					(*Strings.StringToInt(hex4, val, res);*)
          IntStr.StrToInt(hex4, val, res);
					IF res = 0 THEN s.dynstr.AppendChar(CHR(val))
					ELSE Error(s, errMsg)
					END
				ELSE Error(s, errMsg)
				END
			ELSIF ch = 'r' THEN
				s.dynstr.AppendChar(CR)
			ELSIF ch = 'n' THEN
				s.dynstr.AppendChar(LF)
			ELSIF (ch = '/') OR (ch = '\') OR (ch = '"') THEN 
				s.dynstr.AppendChar(ch)
			ELSIF ch = 't' THEN
				s.dynstr.AppendChar(TAB)
			ELSIF ch = 'b' THEN
				s.dynstr.AppendChar(BS)
			ELSIF ch = 'f' THEN
				s.dynstr.AppendChar(FF)
			ELSE
				Error(s, errMsg)
			END
		ELSIF s.nextCh >= " " THEN
			s.dynstr.AppendChar(s.nextCh)
		ELSE
			Error(s, errMsg2)
		END;
		NextCh(s)
	END;
	s.sym := StringVal;
	IF s.nextCh = '"' THEN NextCh(s) ELSE Error(s, errMsg3) END
END ScanString;

PROCEDURE ScanLiteral(VAR s: Scanner);
VAR
  strue, sfalse, snull: ARRAY 8 OF CHAR;
  sunkn: ARRAY 16 OF CHAR;
BEGIN
  COPY("true", strue); COPY("false", sfalse); COPY("null", snull);
  COPY("unknown literal", sunkn);
	WHILE (s.nextCh >= "a") & (s.nextCh <= "z") DO s.dynstr.AppendChar(s.nextCh); NextCh(s) END;
	IF s.dynstr.EqualsTo(strue, FALSE) THEN s.sym := True
	ELSIF s.dynstr.EqualsTo(sfalse, FALSE) THEN s.sym := False
	ELSIF s.dynstr.EqualsTo(snull, FALSE) THEN s.sym := Null
	ELSE s.sym := Invalid; Error(s, sunkn)
	END
END ScanLiteral;

PROCEDURE ScanNum(VAR s: Scanner);
	VAR numStr: ARRAY 256 OF CHAR; numLen: LONGINT; res: SHORTINT;
      numErr, numErr2: ARRAY 32 OF CHAR;	
	PROCEDURE Consume(VAR s: Scanner; ch: CHAR);
  VAR errMsg: ARRAY 16 OF CHAR;
	BEGIN
    COPY("number too long", errMsg);
		IF numLen < LEN(numStr) - 1 THEN numStr[numLen] := ch; INC(numLen)
		ELSE Error(s, errMsg)
		END;
		NextCh(s)
	END Consume;
	
	PROCEDURE ScanDigits(VAR s: Scanner);
  VAR errMsg: ARRAY 16 OF CHAR;
	BEGIN
    COPY("digit expected", errMsg);
		IF (s.nextCh >= "0") & (s.nextCh <= "9") THEN Consume(s, s.nextCh);
			WHILE (s.nextCh >= "0") & (s.nextCh <= "9") DO Consume(s, s.nextCh) END
		ELSE Error(s, errMsg)
		END
	END ScanDigits;
	
BEGIN
  COPY("number with leading zero", numErr);
  COPY("cannot convert number", numErr2);
	s.isInt := TRUE; numLen := 0;
	IF s.nextCh = "-" THEN Consume(s, "-") END;
	IF s.nextCh = "0" THEN Consume(s, "0");
		IF (s.nextCh >= "0") & (s.nextCh <= "9") THEN Error(s, numErr) END
	ELSE ScanDigits(s)
	END;
	IF s.nextCh = "." THEN s.isInt := FALSE; Consume(s, "."); ScanDigits(s) END;
	IF (s.nextCh = "e") OR (s.nextCh = "E") THEN s.isInt := FALSE; Consume(s, "E");
		IF (s.nextCh = "-") OR (s.nextCh = "+") THEN Consume(s, s.nextCh) END;
		ScanDigits(s)
	END;
	numStr[numLen] := 0X;
  (*IF s.isInt THEN Strings.StringToLInt(numStr, s.intVal, res); s.realVal := 0*)
  IF s.isInt THEN IntStr.StrToInt(numStr, s.intVal, res); s.realVal := 0
	ELSE RealStr.StrToReal(numStr, s.realVal, res); s.intVal := 0
	END;
	IF res # 0 THEN Error(s, numErr2) END;
	s.sym := NumVal
END ScanNum;

PROCEDURE Scan(VAR s: Scanner);
VAR
  tmpstr: Streams.String;
  errMsg, errMsg2: ARRAY 16 OF CHAR;
BEGIN
  COPY("invalid white space", errMsg);
  COPY("invalid symbol", errMsg2);
	s.dynstr.Clear();
	WHILE (s.nextCh # 0X) & (s.nextCh <= " ") DO 
		(*IF ~((ORD(s.nextCh)-1) VAR {ORD(TAB)-1, ORD(CR)-1, ORD(LF)-1, ORD(" ")-1}) THEN*)
		IF ~((ORD(s.nextCh)-1) = ORD(TAB)-1)
    OR ~((ORD(s.nextCh)-1) = ORD(CR)-1)
    OR ~((ORD(s.nextCh)-1) = ORD(LF)-1)
    OR ~((ORD(s.nextCh)-1) = ORD(" ")-1) THEN
			Error(s, errMsg)
		END;
		NextCh(s)
	END;
	s.startPos := s.pos - 1;
	IF s.r.ok THEN
		CASE s.nextCh OF
		| "{":
				s.sym := BeginObj; NextCh(s)
		| "}":
				s.sym := EndObj; NextCh(s)
		| "[":
				s.sym := BeginArr; NextCh(s)
		| "]":
				s.sym := EndArr; NextCh(s)
		| ":":
				s.sym := NameSep; NextCh(s)
		| ",":
				s.sym := ValSep; NextCh(s)
		| '"':
				ScanString(s)
		| "f", "n", "t":
				ScanLiteral(s)
		| "0".."9", "-":
				ScanNum(s)
		ELSE
				s.sym := Invalid; Error(s, errMsg2); NextCh(s)
		END
	ELSE
    tmpstr := s.r.GetError();
		IF tmpstr # NIL THEN Error(s, tmpstr^); s.sym := Invalid
		ELSE s.sym := Eos
		END
	END
END Scan;

PROCEDURE GetStr(VAR s: Scanner; type: LONGINT): DStrings.String;
BEGIN
	(*IF type VAR s.stringPooling THEN RETURN s.stringPool.Get(s.dynstr)*)
	IF type IN s.stringPooling THEN RETURN s.stringPool.Get(s.dynstr)
	ELSE RETURN s.dynstr.ToString()
	END
END GetStr;

PROCEDURE ParseVal(VAR s: Scanner; nesting: LONGINT): Value;
	VAR num: Number; str: String; obj: Object; key: DStrings.String; val: Value; arr: Array;
  errMsg: ARRAY 32 OF CHAR;
  errMsg2, errMsg3, errMsg4, errMsg5, errMsg6, errMsg7: ARRAY 16 OF CHAR;
BEGIN
  COPY("maximum nesting level exceeded", errMsg);
  COPY("':' expected", errMsg2);
  COPY("',' expected", errMsg3);
  COPY("key expected", errMsg4);
  COPY("'}' expected", errMsg5);
  COPY("value expected", errMsg6);
  COPY("']' expected", errMsg7);
	IF nesting = MaxNesting THEN Error(s, errMsg); s.sym := Eos; RETURN NIL END;
	CASE s.sym OF
	| False:
			Scan(s); val := false
	| Null:
			Scan(s); val := null
	| True:
			Scan(s); val := true
	| NumVal:
			NEW(num); num.isInt := s.isInt; num.intVal := s.intVal; num.realVal := s.realVal; Scan(s); val := num
	| StringVal:
			NEW(str); str.val := GetStr(s, StrString); Scan(s); val := str
	| BeginObj:
			NEW(obj); obj.entries := Objects.NewArrayDict();
			Scan(s);
			WHILE s.sym = StringVal DO 
				key := GetStr(s, StrKey);
				Scan(s);
				IF s.sym = NameSep THEN Scan(s) ELSE Error(s, errMsg2) END;
				val := ParseVal(s, nesting + 1);
				IF val # NIL THEN obj.entries.Remove(key^); obj.entries.Add(key^, val) (* the last key wins *) END;
				IF s.sym # EndObj THEN
					IF s.sym = ValSep THEN Scan(s) ELSE Error(s, errMsg3) END;
					IF s.sym = EndObj THEN Error(s, errMsg4) END;
				END
			END;
			IF s.sym = EndObj THEN Scan(s) ELSE Error(s, errMsg5) END;
			val := obj
	| BeginArr:
			NEW(arr); arr.elems := Objects.NewArrayCollection();
			Scan(s);
			(*WHILE ~(s.sym VAR {EndArr, EndObj, Eos, Invalid}) DO*)
			WHILE ~(s.sym IN {EndArr, EndObj, Eos, Invalid}) DO
				val := ParseVal(s, nesting + 1);
				IF val # NIL THEN arr.elems.Add(val) END;
				IF s.sym # EndArr THEN
					IF s.sym = ValSep THEN Scan(s) ELSE Error(s, errMsg3) END;
					IF s.sym = EndArr THEN Error(s, errMsg6) END;
				END
			END;
			IF s.sym = EndArr THEN Scan(s) ELSE Error(s, errMsg7) END;
			val := arr
	ELSE
			Error(s, errMsg6); Scan(s); val := NIL
	END;
	RETURN val
END ParseVal;

PROCEDURE (this: Parser) SetStringPooling* (stringPooling: SET)(*, NEW*);
BEGIN
	SetStringPooling(this.scanner, stringPooling)
END SetStringPooling;

PROCEDURE (this: Parser) Init*(r: Streams.Reader; e: ErrorHandler)(*, NEW*);
BEGIN
	InitScanner(this.scanner, r, e); (* default is without string pooling *)
	this.reader := r; this.errorHandler := this.scanner.e
END Init;

PROCEDURE (this: Parser) Parse* (): Value(*, NEW*);
	VAR val: Value;
    errMsg: ARRAY 32 OF CHAR;
BEGIN
  COPY("end-of-stream expected", errMsg);
	Scan(this.scanner);
	val := ParseVal(this.scanner, 0);
	IF this.scanner.sym # Eos THEN Error(this.scanner, errMsg) END;
	RETURN val
END Parse;

(** write JSON value to stream; outputs a single line if indent = "" *)

PROCEDURE Write*(val: Value; out: Streams.Writer; VAR indent: ARRAY OF CHAR);
	
	PROCEDURE WriteHex4(ch: CHAR);
		VAR hex4: ARRAY 5 OF CHAR;
      tmpstr: ARRAY 5 OF CHAR;
	BEGIN
    COPY("\u", tmpstr);
		(*Strings.IntToStringForm(ORD(ch), Strings.hexadecimal, 4, "0", Strings.hideBase, hex4);*)
    IntStr.IntToStr(ORD(ch), hex4);(*TODO this doesn't write hex, need to fix it *)
		out.String(tmpstr); out.String(hex4)
	END WriteHex4;
	
	PROCEDURE WriteStr(VAR s: ARRAY OF CHAR);
		VAR i: LONGINT; ch: CHAR;
    VAR sr, sn, st, sb, sf, sbr, sscrn: ARRAY 3 OF CHAR;
	BEGIN
    COPY("\r", sr); COPY("\n", sn); COPY("\t", st); COPY("\b", sb);
    COPY("\f", sf); COPY('\"', sbr); COPY("\\", sscrn);
		out.Char('"');
		i := 0; ch := s[0];
		WHILE ch # 0X DO
			IF (ch < " ") THEN
				IF ch = CR THEN out.String(sr)
				ELSIF ch = LF THEN out.String(sn)
				ELSIF ch = TAB THEN out.String(st)
				ELSIF ch = BS THEN out.String(sb)
				ELSIF ch = FF THEN out.String(sf)
				ELSE WriteHex4(ch)
				END
			ELSIF ch = '"' THEN out.String(sbr)
			ELSIF ch = '\' THEN out.String(sscrn)
			ELSIF ch < 80X THEN out.Char(ch)
			ELSE WriteHex4(ch)
			END;
			INC(i); ch := s[i]
		END;
		out.Char('"')
	END WriteStr;
	
	PROCEDURE WriteIndent(level: LONGINT);
		VAR i: LONGINT;
	BEGIN
		IF indent # "" THEN out.Char(CR);
			FOR i := 1 TO level DO out.String(indent) END
		END
	END WriteIndent;
	
	PROCEDURE WriteVal(x: Value; indentLevel: LONGINT);
		VAR de: Objects.DictEnumerator; it: Objects.Enumerator; next: Objects.ANYPTR; val: Value; key: DStrings.String;
			numStr: ARRAY 32 OF CHAR;
      sf, st, nl: ARRAY 6 OF CHAR;
	BEGIN
    COPY("false", sf); COPY("true", st); COPY("null", nl);
		ASSERT(indentLevel < MaxNesting, 20); (* cyclic values or insane nesting *)
		WITH x: Literal DO
				IF x = false THEN out.String(sf)
				ELSIF x = true THEN out.String(st)
				ELSE out.String(nl)
				END
		| x: Number DO
				IF x.isInt THEN
					(*Strings.IntToString(x.intVal, numStr);*)
          IntStr.IntToStr(x.intVal, numStr);
          out.String(numStr)
				ELSE
					(*IF (x.realVal = INF) OR (x.realVal = -INF) THEN out.String(nl)      
					ELSE *)
            (*Strings.RealToStringForm(x.realVal, 16, 1, 0, " ", numStr); out.String(numStr)*)
            RealStr.RealToStr(x.realVal, numStr);
				(*	END *) (* TODO won't always work correctly for REAL values. need to understand what the hell is INF in component pascal *)
				END
		| x: String DO
				WriteStr(x.val^)
		| x: Array DO
				out.Char('[');
				it := x.elems.GetEnumerator(); next := it.GetNext();
				WHILE next # NIL DO
					val := next(Value);
					WriteIndent(indentLevel);
					(*WriteVal(val , indentLevel + 1);*) (* TODO *)
					next := it.GetNext();
					IF next # NIL THEN out.Char(",") END
				END;
				WriteIndent(indentLevel);
				out.Char(']')
		| x: Object DO
				out.Char('{');
				de := x.entries.GetEnumerator(); next := de.GetNext();
				WHILE next # NIL DO
				(*	val := next(Value); key := de.GetKey(); TODO *)
					WriteIndent(indentLevel); WriteStr(key^); out.Char(":");
					IF indent # "" THEN out.Char(" ") END;
				(*	WriteVal(val, indentLevel + 1); TODO *)
					next := de.GetNext();
					IF next # NIL THEN out.Char(",") END
				END;
				WriteIndent(indentLevel);
				out.Char('}')
		END
	END WriteVal;
	
BEGIN
	WriteVal(val, 0)
END Write;

(** JavaScript style interface to Write; outputs a single line if indent = "" *)
(* TODO
PROCEDURE Stringify* (val: Value; VAR indent: ARRAY OF CHAR): DStrings.String;
	VAR out: Streams.StringWriter;
BEGIN
	out := Streams.NewStringWriter(NIL, 28);
	Write(val, out, indent);
	RETURN out.buf
END Stringify;
*)
PROCEDURE NewParser* (r: Streams.Reader; e: ErrorHandler): Parser;
	VAR p: Parser;
BEGIN
	NEW(p); p.Init(r, e);
	RETURN p
END NewParser;

PROCEDURE Parse*(VAR json: ARRAY OF CHAR): Value;
	VAR 
    r: Streams.Reader;
    s: Scanner; val: Value; res: LONGINT;
      errMsg: ARRAY 32 OF CHAR;
      str, str1: DStrings.String;
BEGIN
  COPY("end-of-stream expected", errMsg);
	(*r := Streams.NewStringReader(DStrings.NewString(json), 0);*)
	str := DStrings.NewString(json);
  r := Streams.NewStringReader(str, 0);
  InitScanner(s, r, NIL); Scan(s);
	val := ParseVal(s, 0);
	IF s.sym # Eos THEN Error(s, errMsg) END;
	IF s.e.nofErrors > 0 THEN
		(*Dialog.GetOK(s.e.errorLog.ToString(), "", "", "", {Dialog.ok}, res);*)
    (*str1 := s.e.errorLog.ToString();*)
    DStrings.toString(s.e.errorLog, str1);
    Out.String("Error: "); Out.String(str1^); Out.Ln;
		HALT(128) (* silent HALT *)
	END;
	RETURN val
END Parse;

(* 
PROCEDURE Test*;
	VAR val: Value; res: LONGINT;
BEGIN
	val := Parse('["3", "3", "3"]');
	Dialog.GetOK(Stringify(val, "  "), "", "", "", {Dialog.ok}, res);
END Test;
*)

(* for running the test suite at: https://github.com/nst/JSONTestSuite

PROCEDURE TestSuite*;
	VAR loc: Files.Locator; fileInfo: Files.FileInfo; f: Files.File;
		in: Streams.Reader; p: Parser; rd: Files.Reader; val: Value;
BEGIN
	loc := Files.dir.This("../JSONTestSuite/test_parsing");    (* << adapt path *)
	fileInfo := Files.dir.FileList(loc);
	WHILE fileInfo # NIL DO
		f := Files.dir.Old(loc, fileInfo.name, TRUE);
		rd := f.NewReader(NIL);
		in := Streams.NewUtf8FileReader(rd);
		Log.String(fileInfo.name); Log.Ln;
		p := NewParser(in, NIL);
		val := p.Parse();
		IF fileInfo.name[0] = "y" THEN
			ASSERT(p.errorHandler.nofErrors = 0)
		ELSIF fileInfo.name[0] = "n" THEN
			ASSERT(p.errorHandler.nofErrors > 0)
		ELSIF fileInfo.name[0] = "i" THEN
			Log.String("  accepted="); Log.Bool(p.errorHandler.nofErrors = 0); Log.Ln;
		ELSE
			Log.String("  unknown class"); Log.Ln;
		END;
		fileInfo := fileInfo.next
	END
END TestSuite;
*)

BEGIN
	NEW(false); NEW(null); NEW(true)
END w3cJSON.
