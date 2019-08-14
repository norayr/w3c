MODULE W3cCSSScanners;

(* this module provides a CSS2 scanner with string pooling capability.

Original author: Stefan Walthert (swalthert).
Ported from A2 Oberon build 7131 to BlackBox Component Pascal, J. Templ, 2017-05-10 *)

IMPORT StdLog,
	DStrings := W3cDStrings,
	Streams := W3cStreams,
	ErrorHandlers := W3cErrorHandlers;

CONST
	(** Scanner: Tokens *)
	Null = -2;
	Invalid* = -1;
	Ident* = 0;
	AtKeyword* = 1;	(** '@'ident *)
	String* = 2;	(** '"'chars'"' | "'"chars"'" *)
	Hash* = 3;	(** '#'name *)
	Important* = 4;	(** '!important' *)
	Number* = 5;	(** number (cf. Scanner.numType) *)
	Percentage* = 6;	(** num'%' *)
	Dimension* = 7;	(** num ident *)
	URI* = 8;	(** 'url('string')' | 'url('chars')' *)
	Function* = 9;	(** ident'(' *)
	UnicodeRange* = 10;	(**  *)
	Cdo* = 11;	(** '<!--' *)
	Cdc* = 12;	(** '-->' *)
	Slash* = 13;	(** '/' *)
	Comma* = 14;	(** ',' *)
	Greater* = 15;	(** '>' *)
	Plus* = 16;	(** '+' *)
	Minus* = 17;	(** '-' *)
	Asterisk* = 18;	(** '*' *)
	Semicolon* = 19;	(** ';' *)
	Colon* = 20;	(** ':' *)
	Dot* = 21;	(** '.' *)
	BracketOpen* = 22;	(** '[' *)
	BracketClose* = 23;	(** ']' *)
	ParenOpen* = 24;	(** '(' *)
	ParenClose* = 25;	(** ')' *)
	BraceOpen* = 26;	(** '{' *)
	BraceClose* = 27;	(** '}' *)
	Equal* = 28;	(** '=' *)
	Includes* = 29;	(** '~=' *)
	Dashmatch* = 30;	(** '|=' *)
	Eof* = 31;	(**  *)

	(** real or integer number *)
	Undefined* = 0;
	Integer* = 1;	(** integer number *)
	Real* = 2;	(** real number *)

	TAB = 09X; LF = 0AX; CR = 0DX;
	
TYPE
	Scanner* = POINTER TO EXTENSIBLE RECORD
		r-: Streams.Reader;
		errorHandler-: ErrorHandler;
		sym-: LONGINT;
		numberType-: INTEGER;
		intVal-: LONGINT;
		realVal-: REAL;
		line-, col-, pos: LONGINT;
		nextCh: CHAR;
		dynstr: DStrings.DynamicString;
		stringPool: DStrings.Pool;
		stringPooling: SET;
	END;
	
	ErrorHandler* = ErrorHandlers.ErrorHandler;


PROCEDURE^ (this: Scanner) NextCh, NEW;
PROCEDURE^ (this: Scanner) GetPos*(): LONGINT, NEW;
PROCEDURE^ IsWhiteSpace(ch: CHAR): BOOLEAN;
PROCEDURE^ HexStrToInt(VAR str: ARRAY OF CHAR; VAR val: LONGINT);
PROCEDURE^ IsDigit(ch: CHAR): BOOLEAN;
PROCEDURE^ IsNmChar(ch: CHAR): BOOLEAN;
PROCEDURE^ IsEscape(ch: CHAR): BOOLEAN;
PROCEDURE^ IsNonAscii(ch: CHAR): BOOLEAN;
PROCEDURE^ IsNmStart(ch: CHAR): BOOLEAN;

