MODULE w3cStreams;

(* This module provides character stream readers and writers as abstractions for storage media and encodings. *)

IMPORT Files, Strings;

CONST
	CR = 0DX; LF = 0AX;
	
TYPE
	Reader* = POINTER TO RECORD
		ok*: BOOLEAN; (* sticky if FALSE; reading beyond end-of-stream sets ok to FALSE but GetError() returns NIL *)
	END;

	Writer* = POINTER TO RECORD
		ok*: BOOLEAN;
	END;

	String* = POINTER TO ARRAY OF CHAR;

	Utf8FileReader* = POINTER TO RECORD (Reader)
		rd: Files.Reader;
		errMsg: String;
	END;

	Utf8FileWriter* = POINTER TO RECORD (Writer)
		wr: Files.Writer;
		errMsg: String;
	END;

	StringReader* = POINTER TO RECORD (Reader)
		source: String;
		pos: LONGINT;
	END;

	StringWriter* = POINTER TO RECORD (Writer)
		buf-: String;
		len-: LONGINT;
	END;

	SString* = POINTER TO ARRAY OF SHORTCHAR;

	SStringReader* = POINTER TO RECORD (Reader)
		source: SString;
		pos: LONGINT;
	END;

	SStringWriter* = POINTER TO RECORD (Writer)
		buf-: SString;
		len-: LONGINT;
	END;


(* ------ Reader ------ *)

(** provides a clear text message if an error was detected; otherwise returns NIL; 
	end-of-stream is not considered an error.
*)
PROCEDURE (this: Reader) GetError* (): String;
BEGIN
	RETURN NIL
END GetError;

(** returns the next character and sets this.ok to FALSE if not successfull;
	at end-of-stream this.ok is also set to FALSE and 0X is returned.
	GetError provides a clear text message if an error was detected.
*)
PROCEDURE (this: Reader) Get* (): CHAR, ABSTRACT;


(* ------ Writer ------ *)

(** provides a clear text message if an error was detected; otherwise returns NIL.
*)
PROCEDURE (this: Writer) GetError* (): String;
BEGIN
	RETURN NIL
END GetError;

PROCEDURE (this: Writer) Char* (ch: CHAR), ABSTRACT;

PROCEDURE (this: Writer) String* (VAR str: ARRAY OF CHAR);
	VAR i: LONGINT; ch: CHAR;
BEGIN
	i := 0; ch := str[0];
	WHILE ch # 0X DO this.Char(ch); INC(i); ch := str[i] END
END String;

PROCEDURE (this: Writer) Ln*;
BEGIN
	this.Char(CR); this.Char(LF)
END Ln;


(* ------ Utf8FileReader ------ *)

PROCEDURE (this: Utf8FileReader) Init* (rd: Files.Reader);
BEGIN
	this.rd := rd; this.ok := TRUE; this.errMsg := NIL
END Init;

PROCEDURE (this: Utf8FileReader) Get* (): CHAR;
	VAR b: SHORTINT; ch: CHAR; val, i: LONGINT;
	
	PROCEDURE FormatError;
		CONST formatError = "UTF-8 format error";
	BEGIN
		this.ok := FALSE; NEW(this.errMsg, LEN(formatError) + 1); this.errMsg^:= formatError
	END FormatError;

BEGIN
	this.rd.ReadByte(b); ch := CHR(b MOD 256);
	IF this.rd.eof THEN
		this.ok := FALSE;
		RETURN 0X
	ELSIF ch < 80X THEN
		RETURN ch
	ELSE (* UTF-8 decoding *)
		IF ch < 0E0X THEN (* 2-byte code *)
			val := ORD(ch) - 192;
			IF val < 0 THEN FormatError; RETURN 0X END ;
			this.rd.ReadByte(b); ch := CHR(b MOD 256);
			val := val * 64 + ORD(ch) - 128;
			IF (ch < 80X) OR (ch >= 0E0X) THEN FormatError; RETURN 0X END ;
			RETURN CHR(val)
		ELSIF ch < 0F0X THEN (* 3-byte code *)
			val := ORD(ch) - 224;
			this.rd.ReadByte(b); ch := CHR(b MOD 256);
			val := val * 64 + ORD(ch) - 128;
			IF (ch < 80X) OR (ch >= 0E0X) THEN FormatError; RETURN 0X END ;
			this.rd.ReadByte(b); ch := CHR(b MOD 256);
			val := val * 64 + ORD(ch) - 128;
			IF (ch < 80X) OR (ch >= 0E0X) THEN FormatError; RETURN 0X END ;
			RETURN CHR(val)
		ELSIF ch < 0F8X THEN (* 4-byte code; cannot be represented as CHAR *)
			FOR i := 0 TO 2 DO
				this.rd.ReadByte(b); ch := CHR(b MOD 256);
				IF (ch < 80X) OR (ch >= 0E0X) THEN FormatError; RETURN 0X END ;
			END;
			RETURN 0313X (* place holder 'geta', shown as white square*)
		ELSE
			FormatError; RETURN 0X
		END
	END
END Get;

PROCEDURE (this: Utf8FileReader) GetError* (): String;
BEGIN
	RETURN this.errMsg
END GetError;


(* ------ Utf8FileWriter ------ *)

