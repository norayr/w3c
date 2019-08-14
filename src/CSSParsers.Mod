MODULE W3cCSSParsers;

(* This module provides a CSS2 parser with string pooling capability.

Original author: Stefan Walthert (swalthert).
Ported from A2 Oberon build 7131 to BlackBox Component Pascal, J. Templ, 2017-05-10.
*)

IMPORT Files,
	DStrings := W3cDStrings,
	Streams := W3cStreams,
	Objects := W3cObjects,
	Scanner := W3cCSSScanners,
	CSS := W3cCSS;

CONST
	(* String pooling settings *)
	Str_Other* = 0; (* one time strings, usually not pooled *)
	Str_Keyword* = 1;
	Str_Selector* = 2;
	Str_Property* = 10;
	Str_Dimension* = 11;
	Str_Function* = 12;
	Str_String* = 13;
	Str_Ident* = 14;
	Str_URI* = 15;
	Str_Hash* = 16;

	DefaultStringPooling* =
		{Str_Keyword, Str_Selector, Str_Property, Str_Dimension, Str_Function, Str_String, Str_Ident};
	
TYPE
	String = CSS.String;

	Parser* = POINTER TO RECORD
		importLoc-: Files.Locator;
		errorHandler-: ErrorHandler;
		scanner: Scanner.Scanner;
	END;
	
	ErrorHandler* = Scanner.ErrorHandler;

PROCEDURE^ (this: Parser) Error(VAR msg: ARRAY OF CHAR), NEW;
PROCEDURE^ (this: Parser) ParseImport(styleSheet: CSS.StyleSheet), NEW;
PROCEDURE^ (this: Parser) ParseMedia(styleSheet: CSS.StyleSheet), NEW;
PROCEDURE^ (this: Parser) ParsePage(): CSS.Page, NEW;
PROCEDURE^ (this: Parser) ParseFontFace(): CSS.FontFace, NEW;
PROCEDURE^ (this: Parser) IgnoreKeyword, NEW;
PROCEDURE^ (this: Parser) ParseRuleSet(): CSS.RuleSet, NEW;
PROCEDURE^ (this: Parser) ParseDeclaration(): CSS.Declaration, NEW;
PROCEDURE^ (this: Parser) ParseId(): CSS.Id, NEW;
PROCEDURE^ (this: Parser) ParseClass(): CSS.Class, NEW;
PROCEDURE^ (this: Parser) ParseSelector(): CSS.Selector, NEW;
PROCEDURE^ (this: Parser) ParseSimpleSelector(): CSS.SimpleSelector, NEW;
PROCEDURE^ (this: Parser) ParseAttribute(): CSS.Attribute, NEW;
PROCEDURE^ (this: Parser) ParsePseudo(): CSS.Pseudo, NEW;
PROCEDURE^ (this: Parser) ParseExpr*(): CSS.Term, NEW;
PROCEDURE^ (this: Parser) ParseRGB(hasAlpha: BOOLEAN): LONGINT, NEW;
PROCEDURE^ GetMedium(mediumStr: ARRAY OF CHAR): INTEGER;
PROCEDURE^ GetPseudoPage(pseudoPageStr: ARRAY OF CHAR): INTEGER;
PROCEDURE^ GetTermUnit(unitStr: ARRAY OF CHAR): INTEGER;
PROCEDURE^ ComputeRGB(VAR s: ARRAY OF CHAR): LONGINT;
PROCEDURE^ HexStrToInt(VAR str: ARRAY OF CHAR; VAR val: LONGINT);

PROCEDURE (this: Parser) Init*(scanner: Scanner.Scanner; importLoc: Files.Locator), NEW;
BEGIN
	this.scanner := scanner;
	this.importLoc := importLoc;
	this.errorHandler := scanner.errorHandler;
	scanner.Scan()
END Init;

PROCEDURE (this: Parser) Reset*(r: Streams.Reader), NEW;
BEGIN
	this.scanner.Reset(r, this.errorHandler);
	this.scanner.Scan()
END Reset;

PROCEDURE (this: Parser) CheckSymbol(expectedSymbols: SET; errormsg: ARRAY OF CHAR): BOOLEAN, NEW;
BEGIN
	IF this.scanner.sym VAR expectedSymbols THEN
		RETURN TRUE
	ELSE
		this.Error(errormsg);
		RETURN FALSE
	END
END CheckSymbol;

PROCEDURE (this: Parser) Error(VAR msg: ARRAY OF CHAR), NEW;
BEGIN
	this.errorHandler.HandleError(this.scanner.GetPos(), this.scanner.line, this.scanner.col, msg);
	(* note: continuing after an error may lead into an infinite loop; not tested *)
	this.errorHandler.cont := FALSE;
	IF ~this.errorHandler.cont THEN this.scanner.r.ok := FALSE END;