PROCEDURE (this: Scanner) Reset*(r: Streams.Reader; e: ErrorHandler), NEW;
BEGIN
	ASSERT(r # NIL, 20);
	ASSERT(e # NIL, 21);
	this.r := r;
	this.errorHandler := e;
	e.Reset;
	this.sym := Null; this.numberType := Undefined; this.intVal := 0; this.realVal := 0.0;
	this.line := 1; this.pos := 0; this.col := 0;
	this.dynstr.Clear;
	this.NextCh()
END Reset;

(* constructor *)
PROCEDURE (this: Scanner) Init*(r: Streams.Reader; e: ErrorHandler), NEW;
BEGIN
	ASSERT(r # NIL, 20);
	IF e = NIL THEN NEW(e); e.Init END;
	this.dynstr := DStrings.NewDynamicString();
	this.stringPool := NIL; this.stringPooling := {};
	this.Reset(r, e)
END Init;

PROCEDURE (this: Scanner) Error(IN msg: ARRAY OF CHAR), NEW;
BEGIN
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

PROCEDURE (this: Scanner) SkipWhiteSpace, NEW;
BEGIN
	WHILE IsWhiteSpace(this.nextCh) DO
		this.NextCh()
	END
END SkipWhiteSpace;

PROCEDURE (this: Scanner) ScanComment, NEW;
BEGIN
	LOOP
		this.NextCh();
		WHILE (this.nextCh # '*') & (this.sym # Eof) DO
			this.NextCh()
		END;
		IF this.nextCh = '*' THEN
			this.NextCh();
			IF this.nextCh = '/' THEN
				this.NextCh(); EXIT
			END
		ELSIF this.sym = Eof THEN
			this.Error("unclosed comment")
		END
	END
END ScanComment;

PROCEDURE (this: Scanner) ScanEscape(isString: BOOLEAN), NEW;
	VAR val: LONGINT; n: INTEGER; hexstr: ARRAY 7 OF CHAR; newline: BOOLEAN;
BEGIN
	newline := FALSE;
	this.NextCh();
	IF IsDigit(this.nextCh)
	OR (('a' <= this.nextCh) & (this.nextCh <= 'f')) 
	OR (('A' <= this.nextCh) & (this.nextCh <= 'F')) THEN (* hexadecimal digit *)
		n := 0;
		(* WHILE ~IsWhiteSpace(this.nextCh) & (n < 6) DO *)
		WHILE (IsDigit(this.nextCh) 
		OR (('a' <= this.nextCh) & (this.nextCh <= 'f')) 
		OR (('A' <= this.nextCh) & (this.nextCh <= 'F'))) 
		& (n < 6) DO
			hexstr[n] := this.nextCh; this.NextCh(); INC(n)
		END;
		hexstr[n] := 0X;
		HexStrToInt(hexstr, val);
		IF IsWhiteSpace(this.nextCh) & (n # 6) THEN  (* skip space after escape digits (if less than 6 digits) *)
			this.NextCh()
		END;
	ELSE
		val := ORD(this.nextCh);
		IF (this.nextCh = LF) OR (this.nextCh = CR) THEN newline := TRUE END;
		this.NextCh()
	END;
	(* INC(i, number of bytes needed to write unicode value val as a UTF8 character); *)
	IF ~isString OR ~newline THEN
		(* compute UTF8 characters out of 'val', put them to dynstr *)
	END
END ScanEscape;

PROCEDURE (this: Scanner) ScanIdent, NEW;
BEGIN
	IF IsNmStart(this.nextCh) THEN
		REPEAT
			IF IsEscape(this.nextCh) THEN
				this.ScanEscape(FALSE)
			ELSE
				this.dynstr.AppendChar(this.nextCh);
				this.NextCh()
			END
		UNTIL ~IsNmChar(this.nextCh);
		this.sym := Ident
	ELSE
		this.Error("{nmstart} expected")
	END
END ScanIdent;

PROCEDURE (this: Scanner) ScanName, NEW;
BEGIN
	WHILE IsNmChar(this.nextCh) DO
		IF IsEscape(this.nextCh) THEN
			this.ScanEscape(FALSE)
		ELSE
			this.dynstr.AppendChar(this.nextCh);
			this.NextCh()
		END
	END;
	this.sym := Ident
END ScanName;

PROCEDURE (this: Scanner) HtmlDecode, NEW;
	VAR i: LONGINT; ref: ARRAY 20 OF CHAR;
BEGIN
	IF this.nextCh = "&" THEN
		this.NextCh();
		i := 0;
		WHILE (this.nextCh # ";") & (this.nextCh # 0X) DO
			ref[i] := this.nextCh; this.NextCh();
			IF i < LEN(ref) - 1 THEN INC(i) END;
		END;
		ref[i] := 0X;
		IF this.nextCh = ";" THEN
			IF ref = 'amp' THEN this.nextCh := '&'
			ELSIF ref = 'lt' THEN this.nextCh := '<'
			ELSIF ref = 'gt' THEN this.nextCh := '>'
			ELSIF ref = 'apos' THEN this.nextCh := "'"
			ELSIF ref = 'quot' THEN this.nextCh := '"'
			ELSE this.Error("unknown html escape: " + "&" + ref + ";"); this.sym := Eof
			END
		ELSE
			this.Error("';' expected"); this.sym := Eof
		END
	END
END HtmlDecode;

PROCEDURE (this: Scanner) ScanString, NEW;
	VAR ch, allowedQuote: CHAR;
BEGIN
	ch := this.nextCh;
	IF ch = '"' THEN allowedQuote := "'"
	ELSIF ch = "'" THEN allowedQuote := '"'
	ELSE this.Error("quote expected")
	END;
	this.NextCh();
	this.HtmlDecode();
	WHILE ((this.nextCh = TAB) OR (this.nextCh = ' ') OR (this.nextCh = '!') OR (('#' <= this.nextCh) & (this.nextCh <= '&'))
			OR (('(' <= this.nextCh) & (this.nextCh <= '~')) OR (this.nextCh = allowedQuote)
			OR IsNonAscii(this.nextCh) OR IsEscape(this.nextCh)) & (this.sym # Eof) DO
		IF IsEscape(this.nextCh) THEN
			this.ScanEscape(TRUE)
		ELSE
			this.dynstr.AppendChar(this.nextCh); this.NextCh();
			this.HtmlDecode();
		END;
	END;
	IF this.nextCh # ch THEN this.Error("quote expected") END;
	this.NextCh()
END ScanString;

PROCEDURE (this: Scanner) ScanURL, NEW;
BEGIN
	WHILE ((this.nextCh = '!') OR (('#' <= this.nextCh) & (this.nextCh <= '&')) OR (('*' <= this.nextCh) & (this.nextCh <= '~'))
			OR IsNonAscii(this.nextCh) OR IsEscape(this.nextCh)) & (this.sym # Eof) DO
		IF IsEscape(this.nextCh) THEN
			this.ScanEscape(FALSE)
		ELSE
			this.dynstr.AppendChar(this.nextCh);
			this.NextCh()
		END
	END
END ScanURL;

PROCEDURE (this: Scanner) ScanIdentUriFunction, NEW;
	VAR s: DStrings.String;
BEGIN
	this.ScanIdent();
	IF this.nextCh = '(' THEN
		this.NextCh();
		s := this.dynstr.ToString();
		IF s^ = 'url' THEN
			this.SkipWhiteSpace();
			this.dynstr.Clear();
			IF (this.nextCh = '"') OR (this.nextCh = "'") THEN
				this.ScanString()
			ELSE
				this.ScanURL()
			END;
			this.SkipWhiteSpace();
			IF this.nextCh = ')' THEN
				this.NextCh(); this.sym := URI
			ELSE
				this.Error("')' expected")
			END
		ELSE
			this.sym := Function
		END
	END
END ScanIdentUriFunction;

PROCEDURE (this: Scanner) ScanNumber, NEW;
	VAR a, b, div: LONGINT;
BEGIN
	a := 0;
	WHILE IsDigit(this.nextCh) & (this.sym # Eof) DO
		a := 10 * a + ORD(this.nextCh) - ORD('0');
		this.NextCh()
	END;
	IF this.nextCh = '.' THEN
		b := 0; div := 1;
		this.NextCh();
		IF ~IsDigit(this.nextCh) THEN this.sym := Dot; RETURN END;
		WHILE IsDigit(this.nextCh) & (this.sym # Eof) DO
			b := 10 * b + ORD(this.nextCh) - ORD('0'); div := 10 * div;
			this.NextCh()
		END;
		this.realVal := a + b / div;
		this.sym := Number; this.numberType := Real
	ELSE
		this.intVal := a;
		this.sym := Number; this.numberType := Integer
	END;
	IF IsNmStart(this.nextCh) THEN
		this.ScanIdent(); this.sym := Dimension
	ELSIF this.nextCh = '%' THEN
		this.NextCh(); this.sym := Percentage
	END
END ScanNumber;

PROCEDURE (this: Scanner) Scan*, NEW;
	VAR s: DStrings.String; msg: ARRAY 22 OF CHAR;
BEGIN
	this.sym := Null;
	this.numberType := Undefined; this.intVal := 0; this.realVal := 0.0;	(* reset all fields *)
	REPEAT
		this.dynstr.Clear();
		this.SkipWhiteSpace();
		CASE this.nextCh OF
		| 0X: this.sym := Eof
		| 'a' .. 'z', 'A' .. 'Z', '\', '_': this.ScanIdentUriFunction()
		| '!': this.NextCh(); this.SkipWhiteSpace();
				this.ScanIdent(); s := this.dynstr.ToString();
				IF s^ = 'important' THEN
					this.sym := Important
				ELSE
					this.Error("'!important' expected")
				END
		| '+': this.NextCh();
				IF IsDigit(this.nextCh) OR (this.nextCh = '.') THEN
					this.ScanNumber()
				ELSE
					this.sym := Plus
				END
		| '-': this.NextCh();
				IF this.nextCh = '-' THEN
					this.NextCh();
					IF this.nextCh = '>' THEN
						this.NextCh(); this.sym := Cdc
					ELSE
						this.Error("'-->' expected")
					END
				ELSIF IsNmStart(this.nextCh) THEN
					this.dynstr.AppendChar("-"); this.ScanIdentUriFunction()
				ELSE
					this.sym := Minus
				END;
		| '0' .. '9', '.' : this.ScanNumber()
		| '@': this.NextCh(); this.ScanIdent(); this.sym := AtKeyword
		| '#': this.NextCh();
				IF IsNmChar(this.nextCh) THEN this.ScanName(); this.sym := Hash
				ELSE this.Error("'name' expected after #")
				END
		| '*': this.NextCh(); this.sym := Asterisk
		| '<': this.NextCh();
				IF this.nextCh = '!' THEN
					this.NextCh();
					IF this.nextCh = '-' THEN
						this.NextCh();
						IF this.nextCh = '-' THEN
							this.NextCh(); this.sym := Cdo
						ELSE
							this.Error("'<!--' expected")
						END
					ELSE
						this.Error("'<!--' expected")
					END
				ELSE
					this.Error("'<!--' expected")
				END
		| '/': this.NextCh();
				IF this.nextCh = '*' THEN
					this.ScanComment(); this.sym := Null
				ELSE
					this.sym := Slash
				END
		| '>': this.NextCh(); this.sym := Greater
		| '~': this.NextCh();
				IF this.nextCh = '=' THEN
					this.NextCh(); this.sym := Includes
				ELSE
					this.Error("'~= expected")
				END
		| '|': this.NextCh();
				IF this.nextCh = '=' THEN
					this.NextCh(); this.sym := Dashmatch
				ELSE
					this.Error("'|=' expected")
				END
		| '=': this.NextCh(); this.sym := Equal
		| '"', "'": this.ScanString(); this.sym := String
		| '[': this.NextCh(); this.sym := BracketOpen
		| ']': this.NextCh(); this.sym := BracketClose
		| '(': this.NextCh(); this.sym := ParenOpen
		| ')': this.NextCh(); this.sym := ParenClose
		| '{': this.NextCh(); this.sym := BraceOpen
		| '}': this.NextCh(); this.sym := BraceClose
		| ',': this.NextCh(); this.sym := Comma
		| ';': this.NextCh(); this.sym := Semicolon
		| ':': this.NextCh(); this.sym := Colon
		| '&': this.HtmlDecode()
		ELSE
			IF IsNonAscii(this.nextCh) THEN
				this.ScanIdentUriFunction()
			ELSE
				msg := "unknown character "; msg[18] := "'"; msg[19] := this.nextCh; msg[20] := "'"; msg[21] := 0X;
				this.Error(msg)
			END
		END
	UNTIL this.sym # Null
END Scan;

PROCEDURE (this: Scanner) GetStr*(type: LONGINT): DStrings.String, NEW;
BEGIN
	IF type IN this.stringPooling THEN RETURN this.stringPool.Get(this.dynstr)
	ELSE RETURN this.dynstr.ToString()
	END
END GetStr;

PROCEDURE (this: Scanner) GetStrLower*(type: LONGINT): DStrings.String, NEW;
BEGIN
	this.dynstr.ToLower;
	RETURN this.GetStr(type)
END GetStrLower;

PROCEDURE (this: Scanner) GetStrUpper*(type: LONGINT): DStrings.String, NEW;
BEGIN
	this.dynstr.ToUpper;
	RETURN this.GetStr(type)
END GetStrUpper;

PROCEDURE (this: Scanner) GetPos*(): LONGINT, NEW;
BEGIN
	RETURN this.pos
END GetPos;

PROCEDURE IsWhiteSpace(ch: CHAR): BOOLEAN;
BEGIN
	RETURN (ch = " ") OR (ch = TAB) OR (ch = CR) OR (ch = LF)
END IsWhiteSpace;

PROCEDURE IsNonAscii(ch: CHAR): BOOLEAN;
BEGIN
	RETURN ch >= 100X
END IsNonAscii;

PROCEDURE IsEscape(ch: CHAR): BOOLEAN;
BEGIN
	RETURN ch = '\'
END IsEscape;

PROCEDURE IsNmStart(ch: CHAR): BOOLEAN;
BEGIN
	RETURN (('a' <= ch) & (ch <= 'z')) OR (('A' <= ch) & (ch <= 'Z')) OR (ch = '_')
			OR IsNonAscii(ch) OR IsEscape(ch)
END IsNmStart;

PROCEDURE IsNmChar(ch: CHAR): BOOLEAN;
BEGIN
	RETURN (('a' <= ch) & (ch <= 'z')) OR (('A' <= ch) & (ch <= 'Z')) OR (ch = '-') OR (ch = '_')
			OR IsDigit(ch) OR IsNonAscii(ch) OR IsEscape(ch)
END IsNmChar;

PROCEDURE IsDigit(ch: CHAR): BOOLEAN;
BEGIN
	RETURN ('0' <= ch) & (ch <= '9')
END IsDigit;

PROCEDURE HexStrToInt(VAR str: ARRAY OF CHAR; VAR val: LONGINT);
	VAR i, d: LONGINT; ch: CHAR;
BEGIN
	i := 0; ch := str[0];
	WHILE (ch # 0X) & (ch <= " ") DO
		INC(i); ch := str[i]
	END;
	val := 0;
	WHILE (("0" <= ch) & (ch <= "9")) OR (("A" <= ch) & (ch <= "F")) DO
		IF (("0" <= ch) & (ch <= "9")) THEN d := ORD(ch) - ORD("0")
		ELSE d := ORD(ch) - ORD("A") + 10
		END;
		INC(i); ch := str[i];
		IF val <= ((MAX(LONGINT) - d) DIV 10H) THEN
			val := 10H * val + d
		ELSE
			HALT(99)
		END
	END
END HexStrToInt;

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

(* allocates and initializes a new scanner; e = NIL means to use the default error handler *)
PROCEDURE NewScanner*(r: Streams.Reader; e: ErrorHandler): Scanner;
	VAR s: Scanner;
BEGIN
	NEW(s); s.Init(r, e); RETURN s
END NewScanner;

END W3cCSSScanners.