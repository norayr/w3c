MODULE W3cDOM;

(* This module provides an abstract syntax tree for XML/HTML according to the W3C document object model (DOM).

Original author: Stefan Walthert (swalthert).
Ported from A2 Oberon build 7131 to BlackBox Component Pascal, J. Templ, 2017-05-10.
*)

IMPORT Strings, Kernel, StdLog,
	Streams := W3cStreams, 
	DStrings := W3cDStrings, 
	Objects := W3cObjects;

CONST
	Ok* = 0;
	InvalidString* = 1;
	BufferError* = 2;

	(** EntityDecl.SetType *)
	GeneralEntity* = 0;
	ParameterEntity* = 1;

	(** ElementDecl.SetContentType *)
	Any* = 0;	(** 'ANY' *)
	Empty* = 1;	(** 'EMPTY' *)
	ElementContent* = 2;	(** children *)
	MixedContent* = 3;	(** Mixed *)

	(** ContentParticle.SetOccurence *)
	ZeroOrOnce* = 0;	(** '?' *)
	ZeroOrMore* = 1;	(** '*' *)
	Once* = 2;	(** nothing *)
	OnceOrMore* = 3;	(** '+' *)

	(** CollectionCP.SetType *)
	Choice* = 1;
	Sequence* = 2;

	(** AttributeDecl.SetType *)
	CData* = 0;	(** CDATA *)
	Id* = 1;	(** ID *)
	IdRef* = 2;	(** IDREF *)
	IdRefs* = 3;	(** IDREFS *)
	Entity* = 4;	(** ENTITY *)
	Entities* = 5;	(** ENTITIES *)
	NmToken* = 6;	(** NMTOKEN *)
	NmTokens* = 7;	(** NMTOKENS *)
	Notation* = 8;	(** NOTATION *)
	Enumeration* = 9;	(** Enumeration *)

	Tab = 09X;
	Space = 20X;

TYPE
	String* = DStrings.String;
	
VAR
	StrNoName: String;