END Error;

PROCEDURE (this: Parser) Parse*(): CSS.StyleSheet, NEW;
	VAR styleSheet: CSS.StyleSheet; s: String;
BEGIN
	NEW(styleSheet); styleSheet.Init;
	s := this.scanner.GetStr(Str_Keyword);
	IF (this.scanner.sym = Scanner.AtKeyword) & (s^ = 'charset') THEN
		this.scanner.Scan();
		IF ~this.CheckSymbol({Scanner.String}, "charset expected") THEN RETURN styleSheet END;
		s := this.scanner.GetStr(Str_Other); styleSheet.SetCharSet(s);
		this.scanner.Scan();
		IF ~this.CheckSymbol({Scanner.Semicolon}, "';' expected") THEN RETURN styleSheet END;
		this.scanner.Scan()
	END;
	WHILE this.scanner.sym VAR {Scanner.Cdo, Scanner.Cdc} DO this.scanner.Scan() END;
	s := this.scanner.GetStr(Str_Keyword);
	WHILE (this.scanner.sym = Scanner.AtKeyword) & (s^ = 'import') DO
		this.ParseImport(styleSheet);
		s := this.scanner.GetStr(Str_Keyword)
	END;
	WHILE this.scanner.sym # Scanner.Eof DO
		IF this.scanner.sym = Scanner.AtKeyword THEN
			s := this.scanner.GetStr(Str_Keyword);
			IF s^ = 'media' THEN
				this.ParseMedia(styleSheet)
			ELSIF s^ = 'page' THEN
				styleSheet.AddPage(this.ParsePage())
			ELSIF s^ = 'font-face' THEN
				styleSheet.AddFontFace(this.ParseFontFace())
			ELSE	(* skip unknown atkeyword *)
				this.IgnoreKeyword()
			END
		ELSIF this.scanner.sym # Scanner.Eof THEN
			styleSheet.AddRuleSet(this.ParseRuleSet())
		END;
		WHILE this.scanner.sym VAR {Scanner.Cdo, Scanner.Cdc} DO this.scanner.Scan() END
	END;
	RETURN styleSheet
END Parse;

PROCEDURE (this: Parser) ParseImport(styleSheet: CSS.StyleSheet), NEW;
	VAR s: String; newParser: Parser; newScanner: Scanner.Scanner; file: Files.File;
		importedStyleSheet: CSS.StyleSheet; media, media2, media3: SET; ruleSets: Objects.Enumerator;
		ruleSet: ANYPTR;
