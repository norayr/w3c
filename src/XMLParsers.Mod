MODULE W3cXMLParsers;

(* This module provides an DOM parser with string pooling capability.

Original author: Stefan Walthert (swalthert).
Ported from A2 Oberon build 7131 to BlackBox Component Pascal, J. Templ, 2017-05-10.
*)

IMPORT Strings,
	DStrings := W3cDStrings,
	Scanner := W3cXMLScanners,
	DOM := W3cDOM,
	Streams := W3cStreams;

CONST
	(* String pooling settings *)
	Str_ElementName* = 1;
	Str_AttributeName* = 2;
	(*Str_CharRef* = 10;*)
	Str_EntityRef* = 11;
	Str_EntityValue* = 12;
	Str_AttributeValue* = 13;
	Str_Comment* = 20;
	Str_ProcessingInstruction* = 21;
	Str_CDataSection* = 22;
	Str_SystemLiteral* = 23;
	Str_PublicLiteral* = 24;
	Str_CharData* = 25;
	Str_Other* = 30;
	
	DefaultStringPooling* = {Str_ElementName, Str_AttributeName};

TYPE
	String = DStrings.String;

	Parser* = POINTER TO EXTENSIBLE RECORD
		elemReg*: DOM.ElementRegistry; (* optional factory for DOM nodes *)
		errorHandler-: ErrorHandler;
		scanner: Scanner.Scanner;
		dtd: DOM.DocTypeDecl;
		ds1, ds2: DStrings.DynamicString; (** utility string, { (ds1 # NIL) & (ds2 # NIL) } *)
	END;
	
	ErrorHandler* = Scanner.ErrorHandler;

VAR
	(* read-only *)
	predefinedEntities: ARRAY 5 OF RECORD
		name: ARRAY 5 OF CHAR;
		expanded: CHAR;
	END;

PROCEDURE^ (this: Parser) ParseXMLDecl(): DOM.XMLDecl, NEW;
PROCEDURE^ (this: Parser) ParseDocTypeDecl, NEW;
PROCEDURE^ (this: Parser) ParseProcessingInstruction(): DOM.ProcessingInstruction, NEW;
PROCEDURE^ (this: Parser) ParseComment(): DOM.Comment, NEW;
PROCEDURE^ (this: Parser) ParseElement(): DOM.Element, NEW;
PROCEDURE^ (this: Parser) ParseTextDecl(): DOM.TextDecl, NEW;
PROCEDURE^ (this: Parser) ParseCharData(): DOM.ArrayChars, NEW;
PROCEDURE^ (this: Parser) ParseCharData(): DOM.ArrayChars, NEW;
(*PROCEDURE^ (this: Parser) ParseCharRef(): DOM.CharReference, NEW;
PROCEDURE^ (this: Parser) ParseEntityRef(): DOM.EntityRef, NEW;*)
PROCEDURE^ (this: Parser) ParseCDataSect(): DOM.CDataSect, NEW;
PROCEDURE^ (this: Parser) ParseSystemLiteral(): String, NEW;
PROCEDURE^ (this: Parser) ParsePubidLiteral(): String, NEW;
PROCEDURE^ (this: Parser) ParseMarkupDecls, NEW;
PROCEDURE^ (this: Parser) ParseElementDecl(dtd: DOM.DocTypeDecl), NEW;
PROCEDURE^ (this: Parser) ParseAttListDecl(dtd: DOM.DocTypeDecl), NEW;
PROCEDURE^ (this: Parser) ParseEntityDecl(dtd: DOM.DocTypeDecl), NEW;
PROCEDURE^ (this: Parser) ParseNotationDecl(dtd: DOM.DocTypeDecl), NEW;
PROCEDURE^ (this: Parser) ParseContentParticle(VAR contentType: INTEGER): DOM.CollectionCP, NEW;
PROCEDURE^ (this: Parser) ParseAttributeValue(): String, NEW;
PROCEDURE^ (this: Parser) ParseElementContent(): DOM.ContentParticle, NEW;
PROCEDURE^ (this: Parser) ParseEntityValue(): String, NEW;
PROCEDURE^ (this: Parser) ExpandCharacterRefs(s: String): String, NEW;
PROCEDURE^ (this: Parser) ParseStartTag(VAR e: DOM.Element; VAR empty: BOOLEAN), NEW;
PROCEDURE^ (this: Parser) ParseEndTag(e: DOM.Element), NEW;
PROCEDURE^ (this: Parser) ParseAttribute(): DOM.Attribute, NEW;
PROCEDURE^ IsPubidLiteral(VAR str: ARRAY OF CHAR): BOOLEAN;
PROCEDURE^ StrToInt(str: ARRAY OF CHAR): LONGINT;
PROCEDURE^ ExpandPredefinedEntity(VAR name: ARRAY OF CHAR): CHAR;

(* initializes a parser with the given scanner. String pooling is turned off initially. *)
PROCEDURE (this: Parser) Init*(scanner: Scanner.Scanner), NEW;
BEGIN
	this.scanner := scanner; this.errorHandler := scanner.errorHandler;
	NEW(this.ds1); this.ds1.Init; NEW(this.ds2); this.ds2.Init;
END Init;

PROCEDURE (this: Parser) Error(VAR msg: ARRAY OF CHAR), NEW;
BEGIN
	this.scanner.errorHandler.ReportError(this.scanner.GetPos(), this.scanner.line, this.scanner.col, msg);
		(* note: continuing after an error may lead into an infinite loop; not tested *)
	this.errorHandler.cont := FALSE;
	IF ~this.errorHandler.cont THEN this.scanner.r.ok := FALSE END

END Error;

PROCEDURE (this: Parser) CheckSymbol(expectedSymbols: SET; VAR errormsg: ARRAY OF CHAR): BOOLEAN, NEW;
BEGIN
	IF ~(this.scanner.sym VAR expectedSymbols) THEN
		this.Error(errormsg); RETURN FALSE
	ELSE
		RETURN TRUE
	END
END CheckSymbol;

PROCEDURE (this: Parser) ExpandCharacterRef(num: LONGINT): CHAR, NEW;
BEGIN
	RETURN CHR(SHORT(SHORT(num)))
END ExpandCharacterRef;

PROCEDURE (this: Parser) ExpandEntityRef(VAR name: ARRAY OF CHAR; type: INTEGER): String, NEW;
	VAR generalEntity: DOM.EntityDecl;
BEGIN
	IF this.dtd # NIL THEN
		generalEntity := this.dtd.GetEntityDecl(name, type);
		IF generalEntity # NIL THEN
			RETURN generalEntity.GetValue()
		ELSE
			RETURN NIL;
		END
	ELSE
		RETURN NIL;
	END;
END ExpandEntityRef;

PROCEDURE (this: Parser) Parse*(): DOM.Document, NEW;
	VAR doc: DOM.Document; e: DOM.Element; s: String;
BEGIN
	NEW(doc); doc.Init(); doc.SetPos(this.scanner.GetPos()); this.dtd := doc.GetDocTypeDecl();
	this.scanner.ScanContent();	(* prolog *)
	IF this.scanner.sym = Scanner.TagXMLDeclOpen THEN	(* XMLDecl? *)
		doc.AddContent(this.ParseXMLDecl());
		this.scanner.ScanContent()
	END;
	WHILE (this.scanner.sym # Scanner.TagDeclOpen) & (this.scanner.sym # Scanner.TagElemStartOpen) DO (* Misc* *)
		CASE this.scanner.sym OF
		| Scanner.TagPIOpen: doc.AddContent(this.ParseProcessingInstruction())
		| Scanner.Comment: doc.AddContent(this.ParseComment())
		ELSE
			this.Error("unknown DOM content "
				+ "(Document Type Declaration, Processing Instruction, Comment or Root Element expected)");
			RETURN doc
		END;
		this.scanner.ScanContent()
	END;
	IF this.scanner.sym = Scanner.TagDeclOpen THEN	(* (doctypedecl Misc* )? *)
		s := this.scanner.GetString(Str_Other);				(* doctypedecl .. *)
		IF s^ = 'DOCTYPE' THEN
			this.ParseDocTypeDecl(); doc.AddContent(this.dtd)
		ELSE
			this.Error("'<!DOCTYPE' expected"); RETURN doc
		END;
		this.scanner.ScanContent();
		WHILE (this.scanner.sym # Scanner.TagElemStartOpen) DO	(* .. Misc* *)
			CASE this.scanner.sym OF
			| Scanner.TagPIOpen: doc.AddContent(this.ParseProcessingInstruction())
			| Scanner.Comment: doc.AddContent(this.ParseComment())
			| Scanner.TagElemStartOpen: (* do nothing *)
			ELSE this.Error("unknown DOM content (Processing Instruction, Comment or Root Element expected)");
				RETURN doc
			END;
			this.scanner.ScanContent()
		END
	END;
	e := this.ParseElement();
	IF e = NIL THEN RETURN NIL END;
	doc.AddContent(e);	(* element *)
	this.scanner.ScanContent();
	WHILE this.scanner.sym # Scanner.Eof DO	(* Misc* *)
		CASE this.scanner.sym OF
		| Scanner.TagPIOpen: doc.AddContent(this.ParseProcessingInstruction())
		| Scanner.Comment: doc.AddContent(this.ParseComment())
		| Scanner.Eof: (* do nothing *)
		ELSE this.Error("unknown DOM content (Processing Instruction, Comment or End of file expected)");
			RETURN doc
		END;
		this.scanner.ScanContent()
	END;
	RETURN doc
END Parse;

PROCEDURE (this: Parser) ParseExtGenEntity*(extEntityRef: DOM.ExternalEntityRef), NEW;
BEGIN
	this.scanner.ScanContent();
	IF this.scanner.sym = Scanner.TagXMLDeclOpen THEN
		extEntityRef.AddContent(this.ParseTextDecl());
		this.scanner.ScanContent()
	END;
	REPEAT
		CASE this.scanner.sym OF
		| Scanner.CharData: extEntityRef.AddContent(this.ParseCharData())
		| Scanner.TagElemStartOpen: extEntityRef.AddContent(this.ParseElement())
		(*| Scanner.CharRef: extEntityRef.AddContent(this.ParseCharRef())
		| Scanner.EntityRef: extEntityRef.AddContent(this.ParseEntityRef())*)
		| Scanner.CDataSect: extEntityRef.AddContent(this.ParseCDataSect())
		| Scanner.Comment: extEntityRef.AddContent(this.ParseComment())
		| Scanner.TagPIOpen: extEntityRef.AddContent(this.ParseProcessingInstruction())
		| Scanner.TagElemEndOpen: (* do nothing *)
		| Scanner.Eof: this.Error("element not closed"); RETURN
		ELSE
			this.Error("unknown Element Content"); RETURN
		END;
		this.scanner.ScanContent()
	UNTIL this.scanner.sym = Scanner.Eof
END ParseExtGenEntity;

PROCEDURE (this: Parser) ParseXMLDecl(): DOM.XMLDecl, NEW;
	VAR decl: DOM.XMLDecl; s: String;
BEGIN
	NEW(decl); decl.Init; decl.SetPos(this.scanner.GetPos());
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Name}, "'version' expected") THEN RETURN decl END;
	s := this.scanner.GetString(Str_Other);
	IF s^ # "version" THEN this.Error("'version' expected"); RETURN decl END;
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Equal}, "'=' expected") THEN RETURN decl END;
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Literal}, "Version Number expected") THEN RETURN decl END;
	s := this.scanner.GetString(Str_Other);
	decl.SetVersion(s^);
	this.scanner.ScanMarkup(); s := this.scanner.GetString(Str_Other);
	IF (this.scanner.sym = Scanner.Name) & (s^ = "encoding") THEN
		this.scanner.ScanMarkup();
		IF ~this.CheckSymbol({Scanner.Equal}, "'=' expected") THEN RETURN decl END;
		this.scanner.ScanMarkup();
		IF ~this.CheckSymbol({Scanner.Literal}, "Encoding Name expected") THEN RETURN decl END;
		s := this.scanner.GetString(Str_Other);
		decl.SetEncoding(s^);
		this.scanner.ScanMarkup(); s := this.scanner.GetString(Str_Other)
	END;
	IF (this.scanner.sym = Scanner.Name) & (s^ = "standalone") THEN
		this.scanner.ScanMarkup();
		IF ~this.CheckSymbol({Scanner.Equal}, "'=' expected") THEN RETURN decl END;
		this.scanner.ScanMarkup();
		IF ~this.CheckSymbol({Scanner.Literal}, '"yes" or "no" expected') THEN RETURN decl END;
		s := this.scanner.GetString(Str_Other);
		IF s^ = "yes" THEN decl.SetStandalone(TRUE)
		ELSIF s^ = "no" THEN decl.SetStandalone(FALSE)
		ELSE this.Error('"yes" or "no" expected'); RETURN decl
		END;
		this.scanner.ScanMarkup()
	END;
	IF ~this.CheckSymbol({Scanner.TagPIClose}, "'?>' expected") THEN RETURN decl END;
	RETURN decl