TYPE
	Content* = POINTER TO ABSTRACT RECORD
		pos: LONGINT;
		previous, next: Content;
	END;
	
	NameContent* = POINTER TO EXTENSIBLE RECORD (Content)
		name: String;
	END;

	Container* = POINTER TO ABSTRACT RECORD (Content)
		first, last: Content;
		nofContents: LONGINT;
	END;
	
	Document* = POINTER TO RECORD (Container)
		xmldecl: XMLDecl;
		dtd: DocTypeDecl;
		root: Element;
	END;

	TextDecl* = POINTER TO EXTENSIBLE RECORD (Content)
		version, encoding: String;
	END;

	XMLDecl* = POINTER TO RECORD (TextDecl)
		standalone: BOOLEAN;
	END;
	
	DocTypeDecl* = POINTER TO RECORD (NameContent)
		elementDecls, notationDecls, generalEntities, parameterEntities: Objects.Dictionary;
		allMarkupDecls: Objects.Collection;
		externalSubset: EntityDecl;
	END;
	
	NotationDecl* = POINTER TO EXTENSIBLE RECORD (NameContent)
		systemId, publicId: String;
	END;

	EntityDecl* = POINTER TO RECORD (NotationDecl)
		value, notationName: String;
		type: INTEGER;
	END;

	ElementDecl* = POINTER TO RECORD (NameContent)
		contentType: INTEGER;
		content: CollectionCP;	(* for contentType = Mixed or contentType = Element *)
		attributeDecls: Objects.Dictionary;
	END;

	ContentParticle* = POINTER TO ABSTRACT RECORD (Content)
		occurence: INTEGER;
	END;
	
	NameContentParticle* = POINTER TO RECORD (ContentParticle)
		name: String;
	END;

	ProcessingInstruction* = POINTER TO RECORD (Content)
		target, instruction: String;
	END;
	
	EntityRef* = POINTER TO EXTENSIBLE RECORD (NameContent)
		decl: EntityDecl;
	END;
	
	InternalEntityRef* = POINTER TO RECORD (EntityRef) END;
	
	ExternalEntityRef* = POINTER TO RECORD (EntityRef)
		coll: Objects.Collection;
		textDecl: TextDecl;
	END;

	CollectionCP* = POINTER TO RECORD (ContentParticle)
		children: Objects.Collection;
		type: INTEGER;
	END;

	AttributeDecl* = POINTER TO RECORD (NameContent)
		defaultValue: String;
		type: INTEGER;
		allowedValues: Objects.Dictionary;
		required: BOOLEAN;
	END;
		
	Attribute* = POINTER TO RECORD (NameContent)
		value, elementName: String;
		document: Document;
		decl: AttributeDecl;
	END;
	
	Element* = POINTER TO EXTENSIBLE RECORD (Container)
		root, parent: Element;
		name: String; (* { name # NIL } *)
		document: Document;
		attributes: Attribute;
		idAttribute: Attribute;
	END;

	Chars* = POINTER TO ABSTRACT RECORD (Content) END;

	ArrayChars* = POINTER TO EXTENSIBLE RECORD (Chars)
		str: String;
		len: LONGINT;
	END;
	
	CDataSect* = POINTER TO RECORD (ArrayChars) END;

	Comment* = POINTER TO RECORD (ArrayChars) END;
	
	CharReference* = POINTER TO RECORD (Content)
		code: LONGINT;
	END;

	TraverseProc* = PROCEDURE (c: Content; data: ANYPTR);
	
	GeneratorProcedure* = PROCEDURE;
	
	ElementRegistry* = POINTER TO RECORD
		generators: Objects.Dictionary;
		timestamp: LONGINT;
	END;
	
	ElementEntry* = POINTER TO RECORD
		name-: ARRAY 32 OF CHAR;
		generator-: GeneratorProcedure;
		generatorModule-, generatorProcedure-: Kernel.Name;
	END;

	ElementArray* = POINTER TO ARRAY OF ElementEntry;


VAR
	generatedElement*: Element; (* return value from generator command *)

PROCEDURE^ (this: Element) SetDocument*(document: Document), NEW, EXTENSIBLE;
PROCEDURE^ (this: Element) GetIdElement*(VAR name, id: ARRAY OF CHAR): Element, NEW, EXTENSIBLE;
PROCEDURE^ (this: Element) GetAttribute*(VAR name: ARRAY OF CHAR): Attribute, NEW, EXTENSIBLE;
PROCEDURE^ (this: Element) AddAttribute*(attribute: Attribute), NEW, EXTENSIBLE;
PROCEDURE^ (this: NotationDecl) GetPublicId*(): String, NEW;
PROCEDURE^ (this: NotationDecl) GetSystemId*(): String, NEW;
PROCEDURE^ NewLine(w: Streams.Writer; level: LONGINT);
PROCEDURE^ EscapeString(w: Streams.Writer; VAR string: ARRAY OF CHAR);


(* ------ Content ------ *)

PROCEDURE (this: Content) Init*, NEW, EXTENSIBLE;
BEGIN
	this.pos := 0; this.previous := NIL; this.next := NIL;
END Init;

PROCEDURE (this: Content) GetPos*(): LONGINT, NEW, EXTENSIBLE;
BEGIN
	RETURN this.pos
END GetPos;

PROCEDURE (this: Content) SetPos*(pos: LONGINT), NEW, EXTENSIBLE;
BEGIN
	this.pos := pos
END SetPos;

(** write the content to stream w. level is the current hierarchy level. used for formatting *)
PROCEDURE (this: Content) Write*(w: Streams.Writer; context: ANYPTR; level: LONGINT), NEW, ABSTRACT;
	
	
(* ------ NameContent ------ *)

PROCEDURE (this: NameContent) Init*, EXTENSIBLE;
BEGIN
	this.Init^;
	this.name := StrNoName;
END Init;

PROCEDURE (this: NameContent) GetName*(): String, NEW;
BEGIN
	RETURN this.name
END GetName;

PROCEDURE (this: NameContent) SetName*(VAR name: ARRAY OF CHAR), NEW;
BEGIN
	this.name := DStrings.NewString(name)
END SetName;

PROCEDURE (this: NameContent) SetNameAsString*(name: String), NEW;
BEGIN
	IF (name # NIL) THEN
		this.name := name;
	ELSE
		this.name := StrNoName;
	END;
END SetNameAsString;

PROCEDURE (this: NameContent) Write*(w: Streams.Writer; context: ANYPTR; level: LONGINT), EXTENSIBLE;
BEGIN
	w.String(this.name^)
END Write;


(* ------ Container ------ *)

PROCEDURE (this: Container) Init*, EXTENSIBLE;
BEGIN
	this.Init^;
	this.first := NIL; this.last := NIL;
	this.nofContents := 0;
END Init;

PROCEDURE (this: Container) RemoveContent0(c: Content): BOOLEAN, NEW;
	VAR cur: Content;
BEGIN
	(*ASSERT(c # NIL);*)
	IF c=NIL THEN RETURN FALSE END;(*PH 12/13*)
	IF (this.first # NIL) THEN
		IF (this.first = c) THEN
			IF (this.first.next # NIL) THEN this.first.next.previous := NIL; END;
			this.first := this.first.next;
			IF (this.last = c) THEN this.last := NIL; ASSERT(this.first = NIL); END;
			c.next := NIL; c.previous := NIL;
			RETURN TRUE
		ELSE
			cur := this.first;
			WHILE (cur.next # NIL) & (cur.next # c) DO cur := cur.next; END;
			IF (cur.next # NIL) THEN
				IF (cur.next.next # NIL) THEN cur.next.next.previous := cur; END;
				cur.next := cur.next.next;
				IF (this.last = c) THEN this.last := cur; ASSERT(cur.next = NIL); END;
				c.next := NIL; c.previous := NIL;
				RETURN TRUE
			END;
		END;
	END;
	RETURN FALSE
END RemoveContent0;

(* Move c after previous. If previous = NIL then move c to end *)
PROCEDURE (this: Container) MoveContentAfter*(c, previous: Content), NEW;
BEGIN
	IF this.RemoveContent0(c) THEN
		IF (previous = NIL) OR (previous = this.last) THEN (* insert as last *)
			IF this.last = NIL THEN
				this.first := c; this.last := c
			ELSE
				this.last.next := c;
				c.previous := this.last;
				this.last := c;
			END;
		ELSE
			c.next := previous.next;
			c.next.previous := c;
			previous.next := c;
			c.previous := previous;
		END
	END;
END MoveContentAfter;

(* Move c before next. If next = NIL then move c to front *)
PROCEDURE (this: Container) MoveContentBefore*(c, next: Content), NEW;
BEGIN
	IF this.RemoveContent0(c) THEN
		IF (next = NIL) OR (next = this.first) THEN (* insert as first *)
			IF this.first = NIL THEN
				this.first := c; this.last := c
			ELSE
				c.next := this.first;
				this.first.previous := c;
				this.first := c;
			END;
		ELSE
			next.previous.next := c;
			c.previous := next.previous;
			c.next := next;
			next.previous := c;
		END;
	END;
END MoveContentBefore;

PROCEDURE (this: Container) AddContent*(c: Content), NEW, EXTENSIBLE;
BEGIN
	ASSERT((c # NIL) & (c.next = NIL) & (c.previous = NIL)); (* may not be in more than one list! *)
	IF (this.first = NIL) THEN
		ASSERT(this.last = NIL);
		this.first := c; this.last := c;
	ELSE
		ASSERT(this.last # NIL);
		this.last.next := c;
		c.previous := this.last;
		this.last := c;
	END;
	ASSERT((this.first # NIL) & (this.last # NIL));
	INC(this.nofContents);
END AddContent;

PROCEDURE (this: Container) RemoveContent*(c: Content), NEW, EXTENSIBLE;
BEGIN
	IF this.RemoveContent0(c) THEN DEC(this.nofContents) END
END RemoveContent;

PROCEDURE (this: Container) GetContents*(): Objects.Enumerator, NEW;
	VAR c: Content; array: Objects.PTRArray; enumerator: Objects.ArrayEnumerator; i: LONGINT;
BEGIN
	NEW(array, MAX(this.nofContents, 1));
	c := this.first;
	FOR i := 0 TO this.nofContents - 1 DO
		array[i] := c;
		c := c.next;
	END;
	enumerator := Objects.NewArrayEnumerator(array);
	RETURN enumerator;
END GetContents;

PROCEDURE (this: Container) GetNumberOfContents*(): LONGINT, NEW;
BEGIN
	RETURN this.nofContents;
END GetNumberOfContents;

PROCEDURE (this: Container) GetFirst*(): Content, NEW;
BEGIN
	RETURN this.first;
END GetFirst;

PROCEDURE (this: Container) GetLast*(): Content, NEW;
BEGIN
	RETURN this.last;
END GetLast;

PROCEDURE (this: Container) GetNext*(content: Content): Content, NEW;
BEGIN
	ASSERT(content # NIL);
	RETURN content.next;
END GetNext;

PROCEDURE (this: Container) GetPrevious*(content: Content): Content, NEW;
BEGIN
	ASSERT(content # NIL);
	RETURN content.previous;
END GetPrevious;


(* ------ Document ------ *)

PROCEDURE (this: Document) Init*;
BEGIN
	this.Init^;
	this.xmldecl := NIL;
	NEW(this.dtd); this.dtd.Init;
	this.root := NIL;
END Init;

PROCEDURE (this: Document) GetXMLDecl*(): XMLDecl, NEW;
BEGIN
	RETURN this.xmldecl
END GetXMLDecl;

PROCEDURE (this: Document) GetDocTypeDecl*(): DocTypeDecl, NEW;
BEGIN
	RETURN this.dtd
END GetDocTypeDecl;

PROCEDURE (this: Document) GetRoot*(): Element, NEW;
BEGIN
	RETURN this.root
END GetRoot;

PROCEDURE (this: Document) AddContent*(c: Content);
BEGIN
	IF (c IS XMLDecl) & (this.xmldecl = NIL) THEN this.xmldecl := c(XMLDecl)
	ELSIF (c IS DocTypeDecl) THEN this.dtd := c(DocTypeDecl)
	ELSIF (c IS Element) & (this.root = NIL) THEN this.root := c(Element); this.root.SetDocument(this)
	END;
	this.AddContent^(c)
END AddContent;

PROCEDURE (this: Document) Write*(w: Streams.Writer; context: ANYPTR; level: LONGINT);
	VAR e: Objects.Enumerator; c: ANYPTR;
BEGIN
	e := this.GetContents();
	WHILE e.HasMoreElements() DO
		c := e.GetNext();
		c(Content).Write(w, context, level + 1)
	END
END Write;


(* ------ TextDecl ------ *)

PROCEDURE (this: TextDecl) Init*, EXTENSIBLE;
BEGIN
	this.Init^;
	this.version := NIL; this.encoding := NIL;
END Init;

PROCEDURE (this: TextDecl) GetVersion*(): String, NEW;
BEGIN
	RETURN this.version
END GetVersion;

PROCEDURE (this: TextDecl) SetVersion*(VAR version: ARRAY OF CHAR), NEW;
BEGIN
	this.version := DStrings.NewString(version)
END SetVersion;

PROCEDURE (this: TextDecl) GetEncoding*(): String, NEW;
BEGIN
	RETURN this.encoding
END GetEncoding;

PROCEDURE (this: TextDecl) SetEncoding*(VAR encoding: ARRAY OF CHAR), NEW;
BEGIN
	this.encoding := DStrings.NewString(encoding)
END SetEncoding;

PROCEDURE (this: TextDecl) Write*(w: Streams.Writer; context: ANYPTR; level: LONGINT), EXTENSIBLE;
BEGIN
	w.String('<?xml version="'); w.String(this.version^);
	IF this.encoding # NIL THEN w.String('" encoding="'); w.String(this.encoding^) END;
	w.String('"?>'); NewLine(w, level)
END Write;


(* ------ XMLDecl ------ *)

PROCEDURE (this: XMLDecl) Init*;
BEGIN
	this.Init^;
	this.standalone := FALSE;
END Init;

PROCEDURE (this: XMLDecl) IsStandalone*(): BOOLEAN, NEW;
BEGIN
	RETURN this.standalone
END IsStandalone;

PROCEDURE (this: XMLDecl) SetStandalone*(standalone: BOOLEAN), NEW;
BEGIN
	this.standalone := standalone
END SetStandalone;

PROCEDURE (this: XMLDecl) Write*(w: Streams.Writer; context: ANYPTR; level: LONGINT);
BEGIN
	w.String('<?xml version="'); w.String(this.version^);
	IF this.encoding # NIL THEN w.String('" encoding="'); w.String(this.encoding^) END;
	w.String('" standalone="');
	IF this.standalone THEN w.String("yes") ELSE w.String("no") END;
	w.String('"?>'); NewLine(w, level)
END Write;


(* ------ DocTypeDecl ------ *)

PROCEDURE (this: DocTypeDecl) Init*;
BEGIN
	this.Init^;
	this.elementDecls := Objects.NewArrayDict();
	this.notationDecls := Objects.NewArrayDict();
	this.generalEntities := Objects.NewArrayDict();
	this.parameterEntities := Objects.NewArrayDict();
	this.allMarkupDecls := Objects.NewArrayCollection();
	this.externalSubset := NIL;
END Init;

PROCEDURE (this: DocTypeDecl) AddMarkupDecl*(c: Content), NEW;
BEGIN
	IF c IS ElementDecl THEN
		this.elementDecls.Add(c(ElementDecl).name^, c); this.allMarkupDecls.Add(c)
	ELSIF (c IS EntityDecl) & (c(EntityDecl).type = GeneralEntity) THEN
		this.generalEntities.Add(c(EntityDecl).name^, c); this.allMarkupDecls.Add(c)
	ELSIF (c IS EntityDecl) & (c(EntityDecl).type = ParameterEntity) THEN
		this.parameterEntities.Add(c(EntityDecl).name^, c); this.allMarkupDecls.Add(c)
	ELSIF c IS NotationDecl THEN
		this.notationDecls.Add(c(NotationDecl).name^, c); this.allMarkupDecls.Add(c)
	ELSIF (c IS ProcessingInstruction) OR (c IS Comment) THEN
		this.allMarkupDecls.Add(c)
	END
END AddMarkupDecl;

PROCEDURE (this: DocTypeDecl) GetElementDecl*(VAR name: ARRAY OF CHAR): ElementDecl, NEW;
	VAR p: ANYPTR;
BEGIN
	p := this.elementDecls.Get(name);
	IF p # NIL THEN RETURN p(ElementDecl)
	ELSE RETURN NIL
	END
END GetElementDecl;

PROCEDURE (this: DocTypeDecl) GetNotationDecl*(VAR name: ARRAY OF CHAR): NotationDecl, NEW;
	VAR p: ANYPTR;
BEGIN
	p := this.elementDecls.Get(name);
	IF p # NIL THEN RETURN p(NotationDecl)
	ELSE RETURN NIL
	END
END GetNotationDecl;

PROCEDURE (this: DocTypeDecl) GetEntityDecl*(VAR name: ARRAY OF CHAR; type: INTEGER): EntityDecl, NEW;
	VAR p: ANYPTR;
BEGIN
	p := NIL;
	IF type = GeneralEntity THEN p := this.generalEntities.Get(name)
	ELSIF type = ParameterEntity THEN p := this.parameterEntities.Get(name)
	END;
	IF p # NIL THEN RETURN p(EntityDecl)
	ELSE RETURN NIL
	END
END GetEntityDecl;

PROCEDURE (this: DocTypeDecl) GetExternalSubset*(): EntityDecl, NEW;
BEGIN
	RETURN this.externalSubset
END GetExternalSubset;

PROCEDURE (this: DocTypeDecl) SetExternalSubset*(externalSubset: EntityDecl), NEW;
BEGIN
	this.externalSubset := externalSubset
END SetExternalSubset;

PROCEDURE (this: DocTypeDecl) Write*(w: Streams.Writer; context: ANYPTR;  level: LONGINT);
	VAR e: Objects.Enumerator; p: ANYPTR; s: String;
BEGIN
	w.String("<!DOCTYPE "); w.String(this.name^);
	IF this.externalSubset # NIL THEN
		s := this.externalSubset.GetPublicId();
		IF s # NIL THEN
			w.String(' PUBLIC "'); w.String(s^); w.String('" "');
		ELSE
			w.String(' SYSTEM "')
		END;
		s := this.externalSubset.GetSystemId();
		w.String(s^); w.Char('"')
	END;
	e := this.allMarkupDecls.GetEnumerator();
	IF e.HasMoreElements() THEN
		w.String(" ["); NewLine(w, level + 1);
		WHILE e.HasMoreElements() DO
			p := e.GetNext(); p(Content).Write(w, context, level + 1)
		END;
		w.String("]")
	END;
	w.Char('>'); NewLine(w, level)
END Write;


(* ------ NotationDecl ------ *)

PROCEDURE (this: NotationDecl) Init*, EXTENSIBLE;
BEGIN
	this.Init^;
	this.systemId := NIL; this.publicId := NIL;
END Init;

PROCEDURE (this: NotationDecl) GetSystemId*(): String, NEW;
BEGIN
	RETURN this.systemId
END GetSystemId;

PROCEDURE (this: NotationDecl) SetSystemId*(VAR systemId: ARRAY OF CHAR), NEW;
BEGIN
	this.systemId := DStrings.NewString(systemId)
END SetSystemId;

PROCEDURE (this: NotationDecl) GetPublicId*(): String, NEW;
BEGIN
	RETURN this.publicId
END GetPublicId;

PROCEDURE (this: NotationDecl) SetPublicId*(VAR publicId: ARRAY OF CHAR), NEW;
BEGIN
	this.publicId := DStrings.NewString(publicId)
END SetPublicId;

PROCEDURE (this: NotationDecl) Write*(w: Streams.Writer; context: ANYPTR; level: LONGINT), EXTENSIBLE;
BEGIN
	w.String("<!NOTATION "); w.String(this.name^);
	IF this.publicId # NIL THEN
		w.String(' PUBLIC "'); w.String(this.publicId^); w.String('" "');
		IF this.systemId # NIL THEN w.String(this.systemId^); w.Char('"') END
	ELSE
		w.String(' SYSTEM "'); w.String(this.systemId^); w.Char('"')
	END;
	w.Char('>'); NewLine(w, level)
END Write;


(* ------ EntityDecl ------ *)

PROCEDURE (this: EntityDecl) Init*;
BEGIN
	this.Init^;
	this.value := NIL; this.notationName := NIL;
	this.type := GeneralEntity;
END Init;

PROCEDURE (this: EntityDecl) GetType*(): INTEGER, NEW;
BEGIN
	RETURN this.type
END GetType;

PROCEDURE (this: EntityDecl) SetType*(type: INTEGER), NEW;
BEGIN
	this.type := type
END SetType;

PROCEDURE (this: EntityDecl) GetValue*(): String, NEW;
BEGIN
	RETURN this.value
END GetValue;

PROCEDURE (this: EntityDecl) SetValue*(VAR value: ARRAY OF CHAR), NEW;
BEGIN
	this.value := DStrings.NewString(value)
END SetValue;

PROCEDURE (this: EntityDecl) GetNotationName*(): String, NEW;
BEGIN
	RETURN this.notationName
END GetNotationName;

PROCEDURE (this: EntityDecl) SetNotationName*(VAR notationName: ARRAY OF CHAR), NEW;
BEGIN
	this.notationName := DStrings.NewString(notationName)
END SetNotationName;

PROCEDURE (this: EntityDecl) Write*(w: Streams.Writer; context: ANYPTR; level: LONGINT);
BEGIN
	w.String("<!ENTITY ");
	IF this.type = ParameterEntity THEN w.String("% ") END;
	w.String(this.name^);
	IF this.value # NIL THEN
		w.String(' "'); w.String(this.value^); w.Char('"')
	ELSE
		IF this.publicId # NIL THEN
			w.String(' PUBLIC "'); w.String(this.publicId^); w.String('" "');
			IF this.systemId # NIL THEN w.String(this.systemId^); w.Char('"') END
		ELSE
			w.String(' SYSTEM "'); w.String(this.systemId^); w.Char('"')
		END;
		IF (this.type = GeneralEntity) & (this.notationName # NIL) THEN
			w.String(' NDATA '); w.String(this.notationName^)
		END
	END;
	w.Char('>'); NewLine(w, level)
END Write;


(* ------ ElementDecl ------ *)

PROCEDURE (this: ElementDecl) Init*;
BEGIN
	this.Init^;
	this.contentType := Any;
	this.content := NIL;
	this.attributeDecls := Objects.NewArrayDict()
END Init;

PROCEDURE (this: ElementDecl) GetContentType*(): INTEGER, NEW;
BEGIN
	RETURN this.contentType
END GetContentType;

PROCEDURE (this: ElementDecl) SetContentType*(contentType: INTEGER), NEW;
BEGIN
	this.contentType := contentType
END SetContentType;

PROCEDURE (this: ElementDecl) GetContent*(): CollectionCP, NEW;
BEGIN
	RETURN this.content
END GetContent;

PROCEDURE (this: ElementDecl) SetContent*(lcp: CollectionCP), NEW;
BEGIN
	this.content := lcp
END SetContent;

PROCEDURE (this: ElementDecl) GetAttributeDecl*(VAR name: ARRAY OF CHAR): AttributeDecl, NEW;
	VAR nc: ANYPTR;
BEGIN
	nc := this.attributeDecls.Get(name);
	IF nc # NIL THEN RETURN nc (AttributeDecl) ELSE RETURN NIL END
END GetAttributeDecl;

PROCEDURE (this: ElementDecl) GetAttributeDecls*(): Objects.Enumerator, NEW;
BEGIN
	RETURN this.attributeDecls.GetEnumerator()
END GetAttributeDecls;

PROCEDURE (this: ElementDecl) AddAttributeDecl*(attributeDecl: AttributeDecl), NEW;
BEGIN
	this.attributeDecls.Add(attributeDecl.name^, attributeDecl)
END AddAttributeDecl;

PROCEDURE (this: ElementDecl) Write*(w: Streams.Writer; context: ANYPTR; level: LONGINT);
	VAR e: Objects.Enumerator; p: ANYPTR;
BEGIN
	w.String("<!ELEMENT "); w.String(this.name^); w.Char(Space);
	IF this.contentType = Empty THEN
		w.String("EMPTY")
	ELSIF this.contentType = Any THEN
		w.String("ANYPTR")
	ELSIF this.content # NIL THEN
		this.content.Write(w, context, level + 1)
	END;
	w.Char('>'); NewLine(w, level);
	e := this.GetAttributeDecls();
	IF e.HasMoreElements() THEN
		w.String("<!ATTLIST "); w.String(this.name^); NewLine(w, level+1);
		WHILE e.HasMoreElements() DO
			p := e.GetNext(); p(Content).Write(w, context, level + 1)
		END;
		w.Char('>'); NewLine(w, level)
	END
END Write;


(* ------ ContentParticle ------ *)

PROCEDURE (this: ContentParticle) Init*, EXTENSIBLE;
BEGIN
	this.Init^;
	this.occurence := ZeroOrOnce;
END Init;

PROCEDURE (this: ContentParticle) GetOccurence*(): INTEGER, NEW;
BEGIN
	RETURN this.occurence
END GetOccurence;

PROCEDURE (this: ContentParticle) SetOccurence*(occ: INTEGER), NEW;
BEGIN
	this.occurence := occ
END SetOccurence;

PROCEDURE (this: ContentParticle) GetOccurenceChar(): CHAR, NEW;
BEGIN
	CASE this.occurence OF
	| ZeroOrOnce: RETURN '?'
	| ZeroOrMore: RETURN '*'
	| Once: RETURN 0X
	| OnceOrMore: RETURN '+'
	END
END GetOccurenceChar;


(* ------ NameContentParticle ------ *)

PROCEDURE (this: NameContentParticle) Init*;
BEGIN
	this.Init^;
	this.name := NIL;
END Init;

PROCEDURE (this: NameContentParticle) GetName*(): String, NEW;
BEGIN
	RETURN this.name
END GetName;

PROCEDURE (this: NameContentParticle) SetName*(VAR name: ARRAY OF CHAR), NEW;
BEGIN
	this.name := DStrings.NewString(name)
END SetName;

PROCEDURE (this: NameContentParticle) SetNameAsString*(name: String), NEW;
BEGIN
	this.name := name;
END SetNameAsString;

PROCEDURE (this: NameContentParticle) Write*(w: Streams.Writer; context: ANYPTR; level: LONGINT);
	VAR ch: CHAR;
BEGIN
	w.String(this.name^);
	ch := this.GetOccurenceChar(); IF ch # 0X THEN w.Char(ch) END
END Write;


(* ------ CollectionCP ------ *)

PROCEDURE (this: CollectionCP) Init*;
BEGIN
	this.Init^;
	this.children := Objects.NewArrayCollection();
	this.type := 0;
END Init;

PROCEDURE (this: CollectionCP) GetType*(): INTEGER, NEW;
BEGIN
	RETURN this.type
END GetType;

PROCEDURE (this: CollectionCP) SetType*(type: INTEGER), NEW;
BEGIN
	this.type := type
END SetType;

PROCEDURE (this: CollectionCP) GetChildren*(): Objects.Enumerator, NEW;
BEGIN
	RETURN this.children.GetEnumerator()
END GetChildren;

PROCEDURE (this: CollectionCP) AddChild*(cp: ContentParticle), NEW;
BEGIN
	this.children.Add(cp)
END AddChild;

PROCEDURE (this: CollectionCP) Write*(w: Streams.Writer; context: ANYPTR; level: LONGINT);
	VAR e: Objects.Enumerator; ch: CHAR; p: ANYPTR;
BEGIN
	e := this.GetChildren();
	p := e.GetNext();
	w.Char('(');
	p(Content).Write(w, context, level + 1);
	WHILE e.HasMoreElements() DO
		p := e.GetNext();
		IF this.type = Choice THEN w.String(" | ")
		ELSIF this.type = Sequence THEN w.String(", ")
		END;
		p(Content).Write(w, context, level + 1)
	END;
	w.Char(')');
	ch := this.GetOccurenceChar(); IF ch # 0X THEN w.Char(ch) END
END Write;


(* ------ AttributeDecl ------ *)

PROCEDURE (this: AttributeDecl) Init*;
BEGIN
	this.Init^;
	this.defaultValue := NIL;
	this.type := CData;
	this.allowedValues := Objects.NewArrayDict();
	this.required := FALSE;
END Init;

PROCEDURE (this: AttributeDecl) GetDefaultValue*(): String, NEW;
BEGIN
	RETURN this.defaultValue
END GetDefaultValue;

PROCEDURE (this: AttributeDecl) SetDefaultValue*(VAR defaultValue: ARRAY OF CHAR), NEW;
BEGIN
	this.defaultValue := DStrings.NewString(defaultValue)
END SetDefaultValue;

PROCEDURE (this: AttributeDecl) GetType*(): INTEGER, NEW;
BEGIN
	RETURN this.type
END GetType;

PROCEDURE (this: AttributeDecl) SetType*(type: INTEGER), NEW;
BEGIN
	this.type := type
END SetType;

(** Collection of NameContents *)
PROCEDURE (this: AttributeDecl) GetAllowedValues*(): Objects.Enumerator, NEW;
BEGIN
	RETURN this.allowedValues.GetEnumerator()
END GetAllowedValues;

PROCEDURE (this: AttributeDecl) AddAllowedValue*(VAR value: ARRAY OF CHAR), NEW;
	VAR nameContent: NameContent;
BEGIN
	NEW(nameContent); nameContent.Init(); nameContent.SetName(value);
	this.allowedValues.Add(value, nameContent)
END AddAllowedValue;

PROCEDURE (this: AttributeDecl) IsRequired*(): BOOLEAN, NEW;
BEGIN
	RETURN this.required
END IsRequired;

PROCEDURE (this: AttributeDecl) SetRequired*(required: BOOLEAN), NEW;
BEGIN
	this.required := required
END SetRequired;

PROCEDURE (this: AttributeDecl) Write*(w: Streams.Writer; context: ANYPTR; level: LONGINT);
	VAR e: Objects.Enumerator; p: ANYPTR;
BEGIN
	w.String(this.name^); w.Char(Space);
	CASE this.type OF
	| CData: w.String("CDATA")
	| Id: w.String("ID")
	| IdRef: w.String("IDREF")
	| IdRefs: w.String("IDREFS")
	| Entity: w.String("ENTITY")
	| Entities: w.String("ENTITIES")
	| NmToken: w.String("NMTOKEN")
	| NmTokens: w.String("NMTOKENS")
	| Notation: w.String("NOTATION")
	| Enumeration:
	END;
	IF this.type # Enumeration THEN w.Char(Space) END;
	IF (this.type = Notation) OR (this.type = Enumeration) THEN
		w.Char('('); e := this.GetAllowedValues();
		p := e.GetNext(); p(Content).Write(w, context, level + 1);
		WHILE e.HasMoreElements() DO
			w.Char('|'); p := e.GetNext(); p(Content).Write(w, context, level + 1)
		END;
		w.String(") ")
	END;
	IF this.required THEN
		IF this.defaultValue = NIL THEN w.String('#REQUIRED')
		ELSE w.String('#FIXED "'); w.String(this.defaultValue^); w.String('"')
		END
	ELSE
		IF this.defaultValue = NIL THEN w.String('#IMPLIED')
		ELSE w.String('"'); w.String(this.defaultValue^); w.String('"')
		END
	END;
	NewLine(w, level)
END Write;


(* ------ CharReference ------ *)

PROCEDURE (this: CharReference) Init*;
BEGIN
	this.Init^;
	this.code := 0;
END Init;

PROCEDURE (this: CharReference) SetCode*(code: LONGINT), NEW;
BEGIN
	this.code := code
END SetCode;

PROCEDURE (this: CharReference) GetCode*(): LONGINT, NEW;
BEGIN
	RETURN this.code
END GetCode;

PROCEDURE (this: CharReference) Write*(w: Streams.Writer; context: ANYPTR; level: LONGINT);
	VAR codeArray: ARRAY 16 OF CHAR; codeStr: String;
BEGIN
	Strings.IntToString(this.code, codeArray);
	codeStr := DStrings.NewString(codeArray);
	w.String('&#'); w.String(codeStr^); w.Char(';')
END Write;


(* ------ EntityRef ------ *)

PROCEDURE (this: EntityRef) Init*, EXTENSIBLE;
BEGIN
	this.Init^;
	this.decl := NIL;
END Init;

PROCEDURE (this: EntityRef) GetEntityDecl*(): EntityDecl, NEW;
BEGIN
	RETURN this.decl
END GetEntityDecl;

PROCEDURE (this: EntityRef) SetDocument(document: Document), NEW;
	VAR dtd: DocTypeDecl;
BEGIN
	dtd := document.GetDocTypeDecl();
	IF dtd # NIL THEN
		this.decl := dtd.GetEntityDecl(this.name^, GeneralEntity)
	END
END SetDocument;

PROCEDURE (this: EntityRef) Write*(w: Streams.Writer; context: ANYPTR; level: LONGINT);
BEGIN
	w.Char('&'); w.String(this.name^); w.Char(';')
END Write;


(* ------ InternalEntityRef ------ *)

PROCEDURE (this: InternalEntityRef) GetValue*(): String, NEW;
BEGIN
	IF this.decl # NIL THEN RETURN this.decl.value
	ELSE RETURN NIL
	END
END GetValue;


(* ------ ExternalEntityRef ------ *)

PROCEDURE (this: ExternalEntityRef) Init*;
BEGIN
	this.Init^;
	this.coll := NIL;
	this.textDecl := NIL;
END Init;

PROCEDURE (this: ExternalEntityRef) GetTextDecl*(): TextDecl, NEW;
BEGIN
	RETURN this.textDecl
END GetTextDecl;

PROCEDURE (this: ExternalEntityRef) IsParsed*(): BOOLEAN, NEW;
BEGIN
	RETURN this.coll # NIL
END IsParsed;

PROCEDURE (this: ExternalEntityRef) GetContents*(): Objects.Enumerator, NEW;
BEGIN
	IF this.IsParsed() THEN RETURN this.coll.GetEnumerator()
	ELSE RETURN NIL
	END
END GetContents;

PROCEDURE (this: ExternalEntityRef) AddContent*(c: Content), NEW;
BEGIN
	IF this.coll = NIL THEN this.coll := Objects.NewArrayCollection() END;
	IF c IS TextDecl THEN
		this.textDecl := c(TextDecl)
	END;
	this.coll.Add(c)
END AddContent;

PROCEDURE (this: ExternalEntityRef) GetIdElement(VAR name, id: ARRAY OF CHAR): Element, NEW;
	VAR contents: Objects.Enumerator; p: ANYPTR; retElement: Element;
BEGIN
	retElement := NIL;
	IF this.IsParsed() THEN
		contents := this.GetContents();
		WHILE contents.HasMoreElements() & (retElement = NIL) DO
			p := contents.GetNext();
			IF p IS Element THEN
				retElement := p(Element).GetIdElement(name, id)
			ELSIF p IS ExternalEntityRef THEN
				retElement := p(ExternalEntityRef).GetIdElement(name, id)
			END
		END
	END;
	RETURN retElement
END GetIdElement;


(* ------ Chars ------ *)

PROCEDURE (this: Chars) GetStr*(): String, NEW, ABSTRACT;

PROCEDURE (this: Chars) GetLength*(): LONGINT, NEW, ABSTRACT;

PROCEDURE (this: Chars) Write*(w: Streams.Writer; context: ANYPTR; level: LONGINT), EXTENSIBLE;
	VAR s: String;
BEGIN
	s := this.GetStr(); w.String(s^)
END Write;


(* ------ ArrayChars ------ *)

PROCEDURE (this: ArrayChars) Init*;
BEGIN
	this.str := NIL;
	this.len := 0;
END Init;

PROCEDURE (this: ArrayChars) GetStr*(): String;
BEGIN
	RETURN this.str
END GetStr;

PROCEDURE (this: ArrayChars) GetLength*(): LONGINT;
BEGIN
	RETURN this.len
END GetLength;

PROCEDURE (this: ArrayChars) SetStr*(VAR str: ARRAY OF CHAR), NEW;
BEGIN
	this.str := DStrings.NewString(str);
	this.len := LEN(str$)
END SetStr;

PROCEDURE (this: ArrayChars) SetStrAsString*(str: String), NEW;
BEGIN
	this.str := str;
	this.len := LEN(str^$)
END SetStrAsString;


(* ------ CDataSect ------ *)

PROCEDURE (this: CDataSect) Write*(w: Streams.Writer; context: ANYPTR; level: LONGINT);
	VAR s: String; i, j: LONGINT; buf: ARRAY 4 OF CHAR;
BEGIN
	w.String("<![CDATA[");
	s := this.GetStr(); buf := "   ";
	IF (LEN(s^) < 3) THEN
		w.String(s^);
	ELSE
		buf[1] := s^[0];
		buf[2] := s^[1]; i := 2;
		WHILE (i < LEN(s^)) DO
			buf[0] := buf[1];
			buf[1] := buf[2];
			buf[2] := s^[i];
			INC(i);
			IF (buf = "]]>") THEN
				w.String("]]]]><![CDATA[>");
				IF ((i+2) < LEN(s^)) THEN
					buf[1] := s^[i]; INC(i);
					buf[2] := s^[i]; INC(i);
				ELSE
					j := 0;
					WHILE (i < LEN(s^)) DO
						buf[j] := s^[i]; INC(i); INC(j);
					END;
					buf[j] := 0X;
				END;
			ELSIF (i < LEN(s^)) THEN w.Char(buf[0]);
			END;
		END;
		w.String(buf);
	END;
	w.String("]]>"); NewLine(w, level)
END Write;


(* ------ ProcessingInstruction ------ *)

PROCEDURE (this: ProcessingInstruction) Init*;
BEGIN
	this.Init^;
	this.target := NIL; this.instruction := NIL;
END Init;

PROCEDURE (this: ProcessingInstruction) GetTarget*(): String, NEW;
BEGIN
	RETURN this.target
END GetTarget;

PROCEDURE (this: ProcessingInstruction) SetTarget*(VAR target: ARRAY OF CHAR), NEW;
BEGIN
	this.target := DStrings.NewString(target)
END SetTarget;

PROCEDURE (this: ProcessingInstruction) GetInstruction*(): String, NEW;
BEGIN
	RETURN this.instruction
END GetInstruction;

PROCEDURE (this: ProcessingInstruction) SetInstruction*(VAR instruction: ARRAY OF CHAR), NEW;
BEGIN
	this.instruction := DStrings.NewString(instruction)
END SetInstruction;

PROCEDURE (this: ProcessingInstruction) Write*(w: Streams.Writer; context: ANYPTR; level: LONGINT);
BEGIN
	w.String("<?"); w.String(this.target^); w.Char(Space);
	w.String(this.instruction^); w.String("?>"); NewLine(w, level)
END Write;


(* ------ Attribute ------ *)

PROCEDURE (this: Attribute) Init*;
BEGIN
	this.Init^;
	this.value := NIL; this.elementName := NIL;
	this.document := NIL;
	this.decl := NIL;
END Init;

PROCEDURE (this: Attribute) IsAllowedValue*(VAR value: ARRAY OF CHAR): BOOLEAN, NEW;
BEGIN
	IF this.decl = NIL THEN
		RETURN TRUE
	ELSE
		CASE this.decl.GetType() OF
		| CData: RETURN TRUE
		| Id: RETURN this.document.root.GetIdElement(this.elementName^, value) = NIL
		| IdRef: RETURN TRUE
		| IdRefs: RETURN TRUE
		| Entity: RETURN TRUE
		| Entities: RETURN TRUE
		| NmToken: RETURN TRUE
		| NmTokens: RETURN TRUE
		| Notation:
			RETURN this.decl.allowedValues.Get(value) # NIL
		| Enumeration:
			RETURN this.decl.allowedValues.Get(value) # NIL
		ELSE
		END
	END
END IsAllowedValue;

PROCEDURE (this: Attribute) SetDocument(document: Document; elementName: String), NEW;
	VAR dtd: DocTypeDecl; elementDecl: ElementDecl;
BEGIN
	this.document := document;
	this.elementName := elementName;
	dtd := document.GetDocTypeDecl();
	IF dtd # NIL THEN
		elementDecl := dtd.GetElementDecl(elementName^);
		IF elementDecl # NIL THEN
			this.decl := elementDecl.GetAttributeDecl(this.name^);
			IF (this.decl # NIL) & ((this.value = NIL) OR ~this.IsAllowedValue(this.value^)) THEN
				this.value := this.decl.defaultValue
			END
		END
	END
END SetDocument;

PROCEDURE (this: Attribute) GetValue*(): String, NEW;
BEGIN
	RETURN this.value
END GetValue;

PROCEDURE (this: Attribute) SetValue*(VAR value: ARRAY OF CHAR), NEW;
BEGIN
	IF this.IsAllowedValue(value) THEN
		this.value := DStrings.NewString(value)
	END
END SetValue;

PROCEDURE (this: Attribute) SetValueAsString*(value: String), NEW;
BEGIN
	ASSERT(value # NIL);
	IF this.IsAllowedValue(value^) THEN
		this.value := value;
	END;
END SetValueAsString;

PROCEDURE (this: Attribute) Write*(w: Streams.Writer; context: ANYPTR; level: LONGINT);
BEGIN
	IF this.value = NIL THEN StdLog.String("NIL attribute "); StdLog.Ln; RETURN END;
	w.Char(Space); w.String(this.name^); w.String('="'); EscapeString(w, this.value^); w.Char('"')
END Write;


(* ------ Element ------ *)

PROCEDURE (this: Element) Init*, EXTENSIBLE;
BEGIN
	this.Init^;
	this.root := NIL; this.parent := NIL;
	this.name := StrNoName;
	this.document := NIL; this.attributes := NIL;
	this.idAttribute := NIL;
END Init;

PROCEDURE (this: Element) AddContent*(content: Content), EXTENSIBLE;
BEGIN
	ASSERT(content # NIL);
	this.AddContent^(content);
	IF (content IS Element) THEN
		WITH content: Element DO
			IF this.root # NIL THEN content.root := this.root ELSE content.root := this; END;
			content.parent := this;
		END;
	END;
END AddContent;

PROCEDURE (this: Element) RemoveContent*(content: Content), EXTENSIBLE;
BEGIN
	(*ASSERT(content # NIL);*)
	IF content=NIL THEN RETURN END; (*PH 12/13: removing nothing is logically correct *)
	this.RemoveContent^(content);
	IF (content IS Element) THEN
		IF (content(Element).parent = this) THEN
			content(Element).parent := NIL;
			content(Element).root := NIL;
		END;
	END;
END RemoveContent;

PROCEDURE (this: Element) SetDocument*(document: Document), NEW, EXTENSIBLE;
	VAR
		dtd: DocTypeDecl; elementDecl: ElementDecl;
		enum: Objects.Enumerator; c: Content; p: ANYPTR; attribute: Attribute;
BEGIN
	ASSERT(document # NIL);
	this.document := document;
	this.root := document.GetRoot();
	dtd := document.GetDocTypeDecl();
	IF dtd # NIL THEN
		elementDecl := dtd.GetElementDecl(this.name^);
		IF elementDecl # NIL THEN
			enum := elementDecl.GetAttributeDecls();
			WHILE enum.HasMoreElements() DO
				p := enum.GetNext();
				WITH p: AttributeDecl DO
					attribute := this.GetAttribute(p.name^);
					IF attribute # NIL THEN
						attribute.SetDocument(document, this.name);
					ELSE
						NEW(attribute); attribute.Init;
						attribute.name := p.name;
						attribute.value := p.defaultValue;
						attribute.SetDocument(document, this.name);
						this.AddAttribute(attribute);
					END;
					IF p.type = Id THEN this.idAttribute := attribute END
				END
			END
		END
	END;
	c := this.GetFirst();
	WHILE (c # NIL) DO
		IF (c IS Element) THEN c(Element).SetDocument(document);
		ELSIF (c IS EntityRef) THEN c(EntityRef).SetDocument(document);
		END;
		c := this.GetNext(c);
	END;
END SetDocument;

PROCEDURE (this: Element) SetName*(VAR name: ARRAY OF CHAR), NEW, EXTENSIBLE;
BEGIN
	this.name := DStrings.NewString(name)
END SetName;

PROCEDURE (this: Element) SetNameAsString*(name: String), NEW, EXTENSIBLE;
BEGIN
	ASSERT(name # NIL);
	this.name := name
END SetNameAsString;

PROCEDURE (this: Element) GetName*(): String, NEW, EXTENSIBLE;
BEGIN
	ASSERT(this.name # NIL);
	RETURN this.name
END GetName;

PROCEDURE (this: Element) GetId*(): String, NEW, EXTENSIBLE;
BEGIN
	IF this.idAttribute # NIL THEN RETURN this.idAttribute.value
	ELSE RETURN NIL
	END
END GetId;

PROCEDURE (this: Element) GetIdElement*(VAR name, id: ARRAY OF CHAR): Element, NEW, EXTENSIBLE;
	VAR contents: Objects.Enumerator; content: ANYPTR; idString: String; retElement: Element;
BEGIN
	retElement := NIL;
	IF this.name^ = name THEN
		idString := this.GetId();
		IF (idString # NIL) & (idString^ = id) THEN retElement := this END
	END;
	IF retElement = NIL THEN
		contents := this.GetContents();
		WHILE contents.HasMoreElements() & (retElement = NIL) DO
			content := contents.GetNext();
			IF content IS Element THEN
				retElement := content(Element).GetIdElement(name, id)
			ELSIF content IS ExternalEntityRef THEN
				retElement := content(ExternalEntityRef).GetIdElement(name, id)
			END
		END
	END;
	RETURN retElement
END GetIdElement;

PROCEDURE (this: Element) RemoveAttributeInternal(VAR name: ARRAY OF CHAR), NEW;
	VAR a: Attribute;
BEGIN (* caller holds object lock *)
	IF (this.attributes # NIL) THEN
		IF (this.attributes.name^ = name) THEN
			IF (this.attributes.next = NIL) THEN this.attributes := NIL;
			ELSE this.attributes := this.attributes.next (Attribute); 
			END;
		ELSE
			a := this.attributes;
			WHILE (a.next # NIL) & (a.next(Attribute).name^ # name) DO a := a.next (Attribute); END;
			IF (a.next # NIL) THEN
				a.next := a.next.next;
			END;
		END;
	END;
END RemoveAttributeInternal;

PROCEDURE (this: Element) AddAttribute*(attribute: Attribute), NEW, EXTENSIBLE;
	VAR a: Attribute;
BEGIN
	ASSERT((attribute # NIL) & (attribute.next = NIL) & (attribute.name # NIL) & (attribute.name^ # ""));
	this.RemoveAttributeInternal(attribute.name^);
	IF (this.attributes = NIL) THEN
		this.attributes := attribute;
	ELSE
		a := this.attributes;
		WHILE (a.next # NIL) DO a := a.next (Attribute); END;
		a.next := attribute;
	END;
END AddAttribute;

PROCEDURE (this: Element) RemoveAttribute*(VAR name: ARRAY OF CHAR), NEW, EXTENSIBLE;
BEGIN
	this.RemoveAttributeInternal(name);
END RemoveAttribute;

PROCEDURE (this: Element) SetAttributeValue*(VAR name, value: ARRAY OF CHAR), NEW, EXTENSIBLE;
	VAR attribute: Attribute;
BEGIN
	NEW(attribute); attribute.Init; attribute.SetName(name); attribute.SetValue(value); this.AddAttribute(attribute)
END SetAttributeValue;

PROCEDURE (this: Element) GetAttribute*(VAR name: ARRAY OF CHAR): Attribute, NEW, EXTENSIBLE;
	VAR a: Attribute;
BEGIN
	a := this.attributes;
	WHILE (a # NIL) & (a.name^ # name) DO
		IF (a.next = NIL) THEN a := NIL; ELSE a := a.next (Attribute); END;
	END;
	RETURN a;
END GetAttribute;

PROCEDURE (this: Element) GetAttributeValue*(VAR name: ARRAY OF CHAR): String, NEW, EXTENSIBLE;
	VAR a: Attribute;
BEGIN
	a := this.GetAttribute(name);
	IF (a # NIL) THEN
		RETURN a.GetValue();
	ELSE
		RETURN NIL;
	END;
END GetAttributeValue;

PROCEDURE (this: Element) GetAttributes*(): Objects.Enumerator, NEW, EXTENSIBLE;
	VAR a: Attribute; array: Objects.PTRArray; enumerator: Objects.ArrayEnumerator; i, nofAttributes: LONGINT;
BEGIN
	nofAttributes := 0;
	a := this.attributes;
	WHILE (a # NIL) DO
		INC(nofAttributes);
		IF (a.next # NIL) THEN a := a.next (Attribute); ELSE a := NIL; END;
	END;
	NEW(array, MAX(nofAttributes, 1));
	a := this.attributes; i := 0;
	WHILE (a # NIL) DO
		array[i] := a; INC(i);
		IF (a.next # NIL) THEN a := a.next (Attribute); ELSE a := NIL; END;
	END;
	enumerator := Objects.NewArrayEnumerator(array);
	RETURN enumerator;
END GetAttributes;

PROCEDURE (this: Element) GetFirstAttribute*(): Attribute, NEW, EXTENSIBLE;
	VAR a: Attribute;
BEGIN
	RETURN this.attributes;
END GetFirstAttribute;

PROCEDURE (this: Element) GetNextAttribute*(a: Attribute): Attribute, NEW, EXTENSIBLE;
BEGIN
	IF a.next # NIL THEN RETURN a.next(Attribute) ELSE RETURN NIL END
END GetNextAttribute;

PROCEDURE (this: Element) HasAttribute*(VAR name: ARRAY OF CHAR): BOOLEAN, NEW, EXTENSIBLE;
BEGIN
	RETURN this.GetAttribute(name) # NIL;
END HasAttribute;

PROCEDURE (this: Element) GetRoot*(): Element, NEW, EXTENSIBLE;
BEGIN
	RETURN this.root
END GetRoot;

PROCEDURE (this: Element) GetParent*(): Element, NEW, EXTENSIBLE;
BEGIN
	RETURN this.parent
END GetParent;

PROCEDURE (this: Element) GetFirstChild*(): Element, NEW, EXTENSIBLE;
	VAR c: Content;
BEGIN
	c := this.GetFirst();
	WHILE (c # NIL) & ~(c IS Element) DO
		c := this.GetNext(c);
	END;
	IF (c # NIL) THEN
		RETURN c(Element);
	ELSE
		RETURN NIL;
	END;
END GetFirstChild;

PROCEDURE (this: Element) GetNextSibling*(): Element, NEW, EXTENSIBLE;
	VAR c: Content;
BEGIN
	c := this.next;
	WHILE (c # NIL) & ~(c IS Element) DO c := c.next; END;
	IF (c # NIL) THEN
		RETURN c(Element);
	ELSE
		RETURN NIL;
	END;
END GetNextSibling;

PROCEDURE (this: Element) GetPreviousSibling*(): Element, NEW, EXTENSIBLE;
	VAR c: Content;
BEGIN
	c := this.previous;
	WHILE	(c # NIL) & ~(c IS Element) DO c := c.previous; END;
	IF (c # NIL) THEN
		RETURN c(Element);
	ELSE
		RETURN NIL;
	END;
END GetPreviousSibling;

PROCEDURE (this: Element) Traverse*(traverseProc: TraverseProc; data: ANYPTR), NEW, EXTENSIBLE;
	VAR c: Content;
BEGIN
	ASSERT(traverseProc # NIL);
	traverseProc(this, data);
	c := this.GetFirst();
	WHILE (c # NIL) DO
		IF (c IS Element) THEN c(Element).Traverse(traverseProc, data);
		ELSE traverseProc(c, data);
		END;
		c := this.GetNext(c);
	END;
END Traverse;

PROCEDURE (this: Element) WriteAttributes*(w: Streams.Writer; context: ANYPTR; level: LONGINT), 
																																	NEW, EXTENSIBLE;
	VAR a: Attribute;
BEGIN
	a := this.attributes;
	WHILE (a # NIL) DO
		a.Write(w, context, level + 1);
		IF (a.next # NIL) THEN
			a := a.next (Attribute);
		ELSE
			a := NIL;
		END;
	END;
END WriteAttributes;

PROCEDURE (this: Element) Write*(w: Streams.Writer; context: ANYPTR; level: LONGINT), EXTENSIBLE;
	VAR c: Content;
BEGIN
	w.Char('<'); w.String(this.name^);
	this.WriteAttributes(w, context, level);
	c := this.GetFirst();
	IF (c = NIL) THEN w.String("/>")
	ELSE
		w.Char('>');
		IF ~(c IS ArrayChars)  THEN NewLine(w, level + 1) END;
		c.Write(w, context,  level + 1);
		WHILE (this.GetNext(c) # NIL) DO
			c := this.GetNext(c); NewLine(w, level + 1); c.Write(w, context, level + 1);
		END;
		IF ~(c IS ArrayChars)  THEN NewLine(w, level); END;
		w.String("</"); w.String(this.name^); w.Char('>');
	END;
END Write;


(* ------ ElementEntry ------ *)

PROCEDURE (this: ElementEntry) Init*, NEW;
BEGIN
	this.generator := NIL;
	this.generatorModule := "";  this.generatorProcedure := ""
END Init;


(* ------ ElementRegistry ------ *)

PROCEDURE (this: ElementRegistry) Init*, NEW;
BEGIN
	this.generators := Objects.NewArrayDict();
	this.timestamp := 0;
END Init;

PROCEDURE (this: ElementRegistry) RegisterElement*(VAR name: ARRAY OF CHAR; 
																					generator: GeneratorProcedure), NEW;
	VAR e: ElementEntry; p: ANYPTR;
BEGIN
	ASSERT(generator # NIL, 20);
	p := this.generators.Get(name);
	IF p = NIL THEN
		NEW(e); e.Init; e.name := name$; e.generator := generator; this.generators.Add(name, e)
	ELSE (* redefinition *)
		p(ElementEntry).generator := generator
	END;
	INC(this.timestamp);
END RegisterElement;

PROCEDURE  (this: ElementRegistry) RegisterElementByName*(VAR name: ARRAY OF CHAR;
																		VAR generatorModule, generatorProcedure: Kernel.Name), NEW;
	VAR e: ElementEntry; p: ANYPTR;
BEGIN
	ASSERT((generatorModule # "") & (generatorProcedure # ""), 20);
	p := this.generators.Get(name);
	IF p = NIL THEN
		NEW(e); e.Init;
		e.name := name$;
		e.generatorModule := generatorModule;
		e.generatorProcedure := generatorProcedure;
		this.generators.Add(name, e)
	ELSE (* redefinition *)
		p(ElementEntry).generatorModule := generatorModule;
		p(ElementEntry).generatorProcedure := generatorProcedure;
	END;
	INC(this.timestamp);
END RegisterElementByName;

PROCEDURE  (this: ElementRegistry) UnregisterElement*(VAR name: ARRAY OF CHAR), NEW;
BEGIN
	this.generators.Remove(name);
	INC(this.timestamp);
END UnregisterElement;

PROCEDURE  (this: ElementRegistry) InstantiateElement*(VAR name: ARRAY OF CHAR): Element, NEW;
	VAR element: Element; entry: ElementEntry; p: ANYPTR;
		module: Kernel.Module;
BEGIN
	element := NIL;
	p := this.generators.Get(name);
	IF (p # NIL) THEN entry := p (ElementEntry); END;
	IF (entry # NIL) THEN
		IF entry.generator = NIL THEN
			module := Kernel.ThisMod(entry.generatorModule);
			IF module # NIL THEN
				entry.generator := Kernel.ThisCommand(module, entry.generatorProcedure);
			END;
			IF (entry.generator = NIL) THEN
				StdLog.String("Warning: XML.ElementRegistry.InstantiateElement: Factory procedure ");
				StdLog.String(entry.generatorModule); StdLog.String("."); StdLog.String(entry.generatorProcedure);
				StdLog.String(" not found."); StdLog.Ln;
			END
		END;
		IF entry.generator # NIL THEN
			entry.generator(); element := generatedElement; generatedElement := NIL
		END
	END;
	RETURN element;
END InstantiateElement;

(** fof, late time instantiation to be able to react on generator properties *)
PROCEDURE  (this: ElementRegistry) InstantiateLate*(e: Element): Element, NEW;
BEGIN
	RETURN e (* stub *)
END InstantiateLate;

PROCEDURE  (this: ElementRegistry) GetTimestamp*(): LONGINT, NEW;
BEGIN
	RETURN this.timestamp;
END GetTimestamp;

PROCEDURE  (this: ElementRegistry) GetElements*(): ElementArray, NEW;
	VAR enumerator: Objects.Enumerator; nofElements, i: LONGINT; ptr: ANYPTR; ea: ElementArray;
BEGIN
	enumerator := this.generators.GetEnumerator();
	nofElements := 0;
	WHILE enumerator.HasMoreElements() DO INC(nofElements); ptr := enumerator.GetNext(); END;
	IF (nofElements = 0) THEN
		ea := NIL;
	ELSE
		NEW(ea, nofElements);
		enumerator.Reset;
		i := 0;
		WHILE (i < nofElements) & enumerator.HasMoreElements() DO
			ptr := enumerator.GetNext();
			IF (ptr # NIL) & (ptr IS ElementEntry) THEN
				ea[i] := ptr (ElementEntry);
			ELSE
				ea[i] := NIL;
			END;
			INC(i);
		END;
	END;
	RETURN ea;
END GetElements;

(* TODO JT

(**	Write an 0X-terminated UTF8 string to a stream (excl. 0X). XML special characters are escaped.
	Also works for ASCII strings. *)
PROCEDURE UTF8ToStream*(VAR string: ARRAY OF CHAR; w: Streams.Writer; VAR res: LONGINT);
	VAR codeLength, stringLength, i: LONGINT; ch: CHAR;
BEGIN
	ASSERT(w # NIL, 20);
	res := Ok;
	stringLength := LEN(string);
	i := 0;
	WHILE (res = Ok) & (i < stringLength) & (string[i] # 0X) DO
		ch := string[i];
		codeLength := ORD(UTF8Strings.CodeLength[ORD(ch)]);
		IF (codeLength = 1) THEN
			CASE ch OF
				|'&': w.String("&amp;");
				|'<': w.String("&lt;");
				|'>': w.String("&gt;");
				|'"': w.String("&quot;");
				|"'": w.String("&apos;");
			ELSE
				w.Char(ch);
			END;
		ELSIF (codeLength > 0) & (i + codeLength <= stringLength) THEN
			w.Bytes(string, i, codeLength);
		ELSE
			res := InvalidString;
		END;
		INC(i, codeLength);
	END;
	IF (i >= stringLength) OR (string[i] # 0X) THEN
		res := InvalidString;
	END;
END UTF8ToStream;

(**	Read an UTF8 string from a stream and undo escaping of XML special characters.
	If the string array is to small, the string
	will be truncated and an error will be reported. <string> is always a valid 0X-terminated string.
	Also works for ASCII strings. *)
PROCEDURE UTF8FromStream*(VAR string: ARRAY OF CHAR; r: Streams.Reader; VAR res: LONGINT);
	VAR ch: CHAR;  escapeBuffer: ARRAY 8 OF CHAR; escaping: BOOLEAN;
		escapeIdx, codeLength, stringLength, i, len, actLen: LONGINT;

	PROCEDURE FlushEscapeBuffer;
		VAR j: LONGINT;
	BEGIN
		IF escaping THEN
			j := 0;
			WHILE (i < stringLength - 1) & (escapeBuffer[j] # 0X) DO
				string[i] := escapeBuffer[j];
				INC(i); INC(j);
			END;
			IF (escapeBuffer[j] # 0X) THEN res := BufferError; END;
			escaping := FALSE;
		END;
	END FlushEscapeBuffer;

	PROCEDURE CheckEscapeBuffer;
	BEGIN
		ASSERT(i < stringLength);
		IF (escapeIdx = 4) THEN
			IF (escapeBuffer = "&lt;") THEN string[i] := "<"; INC(i); escaping := FALSE;
			ELSIF (escapeBuffer = "&gt;") THEN string[i] := ">"; INC(i); escaping := FALSE;
			END;
		ELSIF (escapeIdx = 5) & (escapeBuffer = "&amp;") THEN
			string[i] := "&"; INC(i); escaping := FALSE;
		ELSIF (escapeIdx = 6) THEN
			IF (escapeBuffer = "&quot;") THEN string[i] := '"'; INC(i); escaping := FALSE;
			ELSIF (escapeBuffer = "&apos;") THEN string[i] := "'"; INC(i); escaping := FALSE;
			END;
		ELSIF (escapeIdx > 6) THEN
			FlushEscapeBuffer;
		END;
	END CheckEscapeBuffer;

BEGIN
	ASSERT((r # NIL) & (LEN(string) >= 1), 20);
	res := Ok;
	escaping := FALSE;
	stringLength := LEN(string);
	i := 0;
	ch := r.Peek();
	WHILE (res = Ok) & (ch # 0X) & (i < stringLength - 1) DO
		codeLength := ORD(UTF8Strings.CodeLength[ORD(ch)]);
		IF (codeLength = 1) THEN
			ch := r.Get();
			IF (ch = "&") THEN
				FlushEscapeBuffer;
				escaping := TRUE;
				escapeBuffer[0] := ch;
				escapeBuffer[1] := 0X;
				escapeIdx := 1;
			ELSIF escaping THEN
				escapeBuffer[escapeIdx] := ch;
				escapeBuffer[escapeIdx + 1] := 0X;
				INC(escapeIdx);
				CheckEscapeBuffer;
			ELSE
				string[i] := ch;
				INC(i);
			END;
		ELSIF (codeLength > 0) THEN
			FlushEscapeBuffer;
			len := Strings.Min(codeLength, stringLength - 1 - i);
			IF (len > 0) THEN
				r.Bytes(string, i, len, actLen);
				IF (actLen # len) THEN
					res := InvalidString;
				ELSIF (len # codeLength) THEN
					res := BufferError;
				END;
				INC(i, actLen);
			ELSE
				res := BufferError;
			END;
		ELSE
			res := InvalidString;
		END;
		ch := r.Peek();
	END;
	string[i] := 0X;
END UTF8FromStream;
*)

PROCEDURE (this: Comment) Write*(w: Streams.Writer; context: ANYPTR; level: LONGINT);
BEGIN
	NewLine(w, level-1); w.String("<!--"); this.Write^(w, context, level); w.String("-->"); NewLine(w, level)
END Write;


PROCEDURE NewLine(w: Streams.Writer; level: LONGINT);
BEGIN
	w.Ln; WHILE level > 0 DO w.Char(Tab); DEC(level) END
END NewLine;

PROCEDURE EscapeString(w: Streams.Writer; VAR string: ARRAY OF CHAR);
	VAR i: LONGINT; ch: CHAR;
BEGIN
	i := 0; ch := string[0];
	WHILE w.ok & (ch # 0X) DO
		CASE ch OF
		| '&': w.String("&amp;");
		| '<': w.String("&lt;");
		| '>': w.String("&gt;");
		| '"': w.String("&quot;");
		| "'": w.String("&apos;");
		ELSE
			w.Char(ch);
		END;
		INC(i); ch := string[i]
	END
END EscapeString;

BEGIN
	StrNoName := DStrings.NewString("");
END W3cDOM.