BEGIN
	this.scanner.Scan();
	IF ~this.CheckSymbol({Scanner.String, Scanner.URI}, "URI expected") THEN RETURN END;
	s := this.scanner.GetStr(Str_Other);
	file := Files.dir.Old(this.importLoc, s^$, Files.shared);
	IF file # NIL THEN
		newScanner := Scanner.NewScanner(Streams.NewUtf8FileReader(file.NewReader(NIL)), NIL);
		NEW(newParser); newParser.Init(newScanner, this.importLoc);
		importedStyleSheet := newParser.Parse()
	ELSE
		this.Error("imported file not found: " + s)
	END;
	this.scanner.Scan();
	IF this.scanner.sym # Scanner.Ident THEN
		media := {CSS.All}
	ELSE
		s := this.scanner.GetStr(Str_Other);
		media := {GetMedium(s^)};
		this.scanner.Scan();
		WHILE this.scanner.sym = Scanner.Comma DO
			this.scanner.Scan();
			IF ~this.CheckSymbol({Scanner.Ident}, "medium identifier expected") THEN RETURN END;
			s := this.scanner.GetStr(Str_Other);
			INCL(media, GetMedium(s^));
			this.scanner.Scan()
		END
	END;
	ruleSets := importedStyleSheet.GetRuleSets();
	WHILE ruleSets.HasMoreElements() DO
		ruleSet := ruleSets.GetNext();
		media2 := ruleSet(CSS.RuleSet).GetMedia();
		media3 := media + media2;
		IF (media3 - {CSS.All} # {}) THEN media3 := media3 - {CSS.All} END;
		ruleSet(CSS.RuleSet).SetMedia(media3);
		styleSheet.AddRuleSet(ruleSet(CSS.RuleSet))
	END;
	IF ~this.CheckSymbol({Scanner.Semicolon}, "';' expected") THEN RETURN END;
	this.scanner.Scan()
END ParseImport;

PROCEDURE (this: Parser) ParseMedia(styleSheet: CSS.StyleSheet), NEW;
	VAR s: String; media: SET; ruleSet: CSS.RuleSet;
BEGIN
	this.scanner.Scan();
	IF ~this.CheckSymbol({Scanner.Ident}, "medium identifier expected") THEN RETURN END;
	s := this.scanner.GetStr(Str_Other);
	media := {GetMedium(s^)};
	this.scanner.Scan();
	WHILE this.scanner.sym = Scanner.Comma DO
		this.scanner.Scan();
		IF ~this.CheckSymbol({Scanner.Ident}, "medium identifier expected") THEN RETURN END;
		s := this.scanner.GetStr(Str_Other);
		INCL(media, GetMedium(s^));
		this.scanner.Scan()
	END;
	IF ~this.CheckSymbol({Scanner.BraceOpen}, "'{' expected") THEN RETURN END;
	this.scanner.Scan();
	WHILE (this.scanner.sym # Scanner.BraceClose) 
	& (this.scanner.sym # Scanner.Eof) 
	& (this.scanner.sym # Scanner.Invalid) DO
		ruleSet := this.ParseRuleSet();
		ruleSet.SetMedia(media);
		styleSheet.AddRuleSet(ruleSet)
	END;
	IF ~this.CheckSymbol({Scanner.BraceClose}, "'}' expected") THEN RETURN END;
	this.scanner.Scan()
END ParseMedia;

PROCEDURE (this: Parser) ParsePage(): CSS.Page, NEW;
	VAR page: CSS.Page; s: String;
BEGIN
	this.scanner.Scan();
	NEW(page); page.Init;
	IF ~this.CheckSymbol({Scanner.Ident, Scanner.Colon, Scanner.BraceOpen},
			"page selector, pseudo page or '{' expected") THEN RETURN page
	END;
	IF this.scanner.sym = Scanner.Ident THEN
		s := this.scanner.GetStr(Str_Other);
		page.SetSelector(s);
		this.scanner.Scan()
	END;
	IF ~this.CheckSymbol({Scanner.Colon, Scanner.BraceOpen}, "pseudo page or '{' expected") THEN RETURN page END;
	IF this.scanner.sym = Scanner.Colon THEN
		this.scanner.Scan();
		IF ~this.CheckSymbol({Scanner.Ident}, "pseudo page identifier expected") THEN RETURN page END;
		s := this.scanner.GetStr(Str_Other);
		page.SetPseudoPage(GetPseudoPage(s^));
		this.scanner.Scan()
	END;
	IF ~this.CheckSymbol({Scanner.BraceOpen}, "'{' expected") THEN RETURN page END;
	this.scanner.Scan();
	page.AddDeclaration(this.ParseDeclaration());
	WHILE this.scanner.sym = Scanner.Semicolon DO
		this.scanner.Scan();
		page.AddDeclaration(this.ParseDeclaration());
	END;
	IF ~this.CheckSymbol({Scanner.BraceClose}, "'}' expected") THEN RETURN page END;
	this.scanner.Scan();
	RETURN page
END ParsePage;

PROCEDURE (this: Parser) ParseFontFace(): CSS.FontFace, NEW;
	VAR fontFace: CSS.FontFace;
BEGIN
	this.scanner.Scan();
	NEW(fontFace); fontFace.Init;
	IF ~this.CheckSymbol({Scanner.BraceOpen}, "'{' expected") THEN RETURN fontFace END;
	this.scanner.Scan();
	fontFace.AddDeclaration(this.ParseDeclaration());
	WHILE this.scanner.sym = Scanner.Semicolon DO
		this.scanner.Scan();
		fontFace.AddDeclaration(this.ParseDeclaration());
	END;
	IF ~this.CheckSymbol({Scanner.BraceClose}, "'}' expected") THEN RETURN fontFace END;
	this.scanner.Scan();
	RETURN fontFace
END ParseFontFace;

PROCEDURE (this: Parser) ParseRuleSet(): CSS.RuleSet, NEW;
	VAR ruleSet: CSS.RuleSet;
BEGIN
	NEW(ruleSet); ruleSet.Init;
	ruleSet.AddSelector(this.ParseSelector());
	WHILE this.scanner.sym = Scanner.Comma DO
		this.scanner.Scan();
		ruleSet.AddSelector(this.ParseSelector())
	END;
	IF ~this.CheckSymbol({Scanner.BraceOpen}, "'{' expected") THEN RETURN ruleSet END;
	this.scanner.Scan();
	ruleSet.AddDeclaration(this.ParseDeclaration());
	WHILE this.scanner.sym = Scanner.Semicolon DO
		this.scanner.Scan();
		IF this.scanner.sym # Scanner.BraceClose THEN ruleSet.AddDeclaration(this.ParseDeclaration()) END
	END;
	IF ~this.CheckSymbol({Scanner.BraceClose}, "'}' expected") THEN RETURN ruleSet END;
	this.scanner.Scan();
	RETURN ruleSet
END ParseRuleSet;

PROCEDURE (this: Parser) ParseSelector(): CSS.Selector, NEW;
	VAR selector: CSS.Selector;
BEGIN
	NEW(selector); selector.Init;
	selector.AddSimpleSelector(this.ParseSimpleSelector());
	WHILE this.scanner.sym VAR {Scanner.Ident, Scanner.Asterisk, Scanner.Hash, Scanner.Dot, Scanner.BracketOpen,
			Scanner.Colon, Scanner.Greater, Scanner.Plus} DO
		selector.AddSimpleSelector(this.ParseSimpleSelector())
	END;
	RETURN selector
END ParseSelector;

PROCEDURE (this: Parser) ParseSimpleSelector(): CSS.SimpleSelector, NEW;
	VAR simpleSelector: CSS.SimpleSelector; s: String;
BEGIN
	NEW(simpleSelector); simpleSelector.Init;
	IF this.scanner.sym = Scanner.Plus THEN
		simpleSelector.SetCombinator(CSS.Sibling); this.scanner.Scan()
	ELSIF this.scanner.sym = Scanner.Greater THEN
		simpleSelector.SetCombinator(CSS.Child); this.scanner.Scan()
	ELSE
		simpleSelector.SetCombinator(CSS.Descendant)
	END;
	IF this.scanner.sym = Scanner.Ident THEN
		s := this.scanner.GetStr(Str_Selector);
		simpleSelector.SetElementName(s); this.scanner.Scan()
	ELSE
		NEW(s, 2); s[0] := '*'; s[1] := 0X;
		simpleSelector.SetElementName(s);
		IF this.scanner.sym = Scanner.Asterisk THEN this.scanner.Scan() END
	END;
	WHILE this.scanner.sym VAR {Scanner.Hash, Scanner.Dot, Scanner.BracketOpen, Scanner.Colon} DO
		CASE this.scanner.sym OF
		| Scanner.Hash: simpleSelector.AddSubSelector(this.ParseId())
		| Scanner.Dot: simpleSelector.AddSubSelector(this.ParseClass())
		| Scanner.BracketOpen: simpleSelector.AddSubSelector(this.ParseAttribute())
		| Scanner.Colon: simpleSelector.AddSubSelector(this.ParsePseudo())
		ELSE	(* do nothing *)
		END
	END;
	RETURN simpleSelector
END ParseSimpleSelector;

PROCEDURE (this: Parser) ParseId(): CSS.Id, NEW;
	VAR id: CSS.Id; s: String;
BEGIN
	NEW(id);
	IF ~this.CheckSymbol({Scanner.Hash}, "'#'element id expected") THEN RETURN id END;
	s := this.scanner.GetStr(Str_Selector);
	id.SetValue(s);
	this.scanner.Scan();
	RETURN id
END ParseId;

PROCEDURE (this: Parser) ParseClass(): CSS.Class, NEW;
	VAR class: CSS.Class; s: String;
BEGIN
	NEW(class);
	IF ~this.CheckSymbol({Scanner.Dot}, "'.'class value expected") THEN RETURN class END;
	this.scanner.Scan();
	IF ~this.CheckSymbol({Scanner.Ident}, "class value expected") THEN RETURN class END;
	s := this.scanner.GetStr(Str_Selector);
	class.SetValue(s);
	this.scanner.Scan();
	RETURN class
END ParseClass;

PROCEDURE (this: Parser) ParseAttribute(): CSS.Attribute, NEW;
	VAR attribute: CSS.Attribute; s: String;
BEGIN
	NEW(attribute); attribute.Init;
	IF ~this.CheckSymbol({Scanner.BracketOpen}, "'[' expected") THEN RETURN attribute END;
	this.scanner.Scan();
	IF ~this.CheckSymbol({Scanner.Ident}, "attribute name expected") THEN RETURN attribute END;
	s := this.scanner.GetStr(Str_Selector);
	attribute.SetName(s);
	this.scanner.Scan();
	IF this.scanner.sym VAR {Scanner.Equal, Scanner.Includes, Scanner.Dashmatch} THEN
		CASE this.scanner.sym OF
		| Scanner.Equal: attribute.SetRelation(CSS.Equal)
		| Scanner.Includes: attribute.SetRelation(CSS.Includes)
		| Scanner.Dashmatch: attribute.SetRelation(CSS.Dashmatch)
		END;
		this.scanner.Scan();
		IF ~this.CheckSymbol({Scanner.Ident, Scanner.String}, "attribute value expected") THEN RETURN attribute END;
		s := this.scanner.GetStr(Str_Selector);
		attribute.SetValue(s);
		this.scanner.Scan()
	END;
	IF ~this.CheckSymbol({Scanner.BracketClose}, "']' expected") THEN RETURN attribute END;
	this.scanner.Scan();
	RETURN attribute
END ParseAttribute;

PROCEDURE (this: Parser) ParsePseudo(): CSS.Pseudo, NEW;
	VAR pseudo: CSS.Pseudo; s: String;
BEGIN
	NEW(pseudo);
	IF ~this.CheckSymbol({Scanner.Colon}, "':' expected") THEN RETURN pseudo END;
	this.scanner.Scan();
	IF ~this.CheckSymbol({Scanner.Ident, Scanner.Function}, "':'type expected") THEN RETURN pseudo END;
	s := this.scanner.GetStr(Str_Selector);
	pseudo.SetType(s);
	IF (this.scanner.sym = Scanner.Function) & (s^ = 'lang') THEN
		this.scanner.Scan();
		IF ~this.CheckSymbol({Scanner.Ident}, "language expected") THEN RETURN pseudo END;
		s := this.scanner.GetStr(Str_Selector);
		pseudo.SetLanguage(s);
		this.scanner.Scan();
		IF ~this.CheckSymbol({Scanner.ParenClose}, "')' expected") THEN RETURN pseudo END
	END;
	this.scanner.Scan();
	RETURN pseudo
END ParsePseudo;

PROCEDURE (this: Parser) ParseExprList* (declaration: CSS.Declaration), NEW;
BEGIN
	declaration.AddTerm(this.ParseExpr());
	WHILE ~(this.scanner.sym VAR {Scanner.Semicolon, Scanner.BraceClose, Scanner.Important, Scanner.Eof})
			& (this.scanner.sym # Scanner.Invalid) DO	(* expr *)
		this.scanner.Scan();
		declaration.AddTerm(this.ParseExpr())
	END;
END ParseExprList;

PROCEDURE (this: Parser) ParseDeclaration(): CSS.Declaration, NEW;
	VAR declaration: CSS.Declaration; s: String;
BEGIN
	NEW(declaration); declaration.Init;
	IF ~this.CheckSymbol({Scanner.Ident}, "declaration property expected") THEN RETURN declaration END;
	s := this.scanner.GetStrLower(Str_Property);
	declaration.SetProperty(s);
	this.scanner.Scan();
	IF ~this.CheckSymbol({Scanner.Colon}, "':' expected") THEN RETURN declaration END;
	this.scanner.Scan();
	this.ParseExprList(declaration);
	IF this.scanner.sym = Scanner.Important THEN
		declaration.SetImportant(TRUE);
		this.scanner.Scan()
	END;
	RETURN declaration
END ParseDeclaration;

(*TODO JT *)
PROCEDURE (this: Parser) ParseFactor (): CSS.Term, NEW;
	VAR factor: CSS.Term; s: String;
BEGIN
	NEW(factor); factor.Init;
	IF this.scanner.sym = Scanner.Minus THEN
		factor.SetUnaryOperator(CSS.Minus); this.scanner.Scan()
	ELSIF this.scanner.sym = Scanner.Plus THEN
		factor.SetUnaryOperator(CSS.Plus); this.scanner.Scan()
	END;
	CASE this.scanner.sym OF
	| Scanner.Number:
			IF this.scanner.numberType = Scanner.Integer THEN
				factor.SetType(CSS.IntNumber); factor.SetIntVal(this.scanner.intVal)
			ELSIF this.scanner.numberType = Scanner.Real THEN
				factor.SetType(CSS.RealNumber); factor.SetRealVal(this.scanner.realVal)
			END
	| Scanner.Percentage:
			factor.SetType(CSS.Percent);
			IF this.scanner.numberType = Scanner.Integer THEN
				factor.SetRealVal(this.scanner.intVal / 100)
			ELSIF this.scanner.numberType = Scanner.Real THEN
				factor.SetRealVal(this.scanner.realVal / 100)
			END
	| Scanner.Dimension:
			IF this.scanner.numberType = Scanner.Integer THEN
				factor.SetType(CSS.IntDimension); factor.SetIntVal(this.scanner.intVal)
			ELSIF this.scanner.numberType = Scanner.Real THEN
				factor.SetType(CSS.RealDimension); factor.SetRealVal(this.scanner.realVal)
			END;
			s := this.scanner.GetStr(Str_Dimension);
			factor.SetUnit(GetTermUnit(s^))
	| Scanner.Function:
			s := this.scanner.GetStr(Str_Function);
			this.scanner.Scan();
			IF (s^ = 'rgb') OR (s^ = 'rgba') THEN
				factor.SetType(CSS.Color); factor.SetIntVal(this.ParseRGB(s^ = 'rgba')); RETURN factor
			ELSE
				factor.SetType(CSS.Function); factor.SetStringVal(s);
				factor.AddTerm(this.ParseExpr());
				WHILE this.scanner.sym = Scanner.Comma DO
					this.scanner.Scan();
					factor.AddTerm(this.ParseExpr())
				END;
				IF ~this.CheckSymbol({Scanner.ParenClose}, "')' expected") THEN RETURN factor END;
			END
	| Scanner.ParenOpen: (* JT: added *)
			this.scanner.Scan();
			factor := this.ParseExpr();
			IF ~this.CheckSymbol({Scanner.ParenClose}, "')' expected") THEN RETURN factor END;
	| Scanner.String:
			s := this.scanner.GetStr(Str_String);
			factor.SetType(CSS.StringVal); factor.SetStringVal(s)
	| Scanner.Ident:
			s := this.scanner.GetStr(Str_Ident);
			factor.SetType(CSS.StringIdent); factor.SetStringVal(s);
	| Scanner.URI:
			s := this.scanner.GetStr(Str_URI);
			factor.SetType(CSS.URI); factor.SetStringVal(s)
	(* | Scanner.Unicoderange	*)
	| Scanner.Hash:
			s := this.scanner.GetStr(Str_Hash);
			factor.SetType(CSS.Color); factor.SetIntVal(ComputeRGB(s^))
	ELSE
		this.Error("factor starts with invalid symbol")
	END;
	this.scanner.Scan();
	RETURN factor
END ParseFactor;

PROCEDURE (this: Parser) ParseTerm (): CSS.Term, NEW;
	VAR term, mulOp, factor: CSS.Term;
BEGIN
	term := this.ParseFactor();
	WHILE this.scanner.sym VAR {Scanner.Asterisk, Scanner.Slash} DO
		NEW(mulOp); mulOp.Init;
		mulOp.SetType(CSS.Operator);
		IF this.scanner.sym = Scanner.Asterisk THEN mulOp.SetOperator(CSS.Times)
		ELSE mulOp.SetOperator(CSS.Slash)
		END;
		this.scanner.Scan();
		factor := this.ParseFactor();
		mulOp.AddTerm(term); mulOp.AddTerm(factor); term := mulOp
	END;
	RETURN term
END ParseTerm;

PROCEDURE (this: Parser) ParseExpr* (): CSS.Term, NEW;
	VAR expr, addOp, term, first: CSS.Term;
BEGIN
	expr := this.ParseTerm(); first := expr;
	LOOP
		IF this.scanner.sym VAR {Scanner.Plus, Scanner.Minus} THEN
			NEW(addOp); addOp.Init;
			addOp.SetType(CSS.Operator);
			IF this.scanner.sym = Scanner.Plus THEN
				addOp.SetOperator(CSS.Add); this.scanner.Scan()
			ELSIF this.scanner.sym = Scanner.Minus THEN
				addOp.SetOperator(CSS.Sub); this.scanner.Scan()
			END;
			term := this.ParseTerm();
			addOp.AddTerm(expr); addOp.AddTerm(term); expr := addOp
		ELSIF ~(this.scanner.sym VAR {Scanner.Semicolon, Scanner.Comma, Scanner.Colon, Scanner.ParenClose, 
			Scanner.BraceClose, Scanner.BracketClose, Scanner.Important, Scanner.Eof}) THEN
			term := this.ParseTerm();
			IF expr = first THEN
				NEW(addOp); addOp.Init;
				addOp.SetType(CSS.Operator);
				addOp.SetOperator(CSS.Seq);
				addOp.AddTerm(expr); addOp.AddTerm(term); expr := addOp
			ELSE
				addOp.AddTerm(term)
			END
		ELSE EXIT
		END
	END;
	RETURN expr
END ParseExpr;

PROCEDURE (this: Parser) ParseRGB(hasAlpha: BOOLEAN): LONGINT, NEW;
	VAR r, g, b, a: LONGINT;
	
	PROCEDURE ParseAndEval(): LONGINT; (* simplified interpreter *)
		VAR term: CSS.Term; val: LONGINT;
	BEGIN
		term := this.ParseExpr();
		IF (term # NIL) & (term.GetOperator() = CSS.Undefined) & (term.GetUnaryOperator() = CSS.Plus) THEN
			IF (term.GetType() = CSS.Percent) THEN val := SHORT(ENTIER(0.5 + term.GetRealVal() * 255))
			ELSIF (term.GetType() = CSS.IntNumber) THEN val := term.GetIntVal()
			ELSIF (term.GetType() = CSS.RealNumber) THEN val := SHORT(ENTIER(0.5 + term.GetRealVal()))
			ELSE this.Error("<number>'%' expected"); val := 0
			END
		ELSE
			this.Error("<number>'%' expected"); val := 0
		END;
		RETURN val
	END ParseAndEval;
	
BEGIN
	r := ParseAndEval();
	IF this.CheckSymbol({Scanner.Comma}, "',' expected") THEN this.scanner.Scan() END;
	g := ParseAndEval();
	IF this.CheckSymbol({Scanner.Comma}, "',' expected") THEN this.scanner.Scan() END;
	b := ParseAndEval();
	IF hasAlpha THEN
		IF this.CheckSymbol({Scanner.Comma}, "',' expected") THEN this.scanner.Scan() END;
		a := ParseAndEval();
	ELSE
		a := 0
	END;
	IF this.CheckSymbol({Scanner.ParenClose}, "')' expected") THEN this.scanner.Scan() END;
	RETURN ASH(a, 24) + ASH(r, 16) + ASH(g, 8) + b
END ParseRGB;

PROCEDURE (this: Parser) IgnoreKeyword, NEW;
BEGIN
	WHILE ~(this.scanner.sym VAR {Scanner.BraceOpen, Scanner.Semicolon, Scanner.Eof})
	& (this.scanner.sym # Scanner.Invalid) DO
		this.scanner.Scan();
		IF this.scanner.sym = Scanner.AtKeyword THEN this.IgnoreKeyword() END
	END;
	IF ~this.CheckSymbol({Scanner.BraceOpen, Scanner.Semicolon}, "'{' or ';' expected") THEN RETURN END;
	IF this.scanner.sym = Scanner.BraceOpen THEN
		WHILE (this.scanner.sym # Scanner.BraceClose) & (this.scanner.sym # Scanner.Eof) 
		& (this.scanner.sym # Scanner.Invalid) DO
			this.scanner.Scan();
			IF this.scanner.sym = Scanner.AtKeyword THEN this.IgnoreKeyword() END
		END;
		IF ~this.CheckSymbol({Scanner.BraceClose}, "'}' expected") THEN RETURN END
	END;
	this.scanner.Scan()
END IgnoreKeyword;

PROCEDURE GetMedium(mediumStr: ARRAY OF CHAR): INTEGER;
BEGIN
	IF mediumStr = 'all' THEN RETURN CSS.All
	ELSIF mediumStr = 'aural' THEN RETURN CSS.Aural
	ELSIF mediumStr = 'braille' THEN RETURN CSS.Braille
	ELSIF mediumStr = 'embossed' THEN RETURN CSS.Embossed
	ELSIF mediumStr = 'handheld' THEN RETURN CSS.Handheld
	ELSIF mediumStr = 'print' THEN RETURN CSS.Print
	ELSIF mediumStr = 'projection' THEN RETURN CSS.Projection
	ELSIF mediumStr = 'screen' THEN RETURN CSS.Screen
	ELSIF mediumStr = 'tty' THEN RETURN CSS.TTY
	ELSIF mediumStr = 'tv' THEN RETURN CSS.TV
	ELSE RETURN CSS.All
	END
END GetMedium;

PROCEDURE GetPseudoPage(pseudoPageStr: ARRAY OF CHAR): INTEGER;
BEGIN
	IF pseudoPageStr = 'left' THEN RETURN CSS.Left
	ELSIF pseudoPageStr = 'right' THEN RETURN CSS.Right
	ELSIF pseudoPageStr = 'first' THEN RETURN CSS.First
	ELSE RETURN CSS.Undefined
END
END GetPseudoPage;

(*	PROCEDURE GetPseudoType(typeStr: ARRAY OF CHAR): INTEGER;
BEGIN
	IF typeStr = 'first-child' THEN RETURN CSS.FirstChild
	ELSIF typeStr = 'link' THEN RETURN CSS.Link
	ELSIF typeStr = 'visited' THEN RETURN CSS.Visited
	ELSIF typeStr = 'hover' THEN RETURN CSS.Hover
	ELSIF typeStr = 'active' THEN RETURN CSS.Active
	ELSIF typeStr = 'focus' THEN RETURN CSS.Focus
	ELSIF typeStr = 'first-line' THEN RETURN CSS.FirstLine
	ELSIF typeStr = 'first-letter' THEN RETURN CSS.FirstLetter
	ELSIF typeStr = 'before' THEN RETURN CSS.Before
	ELSIF typeStr = 'after' THEN RETURN CSS.After
	ELSE RETURN CSS.Undefined
	END
END GetPseudoType;*)

PROCEDURE GetTermUnit(unitStr: ARRAY OF CHAR): INTEGER;
	VAR unit: INTEGER;
BEGIN
	unit := CSS.Undefined;
	CASE LEN(unitStr$) OF
	| 1: IF unitStr = 's' THEN unit := CSS.s END
	| 2: IF unitStr = 'pt' THEN unit := CSS.pt
		ELSIF unitStr = 'px' THEN unit := CSS.px
		ELSIF unitStr = 'pc' THEN unit := CSS.pc
		ELSIF unitStr = 'mm' THEN unit := CSS.mm
		ELSIF unitStr = 'em' THEN unit := CSS.em
		ELSIF unitStr = 'ex' THEN unit := CSS.ex
		ELSIF unitStr = 'in' THEN unit := CSS.in
		ELSIF unitStr = 'cm' THEN unit := CSS.cm
		ELSIF unitStr = 'ms' THEN unit := CSS.ms
		ELSIF unitStr = 'Hz' THEN unit := CSS.Hz
		ELSIF unitStr = 'ch' THEN unit := CSS.ch
		ELSIF unitStr = 'vw' THEN unit := CSS.vw
		ELSIF unitStr = 'vh' THEN unit := CSS.vh
		END
	| 3: IF unitStr = 'deg' THEN unit := CSS.deg
		ELSIF unitStr = 'grad' THEN unit := CSS.grad
		ELSIF unitStr = 'rad' THEN unit := CSS.rad
		ELSIF unitStr = 'kHz' THEN unit := CSS.kHz
		ELSIF unitStr = 'rem' THEN unit := CSS.rem
		END
	| 4: IF unitStr = 'vmin' THEN unit := CSS.vmin
		ELSIF unitStr = 'vmax' THEN unit := CSS.vmax
		END
	ELSE
	END;
	RETURN unit
END GetTermUnit;

PROCEDURE ComputeRGB(VAR s: ARRAY OF CHAR): LONGINT;
	VAR col: LONGINT; r, g, b, a: LONGINT;
BEGIN
	HexStrToInt(s, col);
	IF (LEN(s$) = 6) OR (LEN(s$) = 8) THEN
		RETURN col
	ELSIF (LEN(s$) = 3) OR (LEN(s$) = 4) THEN
		a := col DIV 1000H; r := (col DIV 100H) MOD 10H; g := (col DIV 10H) MOD 10H; b := col MOD 10H;
		RETURN ASH(a, 28) + ASH(a, 24) + ASH(r, 20) + ASH(r, 16) + ASH(g, 12) + ASH(g, 8) + ASH(b, 4) + b
	ELSE
		RETURN 0
	END
END ComputeRGB;

PROCEDURE HexStrToInt(VAR str: ARRAY OF CHAR; VAR val: LONGINT);
	VAR i, d: LONGINT; ch: CHAR;
BEGIN
	i := 0; ch := str[0];
	WHILE (ch # 0X) & (ch <= " ") DO
		INC(i); ch := str[i]
	END;
	val := 0;
	WHILE (("0" <= ch) & (ch <= "9")) OR (("A" <= ch) & (ch <= "F")) DO
		IF (("0" <= ch) & (ch <= "9")) THEN d := ORD(ch)-ORD("0")
		ELSE d := ORD(ch) - ORD("A") + 10
		END;
		INC(i); ch := str[i];
		val := ASH(val, 4)+d
	END
END HexStrToInt;

(*	PROCEDURE SetKeyword();
	VAR s: DynamicStrings.String;
BEGIN
	sym := Import;
	s := GetStr();
	IF s^ = 'import' THEN keyword := Import
	ELSIF s^ = 'page' THEN keyword := Page
	ELSIF s^ = 'media' THEN keyword := Media
	ELSIF s^ = 'font-face' THEN keyword := FontFace
	ELSIF s^ = 'charset' THEN keyword := CharSet
	ELSE keyword := Unknown
	END
END SetKeyword; *)

(* parses an html inline style attribute *)
PROCEDURE (this: Parser) ParseInlineStyle*(): CSS.RuleSet, NEW;
	VAR ruleSet: CSS.RuleSet;
BEGIN
	NEW(ruleSet); ruleSet.Init;
	ruleSet.AddDeclaration(this.ParseDeclaration());
	WHILE this.scanner.sym = Scanner.Semicolon DO
		this.scanner.Scan();
		IF this.scanner.sym = Scanner.Ident THEN ruleSet.AddDeclaration(this.ParseDeclaration()) END
	END;
	RETURN ruleSet
END ParseInlineStyle;

PROCEDURE (this: Parser) SetStringPooling*(stringPooling : SET), NEW;
BEGIN
	this.scanner.SetStringPooling(stringPooling)
END SetStringPooling;

(** allocates and initializes a new parser;
	e = NIL means to use the default (silent) error handler;
	string pooling is not used by default
*)
PROCEDURE NewParser*(r: Streams.Reader; importLoc: Files.Locator; e: ErrorHandler): Parser;
	VAR p: Parser;
BEGIN
	NEW(p); p.Init(Scanner.NewScanner(r, e), importLoc);
	RETURN p
END NewParser;

END W3cCSSParsers.