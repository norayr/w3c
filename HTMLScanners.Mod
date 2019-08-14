MODULE W3cHTMLScanners;

(* This module provides an HTML(4/5) parser with string pooling capability.

Original author: Simon L. Keel, (heavily based on swalthert's "XMLScanner").
Ported from A2 Oberon build 7648 to BlackBox Component Pascal, J. Templ, 2018-03-23.
*)

IMPORT Strings, Files,
	Streams := W3cStreams,
	DStrings := W3cDStrings,
	ErrorHandlers := W3cErrorHandlers;

CONST
	(** Scanner: Tokens *)
	Invalid* = -1;
	TagElemStartOpen* = 0;	(** '<' *)
	TagElemEndOpen* = 1;	(** '</' *)
	TagDeclOpen* = 2;	(** '<!NAME' *)
	TagClose* = 3;	(** '>' *)
	TagEmptyElemClose* = 4;	(** '/>' *)
	TagXMLDeclOpen* = 5;	(** '<?xml' *)
	TagPIOpen* = 6;	(** '<?', PITarget := GetStr() *)
	TagPIClose* = 7;	(** '?>' *)
	(*
	TagCondSectOpen* = 8;	(** '<![' *)
	TagCondSectClose* = 9;	(** ']]>' *)
	*)
	Comment* = 14;	(** '<!--' chars '-->', chars := GetStr() *)
	(*
	CDataSect* = 15;	(** '<![CDATA[' chars ']]>', chars := GetStr() *)
	CharRef* = 16;	(** '&#' number ';' or '&#x' hexnumber ';', number, hexnumber := GetStr() *)
	EntityRef* = 17;	(** '&' name ';', name := GetStr() *)
	ParamEntityRef* = 18;	(** '%' name ';', name := GetStr() *)
	*)
	CharData* = 19;	(** chars := GetStr() *)
	Literal* = 20;	(** '"'chars'"' or "'"chars"'", chars := GetStr() *)
	Name* = 21;	(** Name ::= (Letter | '_' | ':') {NameChar}
								NameChar ::= Letter | Digit | '.' | '-' | '_' | ':' | CombiningChar | Extender
								chars := GetStr() *)
	Nmtoken* = 22;	(**	Nmtoken ::= NameChar {NameChar}, chars := GetStr() *)
	(*
	PoundName* = 23;	(** '#'name, name := GetStr() *)
	Question* = 24;	(** '?' *)
	Asterisk* = 25;	(** '*' *)
	Plus* = 26;	(** '+' *)
	Or* = 27;	(** '|' *)
	Comma* = 28;	(** ',' *)
	Percent* = 29;	(** '%' *)
	*)
	Equal* = 30;	(** '=' *)
	Eof* = 31; (* end of file *)
	
	LF = 0AX;
	CR = 0DX;
	APOS = "'"; (* single quote *)
	QUOT = '"'; (* double quote *)

TYPE
	Scanner* = POINTER TO EXTENSIBLE RECORD
		r-: Streams.Reader;
		errorHandler-: ErrorHandler;
		sym-: BYTE;	(** current token *)
		line-, col-, oldpos, pos: INTEGER;
		nextCh: CHAR;	(* look-ahead *)
		dynstr: DStrings.DynamicString;	(* buffer for CharData, Literal, Name, etc. *)
		stringPool: DStrings.Pool;
		stringPooling: SET;
		entityMap: Files.Reader;
	END;
	
	ErrorHandler* = ErrorHandlers.ErrorHandler;
	
	String = DStrings.String;

PROCEDURE IsWhiteSpace(ch: CHAR): BOOLEAN;
BEGIN
	RETURN (ch = 020X) OR (ch = 9X) OR (ch = 0DX) OR (ch = 0AX)
END IsWhiteSpace;

PROCEDURE (this: Scanner) GetStr*(type: INTEGER): String, NEW;
BEGIN
	IF type IN this.stringPooling THEN RETURN this.stringPool.Get(this.dynstr)
	ELSE RETURN this.dynstr.ToString()
	END
END GetStr;

PROCEDURE (this: Scanner) GetStrUpper*(type: INTEGER): String, NEW;
BEGIN
	this.dynstr.ToUpper();
	RETURN this.GetStr(type)
END GetStrUpper;

PROCEDURE (this: Scanner) GetStrLower*(type: INTEGER): String, NEW;
BEGIN
	this.dynstr.ToLower();
	RETURN this.GetStr(type)
END GetStrLower;

PROCEDURE (this: Scanner) GetPos*(): INTEGER, NEW;
BEGIN
	RETURN this.pos - 1
END GetPos;

PROCEDURE (this: Scanner) GetOldPos*(): INTEGER, NEW;
BEGIN
	RETURN this.oldpos
END GetOldPos;

PROCEDURE (this: Scanner) Error(IN msg: ARRAY OF CHAR), NEW;
BEGIN
	this.sym := Invalid;
	this.errorHandler.HandleError(this.GetPos(), this.line, this.col, msg);
	IF ~this.errorHandler.cont THEN this.nextCh := 0X; this.r.ok := FALSE END;
END Error;

(* JT, some fixes applied; handles also CR+LF *)
PROCEDURE (this: Scanner) NextCh, NEW;
	VAR ch: CHAR;
BEGIN
	IF ~this.r.ok THEN
		IF this.r.GetError() # NIL THEN this.Error(this.r.GetError()) END;
		this.nextCh := 0X; this.sym := Eof
	ELSE
		ch := this.nextCh;
		IF (ch = CR) OR (ch = LF) THEN INC(this.line); this.col := 0;
		ELSE INC(this.col)
		END;
		this.nextCh := this.r.Get(); INC(this.pos);
		IF (ch = CR) & (this.nextCh = LF) THEN (* CR+LF detected *) DEC(this.line) END
	END;
END NextCh;

(** constructor: Initialize scanner to read from the given character stream; e = NIL means default error handler*)
PROCEDURE (this: Scanner) Init*(r: Streams.Reader; e: ErrorHandler), NEW;
BEGIN
	ASSERT(r # NIL, 20);
	this.r := r;
	IF e # NIL THEN this.errorHandler := e ELSE NEW(this.errorHandler); this.errorHandler.Init END;
	this.dynstr := DStrings.NewDynamicString();
	this.stringPool := NIL; this.stringPooling := {}; this.entityMap := NIL;
	this.line := 1; this.pos := 0; this.col := 0;
	this.NextCh();
	(* remove byte order marker (bom) *) (* JT TODO unclear *)
	WHILE (this.r.ok) & (this.nextCh = 0EFX) OR (this.nextCh = 0BBX) OR (this.nextCh = 0BFX)
	OR (this.nextCh = 0FFX) OR (this.nextCh = 0FEX) OR (this.nextCh = 0X) DO
		this.NextCh();
	END;
END Init;

(* Named entities are used rarely because not all browsers support all of them.
	Therefore we assume that a simple  sequential file scan is sufficien. *)
PROCEDURE (this: Scanner) MapEntityName(ref: String): CHAR, NEW;
	VAR f: Files.File; pos, len, code, res: INTEGER;
		line, key, val: ARRAY 64 OF CHAR;
		
		PROCEDURE ReadLine(rd: Files.Reader; OUT line: ARRAY OF CHAR);
			VAR b: BYTE; i: INTEGER;
		BEGIN
			REPEAT rd.ReadByte(b) UNTIL (b >= ORD(" ")) OR rd.eof;
			line[0] := CHR(b); i := 1;
			REPEAT rd.ReadByte(b); line[i] := CHR(b); INC(i) UNTIL (b < ORD(" ")) OR rd.eof;
			line[i - 1] := 0X
		END ReadLine;
		
BEGIN
	IF this.entityMap = NIL THEN 
		f := Files.dir.Old(Files.dir.This("W3c/Rsrc"), "HTMLEntityMap.txt", TRUE);
		IF f # NIL THEN this.entityMap := f.NewReader(NIL) END
	END;
	IF this.entityMap # NIL THEN
		this.entityMap.SetPos(0); key := ref$ + ":"; (* key is case sensitive *)
		ReadLine(this.entityMap, line);
		WHILE ~this.entityMap.eof DO
			Strings.Find(line, key, 0, pos);
			IF pos = 0 THEN len := LEN(key$);
				Strings.Extract(line, len, 10, val); Strings.StringToInt(val, code, res);
				IF res = 0 THEN RETURN CHR(code) END
			END;
			ReadLine(this.entityMap, line);
		END
	END;
	RETURN 0X (* unknown entity name will be kept in text *)
END MapEntityName;

PROCEDURE (this: Scanner) AppendTillChar(ch: CHAR), NEW;
BEGIN
	WHILE (this.nextCh # ch) & (this.sym # Eof) DO
		this.dynstr.AppendChar(this.nextCh); this.NextCh()
	END;
	IF this.sym = Eof THEN this.sym := Invalid END
END AppendTillChar;

PROCEDURE (this: Scanner) DecodeAppendNext(), NEW;
	VAR len0, reflen, val, res: INTEGER; ref: String; ch: CHAR;
BEGIN
	this.dynstr.AppendChar(this.nextCh);
	IF this.nextCh = "&" THEN (* html encoded *)
		this.NextCh();
		IF this.nextCh <= " " THEN (* tolerate & followed by white space *)
			this.dynstr.AppendChar(this.nextCh); this.NextCh()
		ELSE
			len0 := this.dynstr.length;
			this.AppendTillChar(';');
			reflen := this.dynstr.length - len0;
			IF this.sym # Invalid THEN
				this.dynstr.Append(";");
				IF this.dynstr.Get(len0) = '#' THEN (* numeric code *)
					ch :=  this.dynstr.Get(len0 + 1);
					IF(ch = 'x') OR (ch = 'X') THEN (* hex *)
						ref := this.dynstr.Extract(len0 + 2, reflen - 2);
						Strings.ToUpper(ref, ref);
						Strings.StringToInt(ref + "H", val, res);
					ELSE (* decimal *)
						ref := this.dynstr.Extract(len0 + 1, reflen - 1);
						Strings.StringToInt(ref, val, res);
					END;
					IF res = 0 THEN ch := CHR(val)
					ELSE ch := 0X;
						this.Error("invalid number format in: '" + this.dynstr.Extract(len0 - 1, reflen + 2) + "'")
					END
				ELSE (*symbolic code *)
					ref := this.dynstr.Extract(len0, reflen);
					IF ref^ = 'amp' THEN ch := '&'
					ELSIF ref^ = 'lt' THEN ch := '<'
					ELSIF ref^ = 'gt' THEN ch := '>'
					ELSIF ref^ = 'apos' THEN ch := APOS
					ELSIF ref^ = 'quot' THEN ch := QUOT
					ELSIF ref^ = 'nbsp' THEN ch := 0A0X
					ELSIF ref^ = 'euro' THEN ch := 20ACX
					ELSE ch := this.MapEntityName(ref)
					END;
				END;
				IF ch # 0X THEN (* replace *) this.dynstr.Put(ch, len0 - 1); this.dynstr.Put(0X, len0) END;
				this.NextCh();
			END
		END
	ELSE (* raw data *)
		this.NextCh()
	END
END DecodeAppendNext;

PROCEDURE (this: Scanner) SkipWhiteSpaces, NEW;
BEGIN
	WHILE IsWhiteSpace(this.nextCh) & (this.sym # Eof) DO
		this.NextCh()
	END
END SkipWhiteSpaces;

(* Possible results:
		Name
		Nmtoken
		Invalid	*)
PROCEDURE (this: Scanner) ScanNm, NEW;
BEGIN
	this.dynstr.Clear;
	this.SkipWhiteSpaces();
	IF (('0' <= this.nextCh) & (this.nextCh <= '9')) OR (this.nextCh = '.') OR (this.nextCh = '-') THEN
		this.sym := Nmtoken
	ELSIF (('a' <= this.nextCh) & (this.nextCh <= 'z')) OR (('A' <= this.nextCh) & (this.nextCh <= 'Z')) 
	OR (this.nextCh = '_') OR (this.nextCh = ':') THEN
		this.sym := Name
	ELSE
		this.sym := Invalid; RETURN
	END;
	this.dynstr.AppendChar(this.nextCh);
	this.NextCh();
	WHILE ((('a' <= this.nextCh) & (this.nextCh <= 'z')) OR (('A' <= this.nextCh) & (this.nextCh <= 'Z')) 
	OR (('0' <= this.nextCh) & (this.nextCh <= '9')) 
	OR (this.nextCh = '.') OR (this.nextCh = '-') OR (this.nextCh = '_')
	OR (this.nextCh = ':')) & (this.sym # Eof) DO
		this.dynstr.AppendChar(this.nextCh); this.NextCh()
	END;
	IF this.sym = Eof THEN this.sym := Invalid END;
END ScanNm;

(* Scan Comment after comment open tag '<!--', write characters to this.dynstr.
		Possible results:
		Invalid
		Comment	*)
PROCEDURE (this: Scanner) ScanComment, NEW;
BEGIN
	this.dynstr.Clear;
	LOOP
		WHILE (this.nextCh # '-') & (this.sym # Eof) DO
			this.dynstr.AppendChar(this.nextCh); this.NextCh()
		END;
		IF this.nextCh = '-' THEN
			this.NextCh();
			IF this.nextCh = '-' THEN
				LOOP
					this.NextCh();
					IF this.nextCh = '>' THEN
						this.NextCh(); this.sym := Comment; RETURN
					ELSIF this.nextCh = '-' THEN
						this.dynstr.AppendChar('-');
					ELSE
						this.dynstr.Append('--');
						EXIT;
					END
				END;
			ELSE
				this.dynstr.AppendChar('-');
			END
		ELSE
			this.sym := Invalid; RETURN
		END
	END
END ScanComment;

(* Scan until tag '<tag >', write characters to this.dynstr.
		Possible results:
		Invalid
		CharData	*)
PROCEDURE (this: Scanner) ScanTo (IN tag: ARRAY OF CHAR), NEW;
	VAR i, len: INTEGER;
BEGIN
	this.dynstr.Clear;
	LOOP
		WHILE (this.nextCh # '<') & (this.sym # Eof) DO
			this.dynstr.AppendChar(this.nextCh); this.NextCh()
		END;
		IF this.nextCh = '<' THEN
			len := this.dynstr.length;
			this.dynstr.AppendChar(this.nextCh); this.NextCh(); i := 0;
			WHILE (tag[i] # 0X) & (tag[i] = Strings.Upper(this.nextCh)) DO
				this.dynstr.AppendChar(this.nextCh); this.NextCh();
				INC(i)
			END;
			IF tag[i] = 0X THEN
				WHILE (this.nextCh <= " ") & (this.sym # Eof) DO
					this.dynstr.AppendChar(this.nextCh); this.NextCh();
				END;
				IF (this.nextCh = '>') THEN
					this.NextCh();
					this.sym := CharData; (* JT, changed from Comment to CharData *)
					this.dynstr.Put(0X, len); (* truncate *)
					RETURN
				END
			END;
			this.dynstr.AppendChar(this.nextCh); this.NextCh()
		ELSE
			this.sym := Invalid;
			RETURN
		END
	END
END ScanTo;

(* Scan Script until close tag '</SCRIPT >', write characters to this.dynstr.
		Possible results:
		Invalid
		CharData	*)
PROCEDURE (this: Scanner) ScanSCRIPT*, NEW;
BEGIN
	this.ScanTo("/SCRIPT")
END ScanSCRIPT;

(* Scan Style until close tag '</STYLE >', write characters to this.dynstr.
		Possible results:
		Invalid
		CharData	*)
PROCEDURE (this: Scanner) ScanSTYLE*, NEW;
BEGIN
	this.ScanTo("/STYLE")
END ScanSTYLE;

(** possible results:
	Invalid
	TagPIClose
	CharData	*)
PROCEDURE (this: Scanner) ScanPInstruction*, NEW;
BEGIN
	IF this.sym = Eof THEN
		this.sym := Invalid;
		RETURN
	END;
	this.dynstr.Clear;
	LOOP
		WHILE (this.nextCh # '?') & (this.sym # Eof) DO
			this.dynstr.AppendChar(this.nextCh); this.NextCh()
		END;
		IF this.nextCh = '?' THEN
			this.NextCh();
			IF this.nextCh = '>' THEN
				this.sym := TagPIClose; this.NextCh(); RETURN
			ELSE
				this.dynstr.AppendChar('?')
			END
		ELSIF this.sym = Eof THEN
			this.sym := Invalid; RETURN
		ELSE
			this.sym := CharData; RETURN
		END
	END
END ScanPInstruction;

(** possible results:
	Invalid
	Eof
	Comment
	TagDeclOpen
	Name
	TagEmptyElemClose
	TagClose
	Nmtoken  *)
PROCEDURE (this: Scanner) ScanMarkup*, NEW;
	VAR ch: CHAR;
BEGIN
	this.SkipWhiteSpaces();
	this.oldpos := this.GetPos();
	IF this.sym = Eof THEN RETURN END;
	CASE this.nextCh OF
	| '<': this.NextCh();
			IF this.nextCh = '!' THEN	(* <! *)
				this.NextCh();
				IF this.nextCh = '-' THEN
					this.NextCh();
					IF this.nextCh = '-' THEN	(* <!-- *)
						this.NextCh();
						this.ScanComment()
					ELSE
						this.Error("'<!--' expected")
					END
				ELSE
					this.ScanNm();
					IF this.sym = Name THEN
						this.sym := TagDeclOpen
					ELSE
						this.Error("'<!NAME' expected")
					END
				END
			ELSIF this.nextCh = '?' THEN	(* <? *)
				this.NextCh();
				this.ScanNm();
				IF this.sym = Name THEN
					this.sym := TagPIOpen
				ELSE
					this.Error("'<?' Name expected")
				END
			ELSE
				this.Error("'<?' Name or '<!--' expected")
			END
	| '/': this.NextCh();
			IF this.nextCh = '>' THEN	(* /> *)
				this.NextCh(); this.sym := TagEmptyElemClose
			ELSE
				this.sym := Invalid
			END
	| '>': this.NextCh(); this.sym := TagClose
	| '?': this.NextCh();
			IF this.nextCh = '>' THEN	(* ?> *)
				this.NextCh();
				this.sym := TagPIClose
			ELSE
				this.sym := Invalid
			END
	| '=': this.NextCh(); this.sym := Equal
	| QUOT, APOS: ch := this.nextCh; this.NextCh(); this.dynstr.Clear; this.AppendTillChar(ch); this.NextCh();
			IF this.sym # Invalid THEN this.sym := Literal END;
	ELSE this.ScanNm()
	END
END ScanMarkup;

(** possible results:
	Invalid
	Eof
	TagElemEndOpen
	TagXMLDeclOpen
	Comment
	TagDeclOpen
	TagElemStartOpen
	CharData *)
PROCEDURE (this: Scanner) ScanContent*, NEW;
	VAR s: String;
BEGIN
	this.oldpos := this.GetPos();
	IF this.sym = Eof THEN this.nextCh := 0X END;
	CASE this.nextCh OF
	| 0X: this.sym := Eof
	| '<': this.NextCh();
		CASE this.nextCh OF
		| '/': this.sym := TagElemEndOpen; this.NextCh()
		| '?': this.NextCh(); this.ScanNm();
				IF (this.sym = Name) THEN
					s := this.dynstr.ToString(); Strings.ToLower(s^, s^);
					IF s^ = "xml" THEN
						this.sym := TagXMLDeclOpen
					ELSE
						this.Error("''<?xml' expected")
					END
				ELSE
					this.Error("''<?xml' expected")
				END
		| '!': this.NextCh();
				IF this.nextCh = '-' THEN
					this.NextCh();
					IF this.nextCh = '-' THEN
						this.NextCh(); this.ScanComment()
					ELSE
						this.Error("'<!--' expected")
					END
				ELSE
					this.ScanNm();
					IF  this.sym = Name THEN
						this.sym := TagDeclOpen
					ELSE
						this.Error("'<!xml' or '<!NAME' expected")
					END
				END
		ELSE
			this.sym := TagElemStartOpen
		END
	ELSE
		this.dynstr.Clear;
		REPEAT
			this.DecodeAppendNext();
		UNTIL (this.nextCh = '<') OR (this.sym = Eof);
		this.sym := CharData;
	END
END ScanContent;

(* like ScanMarkup but for HTML5 conforming attribute name syntax  
possible results:
	Invalid
	Eof
	Name
	TagEmptyElemClose
	TagClose
 *)
PROCEDURE (this: Scanner) ScanAttributeName*, NEW;
	VAR ch: CHAR;
BEGIN
	this.SkipWhiteSpaces();
	ch := this.nextCh;
	IF (ch = "=") OR (ch = ">") OR (ch = "?") OR (ch = "!") OR (ch = APOS) OR (ch = 0X) THEN this.ScanMarkup
	ELSE
		this.dynstr.Clear; this.dynstr.AppendChar(ch);
		this.NextCh(); ch := this.nextCh;
		WHILE (ch > " ") & ~((ch = "=") OR (ch = ">") OR (ch = "?") OR (ch = "!") OR (ch = APOS)) DO
			this.dynstr.AppendChar(ch);
			this.NextCh(); ch := this.nextCh
		END;
		this.sym := Name
	END
END ScanAttributeName;

PROCEDURE (this: Scanner) ScanAttributeValue*, NEW;
	VAR quote: CHAR;
BEGIN
	this.dynstr.Clear;
	this.SkipWhiteSpaces();
	IF (this.nextCh = QUOT) OR (this.nextCh = APOS) THEN
		quote := this.nextCh; this.NextCh();
		WHILE (this.nextCh # quote) & (this.sym # Eof) DO
			this.DecodeAppendNext();
		END;
		this.NextCh();
	ELSE
		WHILE ~IsWhiteSpace(this.nextCh) & (this.nextCh # '>') & (this.sym # Eof) DO
			this.DecodeAppendNext();
		END;
	END;
	IF this.sym # Eof THEN this.sym := Literal END;
END ScanAttributeValue;

PROCEDURE (this: Scanner) SetStringPooling*(stringPooling: SET), NEW;
BEGIN
	this.stringPooling := stringPooling;
	IF (stringPooling = {}) THEN
		this.stringPool := NIL;
	ELSIF (this.stringPool = NIL) THEN
		this.stringPool := DStrings.NewPool();
	END;
	ASSERT((this.stringPool = NIL) = (stringPooling = {}));
END SetStringPooling;

(** allocates and initializes a new scanner;
	e = NIL means to use the default (silent) error handler *)
PROCEDURE NewScanner*(r: Streams.Reader; e: ErrorHandler): Scanner;
	VAR s: Scanner;
BEGIN
	NEW(s); s.Init(r, e); RETURN s
END NewScanner;

END W3cHTMLScanners.