PROCEDURE (this: Utf8FileWriter) Init* (wr: Files.Writer);
BEGIN
	this.wr := wr; this.ok := TRUE; this.errMsg := NIL
END Init;

PROCEDURE (this: Utf8FileWriter) Char* (ch: CHAR);
BEGIN
	IF ORD(ch) < 128 THEN
		this.wr.WriteByte(SHORT(SHORT(ORD(ch))))
	ELSIF ORD(ch) < 2048 THEN
		this.wr.WriteByte(SHORT(SHORT(ORD(ch) DIV 64 + 192)));
		this.wr.WriteByte(SHORT(SHORT(ORD(ch) MOD 64 + 128)))
	ELSE
		this.wr.WriteByte(SHORT(SHORT(ORD(ch) DIV 4096 + 224)));
		this.wr.WriteByte(SHORT(SHORT(ORD(ch) DIV 64 MOD 64 + 128)));
		this.wr.WriteByte(SHORT(SHORT(ORD(ch) MOD 64 + 128)));
	END
END Char;


(* ------ StringReader ------ *)

PROCEDURE (this: StringReader) Init* (source: String; pos: LONGINT);
BEGIN
	this.source := source; this.pos := pos; this.ok := TRUE
END Init;

PROCEDURE (this: StringReader) Get* (): CHAR;
	VAR ch: CHAR;
BEGIN
	ch := this.source[this.pos];
	IF ch # 0X THEN INC(this.pos)
	ELSE this.ok := FALSE
	END;
	RETURN ch
END Get;


(* ------ StringWriter ------ *)

PROCEDURE (this: StringWriter) Init* (buf: String; initialCapacity: LONGINT);
BEGIN
	IF buf # NIL THEN this.buf := buf ELSE NEW(this.buf, MAX(initialCapacity, 62)) END;
	this.len := 0; this.buf[0] := 0X; this.ok := TRUE
END Init;

PROCEDURE (this: StringWriter) Char* (ch: CHAR);
	VAR newBuf: String;
BEGIN
	IF this.len + 2 >= LEN(this.buf) THEN
		NEW(newBuf, LEN(this.buf) * 2); newBuf^ := this.buf^$; this.buf := newBuf
	END;
	this.buf[this.len] := ch;
	INC(this.len);
	this.buf[this.len] := 0X;
END Char;

PROCEDURE (this: StringWriter) Ln*;
BEGIN
	this.Char(CR)
END Ln;


(* ------ SStringReader ------ *)

PROCEDURE (this: SStringReader) Init* (source: SString; pos: LONGINT);
BEGIN
	this.source := source; this.pos := pos; this.ok := TRUE
END Init;

PROCEDURE (this: SStringReader) Get* (): CHAR;
	VAR ch: CHAR;
BEGIN
	ch := this.source[this.pos];
	IF ch # 0X THEN INC(this.pos)
	ELSE this.ok := FALSE
	END;
	RETURN ch
END Get;


(* ------ SStringWriter ------ *)

PROCEDURE (this: SStringWriter) Init* (buf: SString; initialCapacity: LONGINT);
BEGIN
	IF buf # NIL THEN this.buf := buf ELSE NEW(this.buf, MAX(initialCapacity, 124)) END;
	this.len := 0; this.buf[0] := 0X; this.ok := TRUE
END Init;

PROCEDURE (this: SStringWriter) Char* (ch: CHAR);
	VAR newBuf: SString;
BEGIN
	IF this.len + 2 >= LEN(this.buf) THEN
		NEW(newBuf, LEN(this.buf) * 2); newBuf^ := this.buf^$; this.buf := newBuf
	END;
	IF ch > 0FFX THEN ch := "?" END;
	this.buf[this.len] := SHORT(ch);
	INC(this.len);
	this.buf[this.len] := 0X;
END Char;

PROCEDURE (this: SStringWriter) Ln*;
BEGIN
	this.Char(CR)
END Ln;


(* ------ constructor functions ------ *)

PROCEDURE NewUtf8FileReader* (rd: Files.Reader): Utf8FileReader;
	VAR r: Utf8FileReader;
BEGIN
	NEW(r); r.Init(rd); RETURN r
END NewUtf8FileReader;

PROCEDURE NewUtf8FileWriter* (wr: Files.Writer): Utf8FileWriter;
	VAR w: Utf8FileWriter;
BEGIN
	NEW(w); w.Init(wr); RETURN w
END NewUtf8FileWriter;

PROCEDURE NewStringReader* (source: String; pos: LONGINT): StringReader;
	VAR r: StringReader;
BEGIN
	NEW(r); r.Init(source, pos); RETURN r
END NewStringReader;

PROCEDURE NewStringWriter* (buf: String; initialCapacity: LONGINT): StringWriter;
	VAR w: StringWriter;
BEGIN
	NEW(w); w.Init(buf, initialCapacity); RETURN w
END NewStringWriter;

PROCEDURE NewSStringReader* (source: SString; pos: LONGINT): SStringReader;
	VAR r: SStringReader;
BEGIN
	NEW(r); r.Init(source, pos); RETURN r
END NewSStringReader;

PROCEDURE NewSStringWriter* (buf: SString; initialCapacity: LONGINT): SStringWriter;
	VAR w: SStringWriter;
BEGIN
	NEW(w); w.Init(buf, initialCapacity); RETURN w
END NewSStringWriter;

END w3cStreams.