END ParseXMLDecl;

PROCEDURE (this: Parser) ParseTextDecl(): DOM.TextDecl, NEW;
	VAR decl: DOM.TextDecl; s: String;
BEGIN
	NEW(decl); decl.Init; decl.SetPos(this.scanner.GetPos());
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Name}, "'version' expected") THEN RETURN decl END;
	s := this.scanner.GetString(Str_Other);
	IF s^ # "version" THEN this.Error("'version' expected"); RETURN decl END;
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Equal}, "'=' expected") THEN RETURN decl END;
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Literal}, "Version Number expected") THEN RETURN decl END;
	s := this.scanner.GetString(Str_Other);
	decl.SetVersion(s^);
	this.scanner.ScanMarkup(); s := this.scanner.GetString(Str_Other);
	IF (this.scanner.sym = Scanner.Name) & (s^ = "encoding") THEN
		this.scanner.ScanMarkup();
		IF ~this.CheckSymbol({Scanner.Equal}, "'=' expected") THEN RETURN decl END;
		this.scanner.ScanMarkup();
		IF ~this.CheckSymbol({Scanner.Literal}, "Encoding Name expected") THEN RETURN decl END;
		s := this.scanner.GetString(Str_Other);
		decl.SetEncoding(s^);
		this.scanner.ScanMarkup(); s := this.scanner.GetString(Str_Other)
	END;
	IF ~this.CheckSymbol({Scanner.TagPIClose}, "'?>' expected") THEN RETURN decl END;
	RETURN decl
END ParseTextDecl;

PROCEDURE (this: Parser) ParseComment(): DOM.Comment, NEW;
	VAR comment: DOM.Comment; s: String;
BEGIN
	NEW(comment); comment.Init; comment.SetPos(this.scanner.GetPos());
	s := this.scanner.GetString(Str_Comment);
	comment.SetStrAsString(s);
	RETURN comment
END ParseComment;

PROCEDURE (this: Parser) ParseProcessingInstruction(): DOM.ProcessingInstruction, NEW;
	VAR pi: DOM.ProcessingInstruction; s: String;
BEGIN
	NEW(pi); pi.Init; pi.SetPos(this.scanner.GetPos());
	s := this.scanner.GetString(Str_ProcessingInstruction);
	pi.SetTarget(s^);
	this.scanner.ScanPInstruction();
	IF ~this.CheckSymbol({Scanner.TagPIClose}, "'?>' expected") THEN RETURN pi END;
	s := this.scanner.GetString(Str_ProcessingInstruction);
	pi.SetInstruction(s^);
	RETURN pi
END ParseProcessingInstruction;

PROCEDURE (this: Parser) ParseDocTypeDecl, NEW;
	VAR externalSubset: DOM.EntityDecl; s: String;
BEGIN
	NEW(this.dtd); this.dtd.Init(); this.dtd.SetPos(this.scanner.GetPos());
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Name}, "DTD name expected") THEN RETURN END;
	s := this.scanner.GetString(Str_Other); this.dtd.SetNameAsString(s);
	this.scanner.ScanMarkup();
	IF this.scanner.sym = Scanner.Name THEN	(* DTD points to external subset *)
		NEW(externalSubset); externalSubset.Init; externalSubset.SetPos(this.scanner.GetPos());
		s := this.scanner.GetString(Str_Other);
		IF s^ = 'SYSTEM' THEN
			s := this.ParseSystemLiteral();
			externalSubset.SetSystemId(s^)
		ELSIF s^ = 'PUBLIC' THEN
			s := this.ParsePubidLiteral();
			externalSubset.SetPublicId(s^);
			s := this.ParseSystemLiteral();
			externalSubset.SetSystemId(s^)
		ELSE
			this.Error("'SYSTEM' or 'PUBLIC' expected"); RETURN
		END;
		this.dtd.SetExternalSubset(externalSubset);
		this.scanner.ScanMarkup()
	END;
	IF this.scanner.sym = Scanner.BracketOpen THEN	(* markupdecl *)
		this.ParseMarkupDecls()
	END;
	IF ~this.CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN END;
END ParseDocTypeDecl;

PROCEDURE (this: Parser) ParseMarkupDecls, NEW;
	VAR s: String; (* oldscanner: Scanner.Scanner; *)
BEGIN
	REPEAT
		this.scanner.ScanMarkup();
		CASE this.scanner.sym OF
		| Scanner.TagDeclOpen:
				s := this.scanner.GetString(Str_Other);
				IF s^ = 'ELEMENT' THEN
					this.ParseElementDecl(this.dtd)
				ELSIF s^ = 'ATTLIST' THEN
					this.ParseAttListDecl(this.dtd)
				ELSIF s^ = 'ENTITY' THEN
					this.ParseEntityDecl(this.dtd)
				ELSIF s^ = 'NOTATION' THEN
					this.ParseNotationDecl(this.dtd)
				ELSE
					this.Error("'ELEMENT', 'ATTLIST', 'ENTITY' or 'NOTATION' expected"); RETURN
				END
		|Scanner.TagPIOpen: this.dtd.AddMarkupDecl(this.ParseProcessingInstruction())
		| Scanner.Comment: this.dtd.AddMarkupDecl(this.ParseComment())
	(*	| Scanner.ParamEntityRef:
			s := scanner.GetStr();
			s := ExpandEntityRef(s^, DOM.ParameterEntity);
			f := Files.New(""); Files.OpenWriter(w, f, 0); w.Bytes(s^, 0, LEN(s^) - 1); w.Update;
			oldscanner := scanner;
			NEW(scanner, f);
			ParseMarkupDecls();
			scanner := oldscanner *)
		| Scanner.BracketClose: (* end of markupdecl *)
		| Scanner.Eof, Scanner.Invalid: RETURN
		ELSE
			this.Error("unknown markup declaration"); RETURN
		END
	UNTIL this.scanner.sym = Scanner.BracketClose;
	this.scanner.ScanMarkup()
END ParseMarkupDecls;

(*
	elementdecl ::=	'<!ELEMENT' S Name S contentspec S? '>"
	contentspec ::=	'EMPTY' | 'ANY' | Mixed | children
	S ::=			(#x20 | #x9 | #xD | #xA)+
*)
PROCEDURE (this: Parser) ParseElementDecl(dtd: DOM.DocTypeDecl), NEW;
	VAR ed: DOM.ElementDecl; ccp: DOM.CollectionCP; s: String;
		contentType: INTEGER;
BEGIN
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Name}, "Element name expected") THEN RETURN END;
	s := this.scanner.GetString(Str_ElementName);
	ed := dtd.GetElementDecl(s^);
	IF ed = NIL THEN (* Attribute List Declaration not occured yet -> create new element declaration and add it to the DTD *)
		NEW(ed); ed.Init; ed.SetPos(this.scanner.GetPos());
		ed.SetNameAsString(s);
		dtd.AddMarkupDecl(ed)
	END;
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Name, Scanner.ParenOpen}, "'EMPTY', 'ANY', Mixed or Element Content expected") THEN
		RETURN END;
	IF this.scanner.sym = Scanner.Name THEN
		s := this.scanner.GetString(Str_Other);
		IF s^ = 'EMPTY' THEN
			ed.SetContentType(DOM.Empty)
		ELSIF s^ = 'ANY' THEN
			ed.SetContentType(DOM.Any)
		ELSE
			this.Error("'EMPTY' or 'ANY' expected"); RETURN
		END;
		this.scanner.ScanMarkup();
		IF ~this.CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN END;
	ELSIF this.scanner.sym = Scanner.ParenOpen THEN	(* Mixed or children element content *)
		ccp := this.ParseContentParticle(contentType);
		ed.SetContent(ccp);
		ed.SetContentType(contentType)
	END
END ParseElementDecl;

PROCEDURE (this: Parser) ParseAttListDecl(dtd: DOM.DocTypeDecl), NEW;
	VAR ed: DOM.ElementDecl; ad: DOM.AttributeDecl; s: String;
BEGIN
	this.scanner.ScanMarkup();	(* parse element name *)
	IF ~this.CheckSymbol({Scanner.Name}, "Element name expected") THEN RETURN END;
	s := this.scanner.GetString(Str_AttributeName);
	ed := dtd.GetElementDecl(s^);
	IF ed = NIL THEN	(* Element Declaration not occured yet -> create new element declaration and add it to the DTD *)
		NEW(ed); ed.Init; ed.SetPos(this.scanner.GetPos());
		ed.SetNameAsString(s);
		dtd.AddMarkupDecl(ed)
	END;
	this.scanner.ScanMarkup();
	WHILE (this.scanner.sym # Scanner.TagClose) DO	(* parse AttDefs *)
		IF ~this.CheckSymbol({Scanner.Name}, "Attribute Name expected") THEN RETURN END;
		s := this.scanner.GetString(Str_AttributeName); NEW(ad); ad.Init; ad.SetPos(this.scanner.GetPos());
		ad.SetNameAsString(s);
		this.scanner.ScanMarkup();
		IF ~this.CheckSymbol({Scanner.Name, Scanner.ParenOpen}, "Attribute Type expected") THEN RETURN END;
		IF this.scanner.sym = Scanner.Name THEN
			s := this.scanner.GetString(Str_Other);
			IF s^ = 'CDATA' THEN ad.SetType(DOM.CData)
			ELSIF s^ = 'ID' THEN ad.SetType(DOM.Id)
			ELSIF s^ = 'IDREF' THEN ad.SetType(DOM.IdRef)
			ELSIF s^ = 'IDREFS' THEN ad.SetType(DOM.IdRefs)
			ELSIF s^ = 'ENTITY' THEN ad.SetType(DOM.Entity)
			ELSIF s^ = 'ENTITIES' THEN ad.SetType(DOM.Entities)
			ELSIF s^ = 'NMTOKEN' THEN ad.SetType(DOM.NmToken)
			ELSIF s^ = 'NMTOKENS' THEN ad.SetType(DOM.NmTokens)
			ELSIF s^ = 'NOTATION' THEN
				ad.SetType(DOM.Notation);
				this.scanner.ScanMarkup();
				IF ~this.CheckSymbol({Scanner.ParenOpen}, "'(' expected") THEN RETURN END;
				this.scanner.ScanMarkup();
				IF ~this.CheckSymbol({Scanner.Name}, "Notation Name expected") THEN RETURN END;
				this.scanner.ScanMarkup()
			ELSE this.Error("Attribute Type expected"); RETURN
			END
		ELSIF this.scanner.sym = Scanner.ParenOpen THEN
			ad.SetType(DOM.Enumeration);
			this.scanner.ScanMarkup();
			IF ~this.CheckSymbol({Scanner.Name, Scanner.Nmtoken}, "Value Nmtoken expected") THEN RETURN END;
		END;
		IF (ad.GetType() = DOM.Notation) OR (ad.GetType() = DOM.Enumeration) THEN
			WHILE (this.scanner.sym = Scanner.Name) OR
					((this.scanner.sym = Scanner.Nmtoken) & (ad.GetType() = DOM.Enumeration)) DO
				s := this.scanner.GetString(Str_Other);
				ad.AddAllowedValue(s^);
				this.scanner.ScanMarkup();
				IF this.scanner.sym = Scanner.Or THEN
					this.scanner.ScanMarkup()
				END
			END;
			IF ~this.CheckSymbol({Scanner.ParenClose}, "')' expected") THEN RETURN END;
		END;
		this.scanner.ScanMarkup();
		s := this.scanner.GetString(Str_Other);	(* parse DefaultDecl *)
		IF ~this.CheckSymbol({Scanner.PoundName, Scanner.Literal},
			"'#REQUIRED', '#IMPLIED', '#FIXED' or AttValue expected") THEN RETURN END;
		IF this.scanner.sym = Scanner.PoundName THEN
			IF (s^ = '#REQUIRED') THEN
				ad.SetRequired(TRUE)
			 ELSIF (s^ = '#FIXED') THEN
				ad.SetRequired(TRUE);
				this.scanner.ScanMarkup();
				IF ~this.CheckSymbol({Scanner.Literal}, "AttValue expected") THEN RETURN END
			ELSIF (s^ = '#IMPLIED') THEN
				ad.SetRequired(FALSE)
			ELSE
				this.Error("'#REQUIRED', '#IMPLIED' or '#FIXED' expected"); RETURN
			END
		ELSIF this.scanner.sym = Scanner.Literal THEN
			ad.SetRequired(FALSE)
		END;
		IF (this.scanner.sym = Scanner.Literal) THEN
			s := this.ParseAttributeValue();
			ad.SetDefaultValue(s^)
		END;
		this.scanner.ScanMarkup();
		ed.AddAttributeDecl(ad);
	END;
	IF ~this.CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN END;
END ParseAttListDecl;

(*
	Mixed 		::=	'(' S? '#PCDATA' (S? '|' S? Name)* S? ')*'
					| '(' S? '#PCDATA' S? ')'

	children		::=	(choice | seq) ('?' | '*' | '+')?
	cp 			::=	(Name | choice | seq) ('?' | '*' | '+')?
	choice 		::=	'(' S? cp (S? '|' S? cp)+ S? ')'
	seq			::=	'(' S? cp (S? ',' S? cp)* S? ')'
*)
PROCEDURE (this: Parser) ParseContentParticle(VAR contentType: INTEGER): DOM.CollectionCP, NEW;
	VAR cp: DOM.ContentParticle; ncp: DOM.NameContentParticle; ccp: DOM.CollectionCP; s: String;
BEGIN ccp := NIL;
	IF ~this.CheckSymbol({Scanner.ParenOpen}, "'(' expected") THEN RETURN ccp END;
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Name, Scanner.PoundName, Scanner.ParenOpen},
			"Element Name, '#PCDATA' or '(' expected") THEN RETURN ccp END;
	IF this.scanner.sym = Scanner.PoundName THEN
		contentType := DOM.MixedContent;
		s := this.scanner.GetString(Str_Other);
		IF s^ = '#PCDATA' THEN
			NEW(ncp); ncp.Init; ncp.SetPos(this.scanner.GetPos()); ncp.SetNameAsString(s); ncp.SetOccurence(DOM.Once);
			NEW(ccp); ccp.Init; ccp.SetType(DOM.Choice); ccp.AddChild(ncp);
			this.scanner.ScanMarkup();
			IF ~this.CheckSymbol({Scanner.ParenClose, Scanner.Or}, "')' or '|' expected") THEN RETURN ccp END;
			IF this.scanner.sym = Scanner.ParenClose THEN
				this.scanner.ScanMarkup();
				IF ~this.CheckSymbol({Scanner.Asterisk, Scanner.TagClose}, "'*' or '>' expected") THEN RETURN ccp END;
				IF this.scanner.sym = Scanner.Asterisk THEN
					ccp.SetOccurence(DOM.ZeroOrMore);
					this.scanner.ScanMarkup();
					IF ~this.CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN ccp END
				ELSIF this.scanner.sym = Scanner.TagClose THEN
					ccp.SetOccurence(DOM.Once)
				END;
				cp := ccp
			ELSIF this.scanner.sym = Scanner.Or THEN
				WHILE this.scanner.sym = Scanner.Or DO
					this.scanner.ScanMarkup();
					IF ~this.CheckSymbol({Scanner.Name}, "Element Name expected") THEN RETURN ccp END;
					s := this.scanner.GetString(Str_Other); NEW(ncp); ncp.Init; ncp.SetPos(this.scanner.GetPos());
					ncp.SetNameAsString(s); ncp.SetOccurence(DOM.Once);
					ccp.AddChild(ncp);
					this.scanner.ScanMarkup();
					IF ~this.CheckSymbol({Scanner.ParenClose, Scanner.Or}, "')' or '|' expected") THEN RETURN ccp END
				END;
				this.scanner.ScanMarkup();
				IF ~this.CheckSymbol({Scanner.Asterisk}, "'*' expected") THEN RETURN ccp END;
				ccp.SetOccurence(DOM.ZeroOrMore);
				this.scanner.ScanMarkup();
				IF ~this.CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN ccp END;
				cp := ccp
			END
		ELSE
			this.Error('"#PCDATA" expected'); RETURN ccp
		END
	ELSE
		cp := this.ParseElementContent();
		IF ~this.CheckSymbol({Scanner.Or, Scanner.Comma, Scanner.ParenClose}, "'|' or ',' expected") THEN
			RETURN ccp
		END;
		IF this.scanner.sym = Scanner.Or THEN
			NEW(ccp); ccp.Init;
			ccp.SetType(DOM.Choice); ccp.AddChild(cp);
			REPEAT
				this.scanner.ScanMarkup();
				ccp.AddChild(this.ParseElementContent());
				IF ~this.CheckSymbol({Scanner.Or, Scanner.ParenClose}, "'|' or ')' expected") THEN RETURN ccp END;
			UNTIL this.scanner.sym = Scanner.ParenClose;
			cp := ccp
		ELSIF this.scanner.sym = Scanner.Comma THEN
			NEW(ccp); ccp.Init;
			ccp.SetType(DOM.Sequence); ccp.AddChild(cp);
			REPEAT
				this.scanner.ScanMarkup();
				ccp.AddChild(this.ParseElementContent());
				IF ~this.CheckSymbol({Scanner.Comma, Scanner.ParenClose}, "',' or ')' expected") THEN RETURN ccp END;
			UNTIL this.scanner.sym = Scanner.ParenClose;
			cp := ccp
		ELSIF this.scanner.sym = Scanner.ParenClose THEN
			NEW(ccp); ccp.Init;
			ccp.SetType(DOM.Sequence); ccp.AddChild(cp);
			cp := ccp;
		END;
		this.scanner.ScanMarkup();
		CASE this.scanner.sym OF
		| Scanner.Question: cp.SetOccurence(DOM.ZeroOrOnce);
			this.scanner.ScanMarkup(); IF ~this.CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN ccp END
		| Scanner.TagPIClose: cp.SetOccurence(DOM.ZeroOrOnce)
		| Scanner.Asterisk: cp.SetOccurence(DOM.ZeroOrMore);
			this.scanner.ScanMarkup(); IF ~this.CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN ccp END
		| Scanner.Plus: cp.SetOccurence(DOM.OnceOrMore);
			this.scanner.ScanMarkup(); IF ~this.CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN ccp END
		ELSE cp.SetOccurence(DOM.Once);
			IF ~this.CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN ccp END
		END
	END;
	RETURN cp(DOM.CollectionCP)
END ParseContentParticle;

PROCEDURE (this: Parser) ParseElementContent(): DOM.ContentParticle, NEW;
	VAR cp: DOM.ContentParticle; ncp: DOM.NameContentParticle; ccp: DOM.CollectionCP; s: String;
BEGIN cp := NIL;
	IF ~this.CheckSymbol({Scanner.Name, Scanner.ParenOpen}, "Element Name or '(' expected") THEN RETURN cp END;
	IF this.scanner.sym = Scanner.Name THEN
		NEW(ncp); ncp.Init; ncp.SetPos(this.scanner.GetPos()); s := this.scanner.GetString(Str_Other);
		ncp.SetNameAsString(s); cp := ncp
	ELSIF this.scanner.sym = Scanner.ParenOpen THEN
		this.scanner.ScanMarkup();
		cp := this.ParseElementContent();
		IF ~this.CheckSymbol({Scanner.Or, Scanner.Comma}, "'|' or ',' expected") THEN RETURN cp END;
		IF this.scanner.sym = Scanner.Or THEN
			NEW(ccp); ccp.Init; ccp.SetPos(this.scanner.GetPos());
			ccp.SetType(DOM.Choice); ccp.AddChild(cp);
			REPEAT
				this.scanner.ScanMarkup();
				ccp.AddChild(this.ParseElementContent());
				IF ~this.CheckSymbol({Scanner.Or, Scanner.ParenClose}, "'|' or ')' expected") THEN RETURN cp END;
			UNTIL this.scanner.sym = Scanner.ParenClose;
			cp := ccp
		ELSIF this.scanner.sym = Scanner.Comma THEN
			NEW(ccp); ccp.Init; ccp.SetPos(this.scanner.GetPos());
			ccp.SetType(DOM.Sequence); ccp.AddChild(cp);
			REPEAT
				this.scanner.ScanMarkup();
				ccp.AddChild(this.ParseElementContent());
				IF ~this.CheckSymbol({Scanner.Comma, Scanner.ParenClose}, "',' or ')' expected") THEN RETURN cp END
			UNTIL this.scanner.sym = Scanner.ParenClose;
			cp := ccp
		END
	END;
	this.scanner.ScanMarkup();
	CASE this.scanner.sym OF
	| Scanner.Question: cp.SetOccurence(DOM.ZeroOrOnce); this.scanner.ScanMarkup()
	| Scanner.Asterisk: cp.SetOccurence(DOM.ZeroOrMore); this.scanner.ScanMarkup()
	| Scanner.Plus: cp.SetOccurence(DOM.OnceOrMore); this.scanner.ScanMarkup()
	ELSE cp.SetOccurence(DOM.Once)
	END;
	RETURN cp
END ParseElementContent;

PROCEDURE (this: Parser) ParseEntityDecl(dtd: DOM.DocTypeDecl), NEW;
	VAR ed: DOM.EntityDecl; s: String;
BEGIN
	NEW(ed); ed.Init;
	ed.SetPos(this.scanner.GetPos());
	this.scanner.ScanMarkup();
	IF this.scanner.sym = Scanner.Percent THEN	(* Parameter Entity Decl *)
		ed.SetType(DOM.ParameterEntity);
		this.scanner.ScanMarkup()
	ELSE	(* General Entity Declaration *)
		ed.SetType(DOM.GeneralEntity);
	END;
	IF ~this.CheckSymbol({Scanner.Name}, "Entity Declaration Name expected") THEN RETURN END;
	s := this.scanner.GetString(Str_Other);
	ed.SetNameAsString(s);
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Literal, Scanner.Name}, "EntityValue, 'SYSTEM' or 'PUBLIC' expected") THEN 
		RETURN 
	END;
	IF this.scanner.sym = Scanner.Literal THEN	(* EntityValue *)
		s := this.ParseEntityValue();
		ed.SetValue(s^);
		this.scanner.ScanMarkup()
	ELSIF this.scanner.sym = Scanner.Name THEN	(* ExternalID *)
		s := this.scanner.GetString(Str_Other);
		IF s^ = 'SYSTEM' THEN
			s := this.ParseSystemLiteral();
			ed.SetSystemId(s^);
			this.scanner.ScanMarkup()
		ELSIF s^ = 'PUBLIC' THEN
			s := this.ParsePubidLiteral();
			ed.SetPublicId(s^);
			s := this.ParseSystemLiteral();
			ed.SetSystemId(s^);
			this.scanner.ScanMarkup()
		ELSE
			this.Error("'SYSTEM' or 'PUBLIC' expected"); RETURN
		END;
		IF (this.scanner.sym = Scanner.Name) & (ed.GetType() = DOM.GeneralEntity) THEN
			s := this.scanner.GetString(Str_Other);
			IF s^ = 'NDATA' THEN	(* NDataDecl *)
				this.scanner.ScanMarkup();
				IF ~this.CheckSymbol({Scanner.Name}, "Notation Name expected") THEN RETURN END;
				s := this.scanner.GetString(Str_Other);
				ed.SetNotationName(s^);
				this.scanner.ScanMarkup()
			ELSE
				this.Error("'NDATA' expected"); RETURN
			END
		END
	ELSE
		this.Error("EntityValue or SystemId expected"); RETURN
	END;
	IF ~this.CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN END;
	dtd.AddMarkupDecl(ed)
END ParseEntityDecl;

PROCEDURE (this: Parser) ParseNotationDecl(dtd: DOM.DocTypeDecl), NEW;
	VAR nd: DOM.NotationDecl; s: String;
BEGIN
	NEW(nd); nd.Init; nd.SetPos(this.scanner.GetPos());
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Name}, "Notation Name expected") THEN RETURN END;
	s := this.scanner.GetString(Str_Other);
	nd.SetNameAsString(s);
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Name}, "'PUBLIC' or 'SYSTEM' expected") THEN RETURN END;
	s := this.scanner.GetString(Str_Other);
	IF s^ = 'PUBLIC' THEN
		s := this.ParsePubidLiteral();
		nd.SetPublicId(s^);
		this.scanner.ScanMarkup();
		IF this.scanner.sym = Scanner.Literal THEN	(* ExternalID 1 *)
			s := this.scanner.GetString(Str_Other);
			nd.SetSystemId(s^);
			this.scanner.ScanMarkup()
		ELSE	(* PublicID, nothing more *)
		END
	ELSIF s^ = 'SYSTEM' THEN	(* ExternalID 2 *)
		s := this.ParseSystemLiteral();
		nd.SetSystemId(s^);
		this.scanner.ScanMarkup()
	END;
	IF ~this.CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN END;
	dtd.AddMarkupDecl(nd)
END ParseNotationDecl;

PROCEDURE (this: Parser) ParseSystemLiteral(): String, NEW;
	VAR systemLiteral: String;
BEGIN
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Literal}, "System Literal expected") THEN RETURN NIL END;
	systemLiteral := this.scanner.GetString(Str_SystemLiteral);
	RETURN systemLiteral
END ParseSystemLiteral;

PROCEDURE (this: Parser) ParsePubidLiteral(): String, NEW;
	VAR pubidLiteral: String;
BEGIN
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Literal}, "PubidLiteral expected") THEN RETURN NIL END;
	pubidLiteral := this.scanner.GetString(Str_PublicLiteral);
	IF ~IsPubidLiteral(pubidLiteral^) THEN this.Error("not a correct Pubid Literal"); RETURN pubidLiteral END;
	RETURN pubidLiteral
END ParsePubidLiteral;

PROCEDURE (this: Parser) ParseCDataSect(): DOM.CDataSect, NEW;
	VAR cds: DOM.CDataSect; s: String;
BEGIN
	NEW(cds); cds.Init; cds.SetPos(this.scanner.GetPos());
	s := this.scanner.GetString(Str_CDataSection);
	cds.SetStrAsString(s);
	RETURN cds
END ParseCDataSect;

PROCEDURE (this: Parser) ParseCharData(): DOM.ArrayChars, NEW;
	VAR cd: DOM.ArrayChars; s: String;
BEGIN
	NEW(cd); cd.Init;
	cd.SetPos(this.scanner.GetPos());
	s := this.scanner.GetString(Str_CharData);
	s := this.ExpandCharacterRefs(s);
	cd.SetStrAsString(s);
	RETURN cd
END ParseCharData;

PROCEDURE (this: Parser) ParseElement(): DOM.Element, NEW;
	VAR e: DOM.Element; empty: BOOLEAN;
BEGIN
	this.ParseStartTag(e, empty);
	IF e = NIL THEN RETURN NIL END;
	IF ~empty THEN
		REPEAT
			this.scanner.ScanContent();
			CASE this.scanner.sym OF
			| Scanner.CharData: e.AddContent(this.ParseCharData() )
			| Scanner.TagElemStartOpen: e.AddContent(this.ParseElement())
			(*| Scanner.CharRef: e.AddContent(this.ParseCharRef())
			| Scanner.EntityRef: e.AddContent(this.ParseEntityRef())*)
			| Scanner.CDataSect: e.AddContent(this.ParseCDataSect())
			| Scanner.Comment: e.AddContent(this.ParseComment())
			| Scanner.TagPIOpen: e.AddContent(this.ParseProcessingInstruction())
			| Scanner.TagElemEndOpen: (* do nothing *)
			| Scanner.Eof: this.Error("element not closed"); RETURN e
			ELSE
				this.Error("unknown Element Content"); RETURN e
			END
		UNTIL this.scanner.sym = Scanner.TagElemEndOpen;
		this.ParseEndTag(e);
	END;
	RETURN e
END ParseElement;

PROCEDURE (this: Parser) ParseStartTag(VAR e: DOM.Element; VAR empty: BOOLEAN), NEW;
	VAR s: String; firstInstantiationFailed: BOOLEAN;
BEGIN
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Name}, "Element Name expected") THEN RETURN END;
	s := this.scanner.GetString(Str_ElementName);
	IF this.elemReg # NIL THEN
		e := this.elemReg.InstantiateElement(s^)
	END;
	IF e = NIL THEN
		firstInstantiationFailed := TRUE; NEW(e); e.Init
	ELSE
		firstInstantiationFailed := FALSE;
	END;
	e.SetPos(this.scanner.GetPos());
	e.SetNameAsString(s);
	this.scanner.ScanMarkup();
	WHILE this.scanner.sym = Scanner.Name DO
		e.AddAttribute(this.ParseAttribute());
		this.scanner.ScanMarkup();
	END;
	IF (this.elemReg # NIL) & (firstInstantiationFailed) THEN
		e := this.elemReg.InstantiateLate(e);
		e.SetNameAsString(s);
	END;
	IF ~this.CheckSymbol({Scanner.TagEmptyElemClose, Scanner.TagClose}, "'/>' or '>' expected") THEN RETURN END;
	IF this.scanner.sym = Scanner.TagEmptyElemClose THEN
		empty := TRUE
	ELSIF this.scanner.sym = Scanner.TagClose THEN
		empty := FALSE
	END
END ParseStartTag;

PROCEDURE (this: Parser) ParseAttribute(): DOM.Attribute, NEW;
	VAR a: DOM.Attribute; s: String;
BEGIN
	NEW(a); a.Init; a.SetPos(this.scanner.GetPos());
	s := this.scanner.GetString(Str_AttributeName);
	a.SetNameAsString(s);
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Equal}, "'=' expected") THEN RETURN a END;
	this.scanner.ScanMarkup();
	IF ~this.CheckSymbol({Scanner.Literal}, "Attribute Value expected") THEN RETURN a END;
	s := this.ParseAttributeValue();
	a.SetValueAsString(s);
	RETURN a
END ParseAttribute;

PROCEDURE (this: Parser) ParseEndTag(e: DOM.Element), NEW;
	VAR ds: DStrings.DynamicString; s1, s2: String; msg: ARRAY 12 OF CHAR;
BEGIN
	this.scanner.ScanMarkup();
	s1 := this.scanner.GetString(Str_ElementName); s2 := e.GetName();
	IF (this.scanner.sym = Scanner.Name) & (s1^ = s2^) THEN
		this.scanner.ScanMarkup();
		IF ~this.CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN END;
	ELSE
		NEW(ds); ds.Init;
		msg := "'</'"; ds.Append(msg); ds.Append(s2^);
		msg := ">' expected"; ds.Append(msg); s1 := ds.ToString();
		this.Error(s1^); RETURN
	END
END ParseEndTag;

PROCEDURE (this: Parser) ExpandCharacterRefs(s: String): String, NEW;
	VAR
		from, to: LONGINT;
		ch: CHAR;

	PROCEDURE ReplaceEntity(VAR source: ARRAY OF CHAR; VAR srcPos: LONGINT;
												VAR dest: ARRAY OF CHAR; VAR destPos: LONGINT);
		VAR ch: CHAR; name: ARRAY 32 OF CHAR; sp, np: LONGINT; xch: CHAR;
	BEGIN
		ASSERT(source[srcPos] = "&");
		sp := srcPos + 1; np := 0;
		REPEAT
			ch := source[sp];
			name[np] := ch;
			INC(sp); INC(np);
		UNTIL (ch = ";") OR (ch = 0X) OR (np >= LEN(name));
		name[np - 1] := 0X;
		IF ch = ";" THEN
			xch := ExpandPredefinedEntity(name);
			IF xch # 0X THEN dest[destPos] := xch; INC(destPos); srcPos := sp - 1
			ELSE dest[destPos] := "&"; INC(destPos)
			END;
		ELSE this.Error("unclosed reference")
		END;
		INC(srcPos);
	END ReplaceEntity;

BEGIN
	(* we make use of the fact that the "expansion" is actually always a shrinkage and therefore make change in place ! *)
	from := 0;
	WHILE (s[from] # "&") & (s[from] # 0X) DO INC(from) END;
	to := from;
	REPEAT
		ch := s[from];
		IF ch = "&" THEN
			ReplaceEntity(s^, from, s^, to);
		ELSE
			s[to] := ch;
			INC(from); INC(to);
		END;
	UNTIL ch = 0X;
	RETURN s
END ExpandCharacterRefs;

PROCEDURE (this: Parser) ParseEntityValue(): String, NEW;
	VAR s, es: String; xch: CHAR; start, end, len, val: LONGINT; msg: ARRAY 17 OF CHAR;
BEGIN
	s := this.scanner.GetString(Str_EntityValue);
	this.ds1.Clear; this.ds1.Append(s^);
	start := 0; len := this.ds1.length;
	WHILE start < len DO
		WHILE (start < len) & ((this.ds1.Get(start) # '&') OR (this.ds1.Get(start + 1) # '#')) & (this.ds1.Get(start) # '%') DO
			INC(start)
		END;
		IF ((this.ds1.Get(start) = '&') & (this.ds1.Get(start + 1) = '#')) OR (this.ds1.Get(start) = '%') THEN
			end := start + 1;
			WHILE (end < len) & (this.ds1.Get(end) # ';') DO
				INC(end)
			END;
			IF this.ds1.Get(end) = ';' THEN
				this.ds2.Clear;
				s := this.ds1.Extract(0, start);	(* literal before reference *)
				this.ds2.Append(s^);
				IF (this.ds1.Get(start) = '&') & (this.ds1.Get(start + 1) = '#') THEN	(* character reference *)
					s := this.ds1.Extract(start + 2, end - start - 1);
					val := StrToInt(s^);
					msg[0] := this.ExpandCharacterRef(val);
					msg[1] := 0X;
					this.ds2.Append(msg);
					start := start + 1;
				ELSE	(* predefined entity or parameter entity reference *)
					s := this.ds1.Extract(start + 1, end - start - 1);	(* reference name *)
					xch := ExpandPredefinedEntity(s^);
					IF (xch # 0X) THEN
						start := start + 1; (* don't expand reference again *)
						this.ds2.AppendChar(xch);
					ELSE
						es := this.ExpandEntityRef(s^, DOM.ParameterEntity);	(* reference value *)
						IF es = NIL THEN
							NEW(this.ds2); this.ds2.Init();
							msg := 'unknown entity "'; this.ds2.Append(msg);
							es := this.ds1.Extract(start + 1, end - start - 1); this.ds2.Append(es^);
							msg := '"'; this.ds2.Append(msg);
							es := this.ds2.ToString();
							this.Error(es^); RETURN this.ds1.ToString()
						END;
						this.ds2.Append(es^);
					END;
				END;
				s := this.ds1.Extract(end + 1, len - end -1);	(* literal after reference *)
				this.ds2.Append(s^);
				this.ds1.CopyFrom(this.ds2, 0, this.ds2.length);
				len := this.ds1.length
			ELSE
				this.Error("';' expected (unclosed reference)"); RETURN this.ds1.ToString()
			END
		END
	END;
	RETURN this.ds1.ToString()
END ParseEntityValue;

PROCEDURE (this: Parser) ParseAttributeValue(): String, NEW;
	VAR s: String;
BEGIN
	s := this.scanner.GetString(Str_AttributeValue);
	RETURN this.ExpandCharacterRefs(s);
END ParseAttributeValue;

(*PROCEDURE (this: Parser) ParseCharRef(): DOM.CharReference, NEW;
	VAR cRef: DOM.CharReference; code, res: LONGINT; s: String;
BEGIN
	s := this.scanner.GetString(Scanner.CharRef);
	code := StrToInt(s^);
	NEW(cRef); cRef.Init; cRef.SetPos(this.scanner.GetPos());
	cRef.SetCode(code);
	RETURN cRef;
END ParseCharRef;*)

(*PROCEDURE (this: Parser) ParseEntityRef(): DOM.EntityRef, NEW;
	VAR ext: DOM.ExternalEntityRef; int: DOM.InternalEntityRef; s1, s2: String; ent: DOM.EntityDecl;
BEGIN
	s1 := this.scanner.GetString(Str_EntityRef);
	ent := this.dtd.GetEntityDecl(s1^, DOM.GeneralEntity);
	IF ent # NIL THEN
		s2 := ent.GetValue();
		IF s2 # NIL THEN
			NEW(int); int.Init; int.SetPos(this.scanner.GetPos());
			int.SetNameAsString(s1);
			RETURN int
		ELSE
			NEW(ext); ext.Init; ext.SetPos(this.scanner.GetPos());
			ext.SetNameAsString(s1);
			RETURN ext
		END
	ELSE
		RETURN NIL
	END
END ParseEntityRef;*)

PROCEDURE IsPubidLiteral(VAR str: ARRAY OF CHAR): BOOLEAN;
	VAR i, len: LONGINT; ch: CHAR;
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

PROCEDURE StrToInt(str: ARRAY OF CHAR): LONGINT;
	VAR val, res: LONGINT;
BEGIN
	IF str[0] = 'x' THEN	(* str in hexadecimal form *)
		Strings.ToUpper(str, str);
	END;
	Strings.StringToInt(str, val, res);
	ASSERT(res = 0);
	RETURN val
END StrToInt;

PROCEDURE ExpandPredefinedEntity(VAR name: ARRAY OF CHAR): CHAR;
	VAR i: LONGINT;
BEGIN
	FOR i := 0 TO LEN(predefinedEntities) - 1 DO
		IF (name = predefinedEntities[i].name) THEN
			RETURN predefinedEntities[i].expanded;
		END;
	END;
	RETURN 0X;
END ExpandPredefinedEntity;

PROCEDURE Init;
BEGIN
	predefinedEntities[0].name := "lt"; predefinedEntities[0].expanded := "<";
	predefinedEntities[1].name := "gt"; predefinedEntities[1].expanded := ">";
	predefinedEntities[2].name := "amp"; predefinedEntities[2].expanded := "&";
	predefinedEntities[3].name := "apos"; predefinedEntities[3].expanded := "'";
	predefinedEntities[4].name := "quot"; predefinedEntities[4].expanded := '"';
END Init;

PROCEDURE (this: Parser) SetStringPooling*(stringPooling: SET), NEW;
BEGIN
	this.scanner.SetStringPooling(stringPooling)
END SetStringPooling;

(** allocates and initializes a new parser;
	e = NIL means to use the default (silent) error handler;
	string pooling is not used by default
*)
PROCEDURE NewParser*(r: Streams.Reader; e: ErrorHandler): Parser;
	VAR parser: Parser;
BEGIN
	NEW(parser); parser.Init(Scanner.NewScanner(r, e));
	RETURN parser
END NewParser;

BEGIN
	Init;
END W3cXMLParsers.