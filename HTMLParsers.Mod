MODULE W3cHTMLParsers;

(* This module provides an HTML(4/5) parser with string pooling capability.

Original author: Simon L. Keel, (heavily based on swalthert's "XMLParser").
Ported from A2 Oberon build 7648 to BlackBox Component Pascal, J. Templ, 2018-03-23.
*)

IMPORT Strings,
	DStrings := W3cDStrings,
	Streams := W3cStreams,
	Scanner := W3cHTMLScanners,
	Objects := W3cObjects,
	DOM := W3cDOM;

CONST
	(* String pooling settings *)
	Str_Hdr* = 0; (* names and literals in <?xml and <!DOCTYPE; usually not pooled *)
	Str_ElementName* = 1;
	Str_AttributeName* = 2;
	Str_AttrVal* = 3;
	Str_Comment* = 4;
	Str_CharData* = 5;
	
	DefaultStringPooling* = {Str_ElementName, Str_AttributeName};
	
TYPE
	String = DStrings.String;

	Node = POINTER TO RECORD
		name: String;
		back: Node;
	END;

	OpenTagStack= POINTER TO RECORD
		top: Node;
	END;

	Parser* = POINTER TO EXTENSIBLE RECORD
		elemReg*: DOM.ElementRegistry; (* optional DOM node factory *)
		errorHandler-: ErrorHandler;
		scanner: Scanner.Scanner;
		openTagStack: OpenTagStack;
		closedTag: String;
		newTagName: String;
		closedTagPremature: BOOLEAN;
	END;
	
	ErrorHandler* = Scanner.ErrorHandler;

PROCEDURE^ (this: Parser) ParseXMLDecl(): DOM.XMLDecl, NEW;
PROCEDURE^ (this: Parser) ParseComment(): DOM.Comment, NEW;
PROCEDURE^ (this: Parser) ParseDocTypeDecl(): DOM.DocTypeDecl, NEW;
PROCEDURE^ (this: Parser) ParseStartTagName, NEW;
PROCEDURE^ (this: Parser) ParseElement(): DOM.Element, NEW;
PROCEDURE^ (this: Parser) ParseCharData(): DOM.ArrayChars, NEW;
PROCEDURE^ (this: Parser) ParseStartTag(VAR e: DOM.Element; VAR empty: BOOLEAN), NEW;
PROCEDURE^ (this: Parser) ParseEndTag():String, NEW;
PROCEDURE^ (this: Parser) ParseSystemLiteral(): String, NEW;
PROCEDURE^ (this: Parser) ParsePubidLiteral(): String, NEW;
PROCEDURE^ (this: Parser) ParseAttribute(): DOM.Attribute, NEW;
PROCEDURE^ IsPubidLiteral(VAR str: ARRAY OF CHAR): BOOLEAN;
PROCEDURE^ PrematureTagClosing(name, next: String): BOOLEAN;
PROCEDURE^ IsVoidTag(name: String): BOOLEAN;

(* constructor *)
PROCEDURE (this: OpenTagStack) Init, NEW;
BEGIN
	this.top := NIL;
END Init;

PROCEDURE (this: OpenTagStack) Insert(s: String), NEW;
	VAR node: Node;
BEGIN
	NEW(node);
	node.name := s;
	node.back := this.top;
	this.top := node;
END Insert;

PROCEDURE (this: OpenTagStack) Remove(s: String), NEW;
	VAR node, old: Node;
BEGIN
	old := NIL;
	node := this.top;
	WHILE (node # NIL) & (s^ # node.name^) DO
		old := node;
		node := node.back;
	END;
	IF node # NIL THEN
		IF old = NIL THEN
			this.top := node.back;
		ELSE
			old.back := node.back;
		END;
	END;
END Remove;

PROCEDURE (this: OpenTagStack) IsMember(s: String): BOOLEAN, NEW;
	VAR node: Node;
BEGIN
	node := this.top;
	WHILE (node # NIL) & (s^ # node.name^) DO
		node := node.back;
	END;
	RETURN node # NIL;
END IsMember;

(** For debugging pupose only. 
PROCEDURE (this: OpenTagStack) Print, NEW;
	VAR node: Node;
BEGIN
	node := this.top;
	WHILE (node # NIL) DO
		StdLog.String(node.name^); StdLog.Ln();
		node := node.back;
	END;
	StdLog.String("----------"); StdLog.Ln();
END Print;**)

(* constructor *)
PROCEDURE (this: Parser) Init*(s: Scanner.Scanner), NEW;
BEGIN
	this.scanner := s; this.errorHandler := s.errorHandler;
	NEW(this.openTagStack); this.openTagStack.Init()
END Init;

PROCEDURE (this: Parser) Error(IN msg: ARRAY OF CHAR), NEW;
BEGIN
	this.errorHandler.HandleError(this.scanner.GetPos(), this.scanner.line, this.scanner.col, msg);
	IF ~this.errorHandler.cont THEN this.scanner.r.ok := FALSE END;
END Error;

PROCEDURE (this: Parser) CheckSymbol(expectedSymbols: SET; IN errormsg: ARRAY OF CHAR): BOOLEAN, NEW;
BEGIN
	IF ~(this.scanner.sym IN expectedSymbols) THEN
		this.Error(errormsg); RETURN FALSE
	ELSE
		RETURN TRUE
	END
END CheckSymbol;

PROCEDURE MakeHtml(doc: DOM.Document);
	VAR html, body: DOM.Element; it: Objects.Enumerator; c: DOM.Content;
BEGIN
	NEW(html); html.Init; NEW(body); body.Init;
	it := doc.GetContents();
	WHILE it.HasMoreElements() DO
		c := it.GetNext()(DOM.Content);
		doc.RemoveContent(c);
		body.AddContent(c);
	END;
	doc.AddContent(html);
	html.AddContent(body);
END MakeHtml;

PROCEDURE (this: Parser) Parse*(): DOM.Document, NEW;
	VAR
		doc: DOM.Document;
		decl: DOM.XMLDecl;
		dtd, newDtd: DOM.DocTypeDecl;
		e: DOM.Element;
		s: String;
BEGIN
	NEW(doc); doc.Init;
	dtd := doc.GetDocTypeDecl();
	LOOP
		this.scanner.ScanContent();
		CASE this.scanner.sym OF
		| Scanner.TagXMLDeclOpen: (* <?xml *)
			decl := this.ParseXMLDecl();
			IF decl # NIL THEN doc.AddContent(decl) END;
		| Scanner.Comment: (* <!-- ... --> *)
			doc.AddContent(this.ParseComment());
		| Scanner.TagDeclOpen: (* <!... *)
			s := this.scanner.GetStrUpper(Str_Hdr);
			IF s^ = 'DOCTYPE' THEN
				newDtd := this.ParseDocTypeDecl();
				IF dtd = NIL THEN
					IF newDtd # NIL THEN
						dtd := newDtd;
						doc.AddContent(dtd);
					END;
				END;
			ELSE
				this.Error("ignoring '<!" + s + ">'");
			END;
		| Scanner.TagElemStartOpen: (* < *)
			this.ParseStartTagName();
			e := this.ParseElement();
			IF e # NIL THEN doc.AddContent(e) END;
		| Scanner.CharData: (* char data *)
			doc.AddContent(this.ParseCharData())
		| Scanner.TagElemEndOpen: (* </ *)
			(* ignore *)
			s := this.ParseEndTag();
		| Scanner.Eof: (* EOF *)
			IF doc.GetRoot() = NIL THEN MakeHtml(doc) END;
			RETURN doc
		ELSE
			this.Error("unknown content");
		END;
	END;
END Parse;

PROCEDURE (this: Parser) ParseXMLDecl(): DOM.XMLDecl, NEW;
	VAR decl: DOM.XMLDecl; s: String;
BEGIN
	NEW(decl); decl.Init;
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Name}, "<?xml>: 'version' expected") THEN RETURN NIL END;
	s := this.scanner.GetStrLower(Str_Hdr);
	IF s^ # "version" THEN this.Error("<?xml>: 'version' expected"); RETURN NIL END;
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Equal}, "<?xml>: '=' expected") THEN RETURN NIL END;
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Literal}, "<?xml>: Version Number expected") THEN RETURN NIL END;
	s := this.scanner.GetStr(Str_Hdr);
	IF s = NIL THEN s := DStrings.NewString(""); END;
	decl.SetVersion(s^);
	this.scanner.ScanMarkup();
	s := this.scanner.GetStrLower(Str_Hdr);
	IF (this.scanner.sym = Scanner.Name) & (s^ = "encoding") THEN
		this.scanner.ScanMarkup();
		IF ~this.CheckSymbol({Scanner.Equal}, "<?xml>: encoding: '=' expected") THEN RETURN decl END;
		this.scanner.ScanMarkup();
		IF ~this.CheckSymbol({Scanner.Literal}, "<?xml>: Encoding Name expected") THEN RETURN decl END;
		s := this.scanner.GetStr(Str_Hdr);
		IF s = NIL THEN s := DStrings.NewString(""); END;
		decl.SetEncoding(s^);
		this.scanner.ScanMarkup();
		s := this.scanner.GetStrLower(Str_Hdr);
	END;
	IF (this.scanner.sym = Scanner.Name) & (s^ = "standalone") THEN
		this.scanner.ScanMarkup();
		IF ~this.CheckSymbol({Scanner.Equal}, "<?xml>: standalone: '=' expected") THEN RETURN decl END;
		this.scanner.ScanMarkup();
		IF ~this.CheckSymbol({Scanner.Literal}, '<?xml>: standalone: "yes" or "no" expected') THEN RETURN decl END;
		s := this.scanner.GetStr(Str_Hdr);
		Strings.ToLower(s^, s^);
		IF s^ = "yes" THEN decl.SetStandalone(TRUE)
		ELSIF s^ = "no" THEN decl.SetStandalone(FALSE)
		ELSE this.Error('<?xml>: standalone: "yes" or "no" expected'); RETURN decl
		END;
		this.scanner.ScanMarkup()
	END;
	WHILE (this.scanner.sym # Scanner.TagPIClose) & (this.scanner.sym # Scanner.Eof) DO
		this.scanner.ScanMarkup();
	END;
	IF this.scanner.sym = Scanner.Eof THEN this.Error("<?xml>: '?>' expected") END;
	RETURN decl
END ParseXMLDecl;

PROCEDURE (this: Parser) ParseComment(): DOM.Comment, NEW;
	VAR comment: DOM.Comment; s: String;
BEGIN
	NEW(comment); comment.Init;
	s := this.scanner.GetStr(Str_Comment);
	comment.SetStr(s^);
	RETURN comment
END ParseComment;

PROCEDURE (this: Parser) ParseDocTypeDecl(): DOM.DocTypeDecl, NEW;
	VAR
		dtd: DOM.DocTypeDecl;
		externalSubset: DOM.EntityDecl;
		s: String;
BEGIN
	NEW(dtd); dtd.Init;
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Name}, "<!DOCTYPE: DTD name expected") THEN RETURN NIL END;
	s := this.scanner.GetStr(Str_Hdr);
	dtd.SetNameAsString(s);
	this.scanner.ScanMarkup();
	IF this.scanner.sym = Scanner.Name THEN	(* DTD points to external subset *)
		NEW(externalSubset); externalSubset.Init;
		s := this.scanner.GetStrUpper(Str_Hdr);
		IF s^ = 'SYSTEM' THEN
			this.scanner.ScanMarkup();
			s := this.ParseSystemLiteral();
			IF s = NIL THEN s := DStrings.NewString(""); END;
			externalSubset.SetSystemId(s^);
			this.scanner.ScanMarkup();
		ELSIF s^ = 'PUBLIC' THEN
			this.scanner.ScanMarkup();
			s := this.ParsePubidLiteral();
			IF s = NIL THEN s := DStrings.NewString(""); END;
			externalSubset.SetPublicId(s^);
			this.scanner.ScanMarkup();
			IF this.scanner.sym = Scanner.Literal THEN
				s := this.ParseSystemLiteral();
				IF s = NIL THEN s := DStrings.NewString(""); END;
				externalSubset.SetSystemId(s^);
				this.scanner.ScanMarkup();
			ELSE
				s := DStrings.NewString("");
				externalSubset.SetSystemId(s^);
			END;
		ELSE
			this.Error("<!DOCTYPE>:'SYSTEM' or 'PUBLIC' expected");
			RETURN NIL;
		END;
		dtd.SetExternalSubset(externalSubset);
	END;
	WHILE (this.scanner.sym # Scanner.TagClose) & (this.scanner.sym # Scanner.Eof) DO
		this.scanner.ScanMarkup();
	END;
	IF this.scanner.sym = Scanner.Eof THEN this.Error("<!DOCTYPE>: '>' expected") END;
	RETURN dtd;
END ParseDocTypeDecl;

PROCEDURE (this: Parser) ParseSystemLiteral(): String, NEW;
	VAR systemLiteral: String;
BEGIN
	IF ~this.CheckSymbol({Scanner.Literal}, "System Literal expected") THEN RETURN NIL END;
	systemLiteral := this.scanner.GetStr(Str_Hdr);
	RETURN systemLiteral
END ParseSystemLiteral;

PROCEDURE (this: Parser) ParsePubidLiteral(): String, NEW;
	VAR pubidLiteral: String;
BEGIN
	IF ~this.CheckSymbol({Scanner.Literal}, "PubidLiteral expected") THEN RETURN NIL END;
	pubidLiteral := this.scanner.GetStr(Str_Hdr);
	IF ~IsPubidLiteral(pubidLiteral^) THEN this.Error("not a correct Pubid Literal"); RETURN NIL END;
	RETURN pubidLiteral
END ParsePubidLiteral;

PROCEDURE (this: Parser) ParseCharData(): DOM.ArrayChars, NEW;
	VAR cd: DOM.ArrayChars; s: String;
BEGIN
	NEW(cd); cd.Init;
	s := this.scanner.GetStr(Str_CharData);
	cd.SetStrAsString(s);
	RETURN cd
END ParseCharData;

PROCEDURE (this: Parser) ParseElement(): DOM.Element, NEW;
	VAR
		e: DOM.Element;
		empty: BOOLEAN;
		name, s: String;
BEGIN
	this.ParseStartTag(e, empty);
	IF e = NIL THEN RETURN NIL END;
	IF empty THEN
		this.openTagStack.Remove(e.GetName());
		RETURN e;
	END;
	name := e.GetName();
	IF name^ = "SCRIPT" THEN
		this.scanner.ScanSCRIPT();
		e.AddContent(this.ParseCharData());
		RETURN e;
	END;
	IF name^ = "STYLE" THEN
		this.scanner.ScanSTYLE();
		e.AddContent(this.ParseCharData());
		RETURN e;
	END;
	LOOP
		this.scanner.ScanContent();
		CASE this.scanner.sym OF
		| Scanner.CharData: e.AddContent(this.ParseCharData())
		| Scanner.TagElemStartOpen:
			this.ParseStartTagName();
			REPEAT
				IF PrematureTagClosing(name, this.newTagName) THEN
					this.closedTagPremature := TRUE;
					this.openTagStack.Remove(name);
					(* for debugging:  this.Error("closing " + s); *)
					RETURN e;
				END;
				this.closedTagPremature := FALSE;
				e.AddContent(this.ParseElement());
				IF this.closedTag # NIL THEN
					IF this.closedTag^ = name^ THEN
						this.openTagStack.Remove(name);
						this.closedTag := NIL;
					END;
					RETURN e;
				END;
			UNTIL ~this.closedTagPremature;
		| Scanner.Comment: e.AddContent(this.ParseComment())
		| Scanner.TagPIOpen:
			WHILE (this.scanner.sym # Scanner.TagClose) & (this.scanner.sym # Scanner.Eof) DO
				this.scanner.ScanMarkup();
			END;
			IF this.scanner.sym = Scanner.Eof THEN this.Error("'>' expected") END;
		| Scanner.TagElemEndOpen:
			s := this.ParseEndTag();
			IF s # NIL THEN
				this.openTagStack.Remove(name);
				IF s^ = name^ THEN
					this.closedTag := NIL;
				ELSE
					this.closedTag := s;
				END;
				RETURN e;
			END;
		| Scanner.Eof: this.Error("element not closed: " + name); RETURN e
		ELSE
			this.Error("unknown Element Content");
		END;
	END;
END ParseElement;

PROCEDURE (this: Parser) ParseStartTagName, NEW;
BEGIN
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Name}, "Element Name expected") THEN
		this.newTagName := DStrings.NewString("");
		RETURN
	END;
	this.newTagName := this.scanner.GetStrUpper(Str_ElementName);
