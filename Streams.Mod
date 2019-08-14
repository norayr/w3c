MODULE W3cStreams;

(* This module provides character stream readers and writers as abstractions for storage media and encodings. *)

IMPORT Files, Strings;

CONST
	CR = 0DX; LF = 0AX;
	
TYPE
	Reader* = POINTER TO ABSTRACT RECORD
		ok*: BOOLEAN; (* sticky if FALSE; reading beyond end-of-stream sets ok to FALSE but GetError() returns NIL *)
	END;

	Writer* = POINTER TO ABSTRACT RECORD
		ok*: BOOLEAN;
	END;

	String* = POINTER TO ARRAY OF CHAR;

	Utf8FileReader* = POINTER TO EXTENSIBLE RECORD (Reader)
		rd: Files.Reader;
		errMsg: String;
	END;

	Utf8FileWriter* = POINTER TO EXTENSIBLE RECORD (Writer)
		wr: Files.Writer;
		errMsg: String;
	END;

	StringReader* = POINTER TO EXTENSIBLE RECORD (Reader)
		source: String;
		pos: INTEGER;
	END;

	StringWriter* = POINTER TO EXTENSIBLE RECORD (Writer)
		buf-: String;
		len-: INTEGER;
	END;

	SString* = POINTER TO ARRAY OF SHORTCHAR;

	SStringReader* = POINTER TO EXTENSIBLE RECORD (Reader)
		source: SString;
		pos: INTEGER;
	END;

	SStringWriter* = POINTER TO EXTENSIBLE RECORD (Writer)
		buf-: SString;
		len-: INTEGER;
	END;


(* ------ Reader ------ *)

(** provides a clear text message if an error was detected; otherwise returns NIL; 
	end-of-stream is not considered an error.
*)
PROCEDURE (this: Reader) GetError* (): String, NEW, EXTENSIBLE;
BEGIN
	RETURN NIL
END GetError;

(** returns the next character and sets this.ok to FALSE if not successfull;
	at end-of-stream this.ok is also set to FALSE and 0X is returned.
	GetError provides a clear text message if an error was detected.
*)
PROCEDURE (this: Reader) Get* (): CHAR, NEW, ABSTRACT;


(* ------ Writer ------ *)

(** provides a clear text message if an error was detected; otherwise returns NIL.
*)
PROCEDURE (this: Writer) GetError* (): String, NEW, EXTENSIBLE;
BEGIN
	RETURN NIL
END GetError;

PROCEDURE (this: Writer) Char* (ch: CHAR), NEW, ABSTRACT;

PROCEDURE (this: Writer) String* (IN str: ARRAY OF CHAR), NEW, EXTENSIBLE;
	VAR i: INTEGER; ch: CHAR;
BEGIN
	i := 0; ch := str[0];
	WHILE ch # 0X DO this.Char(ch); INC(i); ch := str[i] END
END String;

PROCEDURE (this: Writer) Ln*, NEW, EXTENSIBLE;
BEGIN
	this.Char(CR); this.Char(LF)
END Ln;


(* ------ Utf8FileReader ------ *)

PROCEDURE (this: Utf8FileReader) Init* (rd: Files.Reader), NEW, EXTENSIBLE;
BEGIN
	this.rd := rd; this.ok := TRUE; this.errMsg := NIL
END Init;

PROCEDURE (this: Utf8FileReader) Get* (): CHAR, EXTENSIBLE;
	VAR b: BYTE; ch: CHAR; val, i: INTEGER;
	
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

PROCEDURE (this: Utf8FileReader) GetError* (): String, EXTENSIBLE;
BEGIN
	RETURN this.errMsg
END GetError;


(* ------ Utf8FileWriter ------ *)

PROCEDURE (this: Utf8FileWriter) Init* (wr: Files.Writer), NEW, EXTENSIBLE;
BEGIN
	this.wr := wr; this.ok := TRUE; this.errMsg := NIL
END Init;

PROCEDURE (this: Utf8FileWriter) Char* (ch: CHAR), EXTENSIBLE;
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

PROCEDURE (this: StringReader) Init* (source: String; pos: INTEGER), NEW, EXTENSIBLE;
BEGIN
	this.source := source; this.pos := pos; this.ok := TRUE
END Init;

PROCEDURE (this: StringReader) Get* (): CHAR, EXTENSIBLE;
	VAR ch: CHAR;
BEGIN
	ch := this.source[this.pos];
	IF ch # 0X THEN INC(this.pos)
	ELSE this.ok := FALSE
	END;
	RETURN ch
END Get;


(* ------ StringWriter ------ *)

PROCEDURE (this: StringWriter) Init* (buf: String; initialCapacity: INTEGER), NEW, EXTENSIBLE;
BEGIN
	IF buf # NIL THEN this.buf := buf ELSE NEW(this.buf, MAX(initialCapacity, 62)) END;
	this.len := 0; this.buf[0] := 0X; this.ok := TRUE
END Init;

PROCEDURE (this: StringWriter) Char* (ch: CHAR), EXTENSIBLE;
	VAR newBuf: String;
BEGIN
	IF this.len + 2 >= LEN(this.buf) THEN
		NEW(newBuf, LEN(this.buf) * 2); newBuf^ := this.buf^$; this.buf := newBuf
	END;
	this.buf[this.len] := ch;
	INC(this.len);
	this.buf[this.len] := 0X;
END Char;

PROCEDURE (this: StringWriter) Ln*, EXTENSIBLE;
BEGIN
	this.Char(CR)
END Ln;


(* ------ SStringReader ------ *)

PROCEDURE (this: SStringReader) Init* (source: SString; pos: INTEGER), NEW, EXTENSIBLE;
BEGIN
	this.source := source; this.pos := pos; this.ok := TRUE
END Init;

PROCEDURE (this: SStringReader) Get* (): CHAR, EXTENSIBLE;
	VAR ch: CHAR;
BEGIN
	ch := this.source[this.pos];
	IF ch # 0X THEN INC(this.pos)
	ELSE this.ok := FALSE
	END;
	RETURN ch
END Get;


(* ------ SStringWriter ------ *)

PROCEDURE (this: SStringWriter) Init* (buf: SString; initialCapacity: INTEGER), NEW, EXTENSIBLE;
BEGIN
	IF buf # NIL THEN this.buf := buf ELSE NEW(this.buf, MAX(initialCapacity, 124)) END;
	this.len := 0; this.buf[0] := 0X; this.ok := TRUE
END Init;

PROCEDURE (this: SStringWriter) Char* (ch: CHAR), EXTENSIBLE;
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

PROCEDURE (this: SStringWriter) Ln*, EXTENSIBLE;
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

PROCEDURE NewStringReader* (source: String; pos: INTEGER): StringReader;
	VAR r: StringReader;
BEGIN
	NEW(r); r.Init(source, pos); RETURN r
END NewStringReader;

PROCEDURE NewStringWriter* (buf: String; initialCapacity: INTEGER): StringWriter;
	VAR w: StringWriter;
BEGIN
	NEW(w); w.Init(buf, initialCapacity); RETURN w
END NewStringWriter;

PROCEDURE NewSStringReader* (source: SString; pos: INTEGER): SStringReader;
	VAR r: SStringReader;
BEGIN
	NEW(r); r.Init(source, pos); RETURN r
END NewSStringReader;

PROCEDURE NewSStringWriter* (buf: SString; initialCapacity: INTEGER): SStringWriter;
	VAR w: SStringWriter;
BEGIN
	NEW(w); w.Init(buf, initialCapacity); RETURN w
END NewSStringWriter;

END W3cStreams.