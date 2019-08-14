MODULE W3cXMLScanners;

(* This module provides an XML scanner with string pooling capability.

Original author: Stefan Walthert (swalthert).
Ported from A2 Oberon build 7131 to BlackBox Component Pascal, J. Templ, 2017-05-10.
*)

IMPORT StdLog,
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
	TagCondSectOpen* = 8;	(** '<![' *)
	TagCondSectClose* = 9;	(** ']]>' *)
	BracketOpen* = 10;	(** '[' *)
	BracketClose* = 11;	(** ']' *)
	ParenOpen* = 12;	(** '(' *)
	ParenClose* = 13;	(** ')' *)
	Comment* = 14;	(** '<!--' chars '-->', chars := GetStr() *)
	CDataSect* = 15;	(** '<![CDATA[' chars ']]>', chars := GetStr() *)
	(*CharRef* = 16;	(** '&#' number ';' or '&#x' hexnumber ';', number, hexnumber := GetStr() *)
	EntityRef* = 17;	(** '&' name ';', name := GetStr() *)*)
	ParamEntityRef* = 18;	(** '%' name ';', name := GetStr() *)
	CharData* = 19;	(** chars := GetStr() *)
	Literal* = 20;	(** '"'chars'"' or "'"chars"'", chars := GetStr() *)
	Name* = 21;	(** 	Name ::= (Letter | '_' | ':') {NameChar}
										NameChar ::= Letter | Digit | '.' | '-' | '_' | ':' | CombiningChar | Extender
										chars := GetStr() *)
	Nmtoken* = 22;	(**	Nmtoken ::= NameChar {NameChar}, chars := GetStr() *)
	PoundName* = 23;	(** '#'name, name := GetStr() *)
	Question* = 24;	(** '?' *)
	Asterisk* = 25;	(** '*' *)
	Plus* = 26;	(** '+' *)
	Or* = 27;	(** '|' *)
	Comma* = 28;	(** ',' *)
	Percent* = 29;	(** '%' *)
	Equal* = 30;	(** '=' *)
	Eof* = 31;

	LF = 0AX;
	CR = 0DX;

TYPE
	Scanner* = POINTER TO EXTENSIBLE RECORD
		errorHandler-: ErrorHandler;
		sym-: INTEGER;	(** current token *)
		line-, col-, oldpos, pos: LONGINT;
		r-: Streams.Reader;
		nextCh: CHAR;	(* look-ahead *)
		dynstr: DStrings.DynamicString;	(* buffer for CharData, Literal, Name, CharRef, EntityRef, ParamEntityRef *)
		stringPool: DStrings.Pool;
		stringPooling: SET;
	END;
	
	ErrorHandler* = ErrorHandlers.ErrorHandler;

PROCEDURE^ (this: Scanner) NextCh, NEW;

(** Constructor; Initialize scanner to read from the given stream *)
PROCEDURE (this: Scanner) Init*(r: Streams.Reader; e: ErrorHandler), NEW;
BEGIN
	this.r := r;
	IF e # NIL THEN this.errorHandler := e ELSE NEW(this.errorHandler) END;
	this.dynstr := DStrings.NewDynamicString();
	this.line := 1; this.pos := 0; this.col := 0;
	this.stringPool := NIL;
	this.stringPooling := {};
	this.NextCh();
END Init;

PROCEDURE (this: Scanner) GetString*(type : LONGINT): DStrings.String, NEW;
	VAR string : DStrings.String;
BEGIN
	IF (type VAR this.stringPooling) THEN
		string := this.stringPool.Get(this.dynstr);
	ELSE
		string := this.dynstr.ToString();
	END;
	RETURN string;
END GetString;

PROCEDURE (this: Scanner) GetPos*(): LONGINT, NEW;
BEGIN
	RETURN this.pos - 1
END GetPos;

PROCEDURE (this: Scanner) GetOldPos*(): LONGINT, NEW;
BEGIN
	RETURN this.oldpos
END GetOldPos;

PROCEDURE (this: Scanner) Error(VAR msg: ARRAY OF CHAR), NEW;
BEGIN
	this.sym := Invalid;
	this.errorHandler.HandleError(this.GetPos(), this.line, this.col, msg);
	(* note: continuing after an error may lead into an infinite loop; not tested *)
	this.errorHandler.cont := FALSE;
	IF ~this.errorHandler.cont THEN this.nextCh := 0X; this.r.ok := FALSE END
END Error;

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

PROCEDURE (this: Scanner) ReadTillChar(ch: CHAR), NEW;
BEGIN
	this.dynstr.Clear;
	WHILE (this.nextCh # ch) & (this.sym # Eof) DO
		this.dynstr.AppendChar(this.nextCh);
		this.NextCh();
	END;
	IF this.sym = Eof THEN this.sym := Invalid END
END ReadTillChar;

PROCEDURE (this: Scanner) SkipWhiteSpaces, NEW;
	VAR ch: CHAR;
BEGIN
	ch := this.nextCh;
	WHILE ((ch = " ") OR (ch = 9X) OR (ch = CR) OR (ch = LF)) & (this.sym # Eof) DO
		this.NextCh(); ch := this.nextCh;
	END
END SkipWhiteSpaces;

PROCEDURE (this: Scanner) ScanPoundName, NEW;
BEGIN
	this.dynstr.Clear;
	this.dynstr.AppendChar(this.nextCh);
	this.NextCh();
	WHILE (('a' <= this.nextCh) & (this.nextCh <= 'z')) 
	OR (('A' <= this.nextCh) & (this.nextCh <= 'Z'))
	OR (('0' <= this.nextCh) & (this.nextCh <= '9'))
	OR (this.nextCh = '.')
	OR (this.nextCh = '-')
	OR (this.nextCh = '_')
	OR (this.nextCh = ':') DO
		this.dynstr.AppendChar(this.nextCh);
		this.NextCh();
	END;
	IF this.sym # Eof THEN this.sym := PoundName ELSE this.sym := Invalid END
END ScanPoundName;

(* Possible results:
		Name
		Nmtoken
		Invalid	*)
PROCEDURE (this: Scanner) ScanNm, NEW;
BEGIN
	this.SkipWhiteSpaces();
	IF (('0' <= this.nextCh) & (this.nextCh <= '9'))
	OR (this.nextCh = '.')
	OR (this.nextCh = '-') THEN
		this.sym := Nmtoken
	ELSIF (('a' <= this.nextCh) & (this.nextCh <= 'z'))
	OR (('A' <= this.nextCh) & (this.nextCh <= 'Z'))
	OR (this.nextCh = '_')
	OR (this.nextCh = ':') THEN
		this.sym := Name
	ELSE
		this.sym := Invalid; RETURN
	END;
	this.dynstr.Clear;
	this.dynstr.AppendChar(this.nextCh);
	this.NextCh();
	WHILE ((('a' <= this.nextCh) & (this.nextCh <= 'z'))
		OR (('A' <= this.nextCh) & (this.nextCh <= 'Z'))
		OR (('0' <= this.nextCh) & (this.nextCh <= '9'))
		OR (this.nextCh = '.')
		OR (this.nextCh = '-')
		OR (this.nextCh = '_')
		OR (this.nextCh = ':')) 
	& (this.sym # Eof) DO
		this.dynstr.AppendChar(this.nextCh);
		this.NextCh();
	END;
	IF this.sym = Eof THEN this.sym := Invalid END
END ScanNm;

(* Scan Comment after comment open tag '<!--', write characters to dynstr.
		Possible results:
		Invalid
		Comment	*)
PROCEDURE (this: Scanner) ScanComment, NEW;
BEGIN
	this.dynstr.Clear;
	LOOP
		WHILE (this.nextCh # '-') & (this.sym # Eof) DO
			this.dynstr.AppendChar(this.nextCh);
			this.NextCh()
		END;
		IF this.nextCh = '-' THEN
			this.NextCh();
			IF this.nextCh = '-' THEN
				this.NextCh();
				IF this.nextCh = '>' THEN
					this.NextCh(); this.sym := Comment; RETURN
				ELSE
					this.sym := Invalid; this.Error("'--' inside Comment"); RETURN
				END
			ELSE
				this.dynstr.AppendChar('-');
			END
		ELSE
			this.sym := Invalid; this.Error("unclosed Comment"); RETURN
		END
	END
END ScanComment;

(* Possible results:
		CharData
		TagCDataSectClose
		Invalid	*)
PROCEDURE (this: Scanner) ScanCDataSect, NEW;
	VAR bc: LONGINT; escape : BOOLEAN;
BEGIN
	IF this.sym = Eof THEN
		this.sym := Invalid;
		RETURN
	END;
	this.dynstr.Clear;
	LOOP
		WHILE (this.nextCh # ']') &  (this.sym # Eof) DO
			this.dynstr.AppendChar(this.nextCh);
			this.NextCh()
		END;
		IF this.nextCh = ']' THEN
			bc := 1; escape := FALSE; this.NextCh();
			WHILE this.nextCh = ']' DO
				INC(bc); this.NextCh();
				IF this.nextCh = '>' THEN
					this.NextCh(); escape := TRUE;
				END
			END;
			IF escape THEN
				WHILE (bc > 2) DO
					DEC(bc);
					this.dynstr.AppendChar(']');
				END;
				this.sym := CDataSect; RETURN
			ELSE
				WHILE (bc > 0) DO
					DEC(bc); this.dynstr.AppendChar(']');
				END;
			END;
		ELSE
			this.sym := CharData; RETURN
		END
	END
END ScanCDataSect;

(* possible results:
	Invalid
	ParamEntityRef *)
PROCEDURE (this: Scanner) ScanPEReference, NEW;
BEGIN
	this.ReadTillChar(';'); this.NextCh();
	IF this.sym # Invalid THEN this.sym := ParamEntityRef END
END ScanPEReference;

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
			this.dynstr.AppendChar(this.nextCh);
			this.NextCh();
		END;
		IF this.nextCh = '?' THEN
			this.NextCh();
			IF this.nextCh = '>' THEN
				this.sym := TagPIClose; this.NextCh(); RETURN
			ELSE
				this.dynstr.AppendChar('?');
			END
		ELSIF this.sym = Eof THEN
			this.sym := Invalid; RETURN
		ELSE
			this.sym := CharData; RETURN
		END
	END
END ScanPInstruction;

(** Possible results:
	Invalid
	TagPIOpen
	TagCondSectOpen
	TagDeclOpen
	TagXMLDeclOpen
	TagClose
	TagEmptyElemClose
	TagPIClose
	TagCondSectClose
	Comment
	CharRef
	EntityRef
	ParamEntityRef
	Literal
	Name
	Nmtoken
	PoundName
	Question
	Asterisk
	Plus
	Or
	Comma
	Percent
	Equal
	ParenOpen
	ParenClose
	BracketOpen
	BracketClose	*)
PROCEDURE (this: Scanner) ScanMarkup*, NEW;
	VAR ch: CHAR;
BEGIN
	this.SkipWhiteSpaces();
	this.oldpos := this.GetPos();
	IF this.sym = Eof THEN
		this.sym := Eof; RETURN
	END;
	CASE this.nextCh OF
	| '<': this.NextCh();
			IF this.nextCh = '!' THEN
				this.NextCh();
				IF this.nextCh = '-' THEN
					this.NextCh();
					IF this.nextCh = '-' THEN
						this.NextCh(); this.ScanComment()
					ELSE
						this.Error("'<!--' expected")
					END
				ELSIF this.nextCh = '[' THEN
					this.sym := TagCondSectOpen
				ELSE
					this.ScanNm();
					IF this.sym = Name THEN
						this.sym := TagDeclOpen
					ELSE
						this.Error("'<!NAME' expected")
					END
				END
			ELSIF this.nextCh = '?' THEN
				this.NextCh(); this.ScanNm();
				IF this.sym = Name THEN
					this.sym := TagPIOpen
				ELSE
					this.Error("'<?' Name expected")
				END
			ELSE
				this.Error("'<?' Name or '<!--' expected")
			END
	| '/': this.NextCh();
			IF this.nextCh = '>' THEN
				this.NextCh(); this.sym := TagEmptyElemClose
			ELSE
				this.sym := Invalid
			END
	| '>': this.NextCh(); this.sym := TagClose
	| '%': this.NextCh();
			IF this.nextCh = ' ' THEN
				this.sym := Percent
			ELSE
				this.ScanPEReference()
			END
	| '?': this.NextCh();
			IF this.nextCh = '>' THEN
				this.NextCh();
				this.sym := TagPIClose
			ELSE
				this.sym := Question
			END
	| '*': this.NextCh(); this.sym := Asterisk
	| '+': this.NextCh(); this.sym := Plus
	| '|': this.NextCh(); this.sym := Or
	| ',': this.NextCh(); this.sym := Comma
	| '(': this.NextCh(); this.sym := ParenOpen
	| ')': this.NextCh(); this.sym := ParenClose
	| '[': this.NextCh(); this.sym := BracketOpen
	| ']': this.NextCh();
			IF this.nextCh = ']' THEN
				this.NextCh();
				IF this.nextCh = '>' THEN
					this.NextCh(); this.sym := TagCondSectClose
				ELSE
					this.Error("']]>' expected")
				END
			ELSE
				this.sym := BracketClose
			END
	| '=': this.NextCh(); this.sym := Equal
	| '"', "'": ch := this.nextCh; this.NextCh(); this.ReadTillChar(ch); this.NextCh();
			IF this.sym # Invalid THEN this.sym := Literal END;
	| '#': this.ScanPoundName()
	ELSE this.ScanNm()
	END
END ScanMarkup;

(** possible results:
	TagElemEndOpen
	TagPIOpen
	TagDocTypeOpen
	CDataSect
	TagElemStartOpen
	Comment
	CharData
	CharRef
	EntityRef
	Eof *)
PROCEDURE (this: Scanner) ScanContent*, NEW;
	VAR op : LONGINT;
BEGIN
	op := this.GetPos();
	this.SkipWhiteSpaces(); this.oldpos := this.GetPos();
	IF this.sym = Eof THEN this.nextCh := 0X END;
	CASE this.nextCh OF
	| 0X: this.sym := Eof
	| '<': this.NextCh();
			CASE this.nextCh OF
			| '/': this.sym := TagElemEndOpen; this.NextCh()
			| '?': this.NextCh(); this.ScanNm();
					IF (this.sym = Name) THEN
						IF this.dynstr.EqualsTo("xml", TRUE) THEN
							this.sym := TagXMLDeclOpen
						ELSE
							this.sym := TagPIOpen
						END
					ELSE
						this.Error("'<? Name' expected")
					END
			| '!': this.NextCh();
					IF this.nextCh = '-' THEN
						this.NextCh();
						IF this.nextCh = '-' THEN
							this.NextCh(); this.ScanComment()
						ELSE
							this.Error("'<!--' expected")
						END
					ELSIF this.nextCh = '[' THEN
						this.NextCh(); this.ScanNm();
						IF (this.sym = Name) & this.dynstr.EqualsTo("CDATA", FALSE) & (this.nextCh = '[') THEN
							this.NextCh(); this.ScanCDataSect()
						ELSE
							this.Error("'<[CDATA[' expected'")
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
				this.sym:=TagElemStartOpen
			END
	(*
	| '?': this.NextCh();
			IF this.nextCh = '>' THEN
				this.NextCh(); this.sym := TagPIClose
			ELSE
				this.Error("'?>' expected")
			END
	| '&': this.NextCh(); this.ScanReference()
	*)
	ELSE
		this.dynstr.Clear;
		REPEAT
			this.dynstr.AppendChar(this.nextCh);
			this.NextCh();
		UNTIL (this.nextCh = '<') OR (this.sym = Eof);
		this.oldpos := op;
		this.sym := CharData
	END
END ScanContent;

PROCEDURE (this: Scanner) SetStringPooling*(stringPooling : SET), NEW;
BEGIN
	this.stringPooling := stringPooling;
	IF (stringPooling = {}) THEN
		this.stringPool := NIL;
	ELSIF (this.stringPool = NIL) THEN
		this.stringPool := DStrings.NewPool();
	END;
	ASSERT((this.stringPool = NIL) = (stringPooling = {}));
END SetStringPooling;

(* allocates and initializes a new scanner; e = NIL means to use the default error handler *)
PROCEDURE NewScanner*(r: Streams.Reader; e: ErrorHandler): Scanner;
	VAR s: Scanner;
BEGIN
	NEW(s); s.Init(r, e);
	RETURN s
END NewScanner;

END W3cXMLScanners.