END ParseStartTagName;

PROCEDURE (this: Parser) ParseStartTag(VAR e: DOM.Element; VAR empty: BOOLEAN), NEW;
	VAR s: String;
BEGIN
	s := this.newTagName; e := NIL; empty := FALSE;
	IF this.elemReg # NIL THEN
		e := this.elemReg.InstantiateElement(s^)
	END;
	IF e = NIL THEN NEW(e); e.Init END;
	e.SetNameAsString(s);
	this.openTagStack.Insert(s);
	this.scanner.ScanAttributeName();
	WHILE this.scanner.sym = Scanner.Name DO
		e.AddAttribute(this.ParseAttribute());
	END;
	IF this.CheckSymbol({Scanner.TagEmptyElemClose, Scanner.TagClose}, "'/>' or '>' expected") THEN
		empty := (this.scanner.sym = Scanner.TagEmptyElemClose) OR IsVoidTag(s)
	END
END ParseStartTag;

PROCEDURE (this: Parser) ParseAttribute(): DOM.Attribute, NEW;
	VAR a: DOM.Attribute; s: String;
BEGIN
	NEW(a); a.Init;
	s := this.scanner.GetStrLower(Str_AttributeName);
	a.SetNameAsString(s);
	this.scanner.ScanAttributeName();
	IF this.scanner.sym = Scanner.Equal THEN
		this.scanner.ScanAttributeValue();
		IF ~this.CheckSymbol({Scanner.Literal}, "Attribute Value expected") THEN RETURN a END;
		s := this.scanner.GetStr(Str_AttrVal);
		a.SetValueAsString(s);
		this.scanner.ScanAttributeName();
	ELSE
		a.SetValue("");
	END;
	RETURN a
END ParseAttribute;

PROCEDURE (this: Parser) ParseEndTag():String, NEW;
	VAR s: String;
BEGIN
	this.scanner.ScanMarkup();
	s := this.scanner.GetStrUpper(Str_ElementName);
	IF (this.scanner.sym = Scanner.Name) THEN
		this.scanner.ScanMarkup();
		IF ~this.CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN NIL; END;
		IF this.openTagStack.IsMember(s) THEN
			RETURN s;
		ELSE
			this.Error("ignoring '</" + s + ">'");
			RETURN NIL;
		END;
	ELSE
		this.Error("ignoring '</" + s + ">'");
		RETURN NIL;
	END
END ParseEndTag;


PROCEDURE IsPubidLiteral(VAR str: ARRAY OF CHAR): BOOLEAN;
	VAR i, len: HUGEINT; ch: CHAR;
BEGIN
	i := 0; len := LEN(str); ch := str[0];
	REPEAT
		ch := str[i]; INC(i)
	UNTIL ((ch # 20X) & (ch # 0DX) & (ch # 0AX) & ((ch < 'a') OR ('z' < ch)) & ((ch < 'A') & ('Z' < ch))
			& ((ch < '0') & ('9' < ch)) & (ch # '(') & (ch # ')') & (ch # '+') & (ch # ',') & (ch # '.')
			& (ch # '/') & (ch # ':') & (ch # '=') & (ch # '?') & (ch # ';') & (ch # '!') & (ch # '*') & (ch # '#')
			& (ch # '@') & (ch # '$') & (ch # '_') & (ch # '%')) OR (i >= len);
	RETURN i = len
END IsPubidLiteral;

PROCEDURE IsVoidTag(name: String): BOOLEAN;
BEGIN
	IF name^ = "AREA" THEN RETURN TRUE END;
	IF name^ = "BASE" THEN RETURN TRUE END;
	IF name^ = "BR" THEN RETURN TRUE END;
	IF name^ = "COL" THEN RETURN TRUE END;
	IF name^ = "EMBED" THEN RETURN TRUE END;
	IF name^ = "HR" THEN RETURN TRUE END;
	IF name^ = "IMG" THEN RETURN TRUE END;
	IF name^ = "INPUT" THEN RETURN TRUE END;
	IF name^ = "LINK" THEN RETURN TRUE END;
	IF name^ = "META" THEN RETURN TRUE END;
	IF name^ = "PARAM" THEN RETURN TRUE END;
	IF name^ = "SOURCE" THEN RETURN TRUE END;
	IF name^ = "TRACK" THEN RETURN TRUE END;
	IF name^ = "WBR" THEN RETURN TRUE END;
	(* not in HTML5 *)
	IF name^ = "BASEFONT" THEN RETURN TRUE END;
	IF name^ = "FRAME" THEN RETURN TRUE END;
	IF name^ = "ISINDEX" THEN RETURN TRUE END;
	IF name^ = "KEYGEN" THEN RETURN TRUE END;
	RETURN FALSE
END IsVoidTag;

PROCEDURE PrematureTagClosing(name, next: String): BOOLEAN;
BEGIN
	IF name^ = "COLGROUP" THEN
		IF next^ # "COL" THEN RETURN TRUE END;
	ELSIF name^ = "DD" THEN
		IF (next^ = "DD") OR (next^ = "DT") (*OR (next^ = "DL")*) THEN RETURN TRUE END;
	ELSIF name^ = "DT" THEN
		IF (next^ = "DT") OR (next^ = "DD") OR (next^ = "DL") THEN RETURN TRUE END;
	ELSIF name^ = "HEAD" THEN
		IF next^ = "BODY" THEN RETURN TRUE END;
	ELSIF name^ = "LI" THEN
		IF next^ = "LI" THEN RETURN TRUE END;
	ELSIF name^ = "OPTION" THEN
		RETURN TRUE;
	ELSIF name^ = "P" THEN
		IF next^ = "P" THEN RETURN TRUE END;
	ELSIF name^ = "TBODY" THEN
		IF (next^ = "TBODY") OR (next^ = "THEAD") OR (next^ = "TFOOT") THEN RETURN TRUE END;
	ELSIF name^ = "TD" THEN
		IF (next^ = "TD") OR (next^ = "TH") OR (next^ = "TR") OR (next^ = "THEAD") OR (next^ = "TBODY") OR (next^ = "TFOOT") THEN RETURN TRUE END;
	ELSIF name^ = "TFOOT" THEN
		IF (next^ = "TBODY") OR (next^ = "THEAD") OR (next^ = "TFOOT") THEN RETURN TRUE END;
	ELSIF name^ = "TH" THEN
		IF (next^ = "TD") OR (next^ = "TH") OR (next^ = "TR") OR (next^ = "THEAD") OR (next^ = "TBODY") OR (next^ = "TFOOT") THEN RETURN TRUE END;
	ELSIF name^ = "THEAD" THEN
		IF (next^ = "TBODY") OR (next^ = "THEAD") OR (next^ = "TFOOT") THEN RETURN TRUE END;
	ELSIF name^ = "TR" THEN
		IF (next^ = "TR")  OR (next^ = "THEAD") OR (next^ = "TBODY") OR (next^ = "TFOOT") THEN RETURN TRUE END;
	END;
	RETURN FALSE

	(* The following code is html-standard. but it's too strict to get good results!
	IF name^ = "COLGROUP" THEN
		IF next^ # "COL" THEN RETURN TRUE END;
	ELSIF name^ = "DD" THEN
		IF ~IsFlow(next) THEN RETURN TRUE END;
	ELSIF name^ = "DT" THEN
		IF ~IsInline(next) THEN RETURN TRUE END;
	ELSIF name^ = "HEAD" THEN
		IF next^ = "BODY" THEN RETURN TRUE END;
	ELSIF name^ = "LI" THEN
		IF ~IsFlow(next) THEN RETURN TRUE END;
	ELSIF name^ = "OPTION" THEN
		RETURN TRUE;
	ELSIF name^ = "P" THEN
		IF ~IsInline(next) THEN RETURN TRUE END;
	ELSIF name^ = "TBODY" THEN
		IF next^ # "TR" THEN RETURN TRUE END;
	ELSIF name^ = "TD" THEN
		IF ~IsFlow(next) THEN RETURN TRUE END;
	ELSIF name^ = "TFOOT" THEN
		IF next^ # "TR" THEN RETURN TRUE END;
	ELSIF name^ = "TH" THEN
		IF ~IsFlow(next) THEN RETURN TRUE END;
	ELSIF name^ = "THEAD" THEN
		IF next^ # "TR" THEN RETURN TRUE END;
	ELSIF name^ = "TR" THEN
		IF (next^ # "TH") & (next^ # "TD") THEN RETURN TRUE END;
	END;
	RETURN FALSE
	*)
END PrematureTagClosing;

(*
PROCEDURE IsFlow(name: String): BOOLEAN;
BEGIN
	IF IsInline(name) THEN RETURN TRUE END;
	IF name^ = "P" THEN RETURN TRUE END;
	IF name^ = "H1" THEN RETURN TRUE END;
	IF name^ = "H2" THEN RETURN TRUE END;
	IF name^ = "H3" THEN RETURN TRUE END;
	IF name^ = "H4" THEN RETURN TRUE END;
	IF name^ = "H5" THEN RETURN TRUE END;
	IF name^ = "H6" THEN RETURN TRUE END;
	IF name^ = "UL" THEN RETURN TRUE END;
	IF name^ = "OL" THEN RETURN TRUE END;
	IF name^ = "PRE" THEN RETURN TRUE END;
	IF name^ = "DL" THEN RETURN TRUE END;
	IF name^ = "DIV" THEN RETURN TRUE END;
	IF name^ = "NOSCRIPT" THEN RETURN TRUE END;
	IF name^ = "BLOCKQUOTE" THEN RETURN TRUE END;
	IF name^ = "FORM" THEN RETURN TRUE END;
	IF name^ = "HR" THEN RETURN TRUE END;
	IF name^ = "TABLE" THEN RETURN TRUE END;
	IF name^ = "FIELDSET" THEN RETURN TRUE END;
	IF name^ = "ADDRESS" THEN RETURN TRUE END;
	RETURN FALSE
END IsFlow;

PROCEDURE IsInline(name: String): BOOLEAN;
BEGIN
	IF name^ = "TT" THEN RETURN TRUE END;
	IF name^ = "I" THEN RETURN TRUE END;
	IF name^ = "B" THEN RETURN TRUE END;
	IF name^ = "BIG" THEN RETURN TRUE END;
	IF name^ = "SMALL" THEN RETURN TRUE END;
	IF name^ = "EM" THEN RETURN TRUE END;
	IF name^ = "STRONG" THEN RETURN TRUE END;
	IF name^ = "DFN" THEN RETURN TRUE END;
	IF name^ = "CODE" THEN RETURN TRUE END;
	IF name^ = "SAMP" THEN RETURN TRUE END;
	IF name^ = "KBD" THEN RETURN TRUE END;
	IF name^ = "VAR" THEN RETURN TRUE END;
	IF name^ = "CITE" THEN RETURN TRUE END;
	IF name^ = "ABBR" THEN RETURN TRUE END;
	IF name^ = "ACRONYM" THEN RETURN TRUE END;
	IF name^ = "A" THEN RETURN TRUE END;
	IF name^ = "IMG" THEN RETURN TRUE END;
	IF name^ = "OBJECT" THEN RETURN TRUE END;
	IF name^ = "BR" THEN RETURN TRUE END;
	IF name^ = "SCRIPT" THEN RETURN TRUE END;
	IF name^ = "MAP" THEN RETURN TRUE END;
	IF name^ = "Q" THEN RETURN TRUE END;
	IF name^ = "SUB" THEN RETURN TRUE END;
	IF name^ = "SUP" THEN RETURN TRUE END;
	IF name^ = "SPAN" THEN RETURN TRUE END;
	IF name^ = "BDO" THEN RETURN TRUE END;
	IF name^ = "INPUT" THEN RETURN TRUE END;
	IF name^ = "SELECT" THEN RETURN TRUE END;
	IF name^ = "TEXTAREA" THEN RETURN TRUE END;
	IF name^ = "LABEL" THEN RETURN TRUE END;
	IF name^ = "BUTTON" THEN RETURN TRUE END;
	RETURN FALSE
END IsInline;
*)

PROCEDURE (this: Parser) SetStringPooling*(stringPooling : SET), NEW;
BEGIN
	this.scanner.SetStringPooling(stringPooling)
END SetStringPooling;

(** allocates and initializes a new parser;
	e = NIL means to use the default (silent) error handler;
	string pooling is not used by default
*)
PROCEDURE NewParser*(r: Streams.Reader; e: ErrorHandler): Parser;
	VAR p: Parser;
BEGIN
	NEW(p); p.Init(Scanner.NewScanner(r, e));
	RETURN p
END NewParser;

END W3cHTMLParsers.
