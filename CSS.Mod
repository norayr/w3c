MODULE W3cCSS;

(* This module provides an abstract CSS2 syntax tree.

Original author: Stefan Walthert (swalthert).
Ported from A2 Oberon build 7131 to BlackBox Component Pascal, J. Templ, 2017-05-10.
*)

IMPORT
	DStrings := W3cDStrings,
	Objects := W3cObjects;

CONST
	Undefined* = 0;

	(** RuleSet.media *)
	All* = 0; (**  *)
	Aural* = 1; (**  *)
	Braille* = 2; (**  *)
	Embossed* = 3; (**  *)
	Handheld* = 4; (**  *)
	Print* = 5; (**  *)
	Projection* = 6; (**  *)
	Screen* = 7; (**  *)
	TTY* = 8; (**  *)
	TV* = 9; (**  *)
	
	(** SimpleSelector.combinator *)
	Descendant* = 1;	(** ' ' *)
	Child* = 2;	(** '>' *)
	Sibling* = 3;	(** '+' *)
	
	(** Attribute.relation *)
	Equal* = 1;	(** '=' *)
	Includes* = 2;	(** '~=' *)
	Dashmatch* = 3;	(** '|=' *)

	(** Term.operator *)
	Add* = 1;
	Sub* = 2;
	Times* = 3;
	Slash* = 4;
	Seq* = 5; (* concatenation *)

	(** Term.unaryOperator *)
	Minus* = -1;	(** '-' *)
	Plus* = 1;	(** '+' *)

	(** Term.type *)
	IntNumber* = 1;	(** [0-9]+ *)
	RealNumber* = 2;	(** [0-9]*'.'[0-9]+ *)
	Percent* = 3;	(** {real}'%' / 100, {integer}'%' / 100 *)
	IntDimension* = 4;	(** {integer}{unit} *)
	RealDimension* = 5;	(** {real}{unit} *)
	Function* = 6;	(** {ident}'('term')' *)
	StringVal* = 7;	(** '"'chars'"' | "'"chars"'" *)
	StringIdent* = 8;	(** chars *)
	URI* = 9;	(** 'url('{string}')' | 'url('url')' *)
	Color* = 10;	(** '#'RGB | '#'RRGGBB | 'rgb('{number}'% ,' {number}'% ,' {number}'%)'
			| 'rgb('{integer}',' {integer}',' {integer}'%)'	(without transparancy)
			or '#'ARGB | '#'AARRGGBB | 'rgba('{number}'% ,' {number}'% ,' {number}'% ,' {number}'%)'
			| 'rgba('{integer}',' {integer}',' {integer}'%,' {integer}'%)'	(with transparancy) (integer: 0 - 255) *)
	Ident* = 11;	(** Ident type: GetIntVal() *)
	UnicodeRange* = 12;	(**  *)
	Operator* = 13; (** binary operator or Seq *)

	(** Term.unit *)
	(** relative length units *)
	em* = 1;	(** the 'font-size' of the relevant font *)
	ex* = 2;	(** the 'x-height' of the relevant font *)
	ch* = 16;	(** the 'width' of the 0 character of the relevant font *)
	(* JT added units 17 to 21 *)
	rem* = 17;	(** the 'font-size' of the root element font *)
	vw* = 18;	(** 1% of the width of the viewport *)
	vh* = 19;	(** 1% of the height of the viewport *)
	vmin* = 20;	(** 1% of viewport's smaller dimension *)
	vmax* = 21;	(** 1% of viewport's larger dimension *)
	(** absolute length units *)
	px* = 3;	(** pixels -- 1px = 1/96th of 1in *)
	in* = 4;	(** inches -- 1 inch is equal to 2.54 centimeters *)
	cm* = 5;	(** centimeters *)
	mm* = 6;	(** millimeters *)
	pt* = 7;	(** points -- the points used by CSS2 are equal to 1/72th of an inch *)
	pc* = 8;	(** picas -- 1 pica is equal to 12 points *)
	(** angle units *)
	deg* = 9;	(** degrees *)
	grad* = 10;	(** grads *)
	rad* = 11;	(** radians *)
	(** time units *)
	ms* = 12;	(** milliseconds *)
	s* = 13;	(** seconds *)
	(** frequency units *)
	Hz* = 14;	(** Hertz *)
	kHz* = 15;	(** kilo Hertz *)

	(** Page.pseudoPage *)
	Left* = 1;	(** ':left' *)
	Right* = 2;	(** ':right' *)
	First* = 3;	(** ':first' *)


TYPE
	String* = DStrings.String;

	StyleSheet* = POINTER TO EXTENSIBLE RECORD
		charSet: String;
		rulesets, pages, fontFaces: Objects.Collection;
	END;
	
	RuleSet* = POINTER TO EXTENSIBLE RECORD
		selectors, declarations: Objects.Collection;
		hasImportantDeclarations, hasNotImportantDeclarations: BOOLEAN;
		media: SET;
	END;

	Selector* = POINTER TO EXTENSIBLE RECORD
		a, b, c: INTEGER;
		simpleSelectors: Objects.Collection;
		lastSimpleSel: SimpleSelector;
	END;

	SimpleSelector* = POINTER TO EXTENSIBLE RECORD
		next: SimpleSelector;
		combinator: SHORTINT;
		elementName: String;
		subSelectors: Objects.Collection;
	END;
	
	SubSelector* = POINTER TO EXTENSIBLE RECORD END;

	Id* = POINTER TO EXTENSIBLE RECORD (SubSelector)
		value: String;
	END;

	Class* = POINTER TO EXTENSIBLE RECORD (SubSelector)
		value: String;
	END;

	Attribute* = POINTER TO EXTENSIBLE RECORD (SubSelector)
		name, value: String;
		relation: SHORTINT;
	END;

	Pseudo* = POINTER TO EXTENSIBLE RECORD (SubSelector)
		isLanguage: BOOLEAN;
		type: String;
	END;
	
	Declaration* = POINTER TO EXTENSIBLE RECORD
		property: String;
		expr: Objects.Collection;
		important: BOOLEAN;
	END;
	
	Term* = POINTER TO EXTENSIBLE RECORD
		operator, unaryOperator: SHORTINT;
		type: SHORTINT;
		intVal: INTEGER;
		realVal: REAL;
		stringVal: String;
		unit: SHORTINT;
		expr: Objects.Collection;	(* if term is a function *)
	END;
	
	Page* = POINTER TO EXTENSIBLE RECORD
		selector: String;
		pseudoPage: SHORTINT;
		declarations: Objects.Collection;
	END;
	
	FontFace* = POINTER TO EXTENSIBLE RECORD
		declarations: Objects.Collection;
	END;


PROCEDURE^ (this: Declaration) IsImportant*(): BOOLEAN, NEW;
PROCEDURE^ (this: SimpleSelector) GetElementName*(): String, NEW;
PROCEDURE^ (this: SimpleSelector) GetSubSelectors*(): Objects.Enumerator, NEW;
PROCEDURE^ IntToRGBA*(color: INTEGER; VAR r, g, b, a: SHORTINT);
PROCEDURE^ RGBAToInt*(r, g, b, a: SHORTINT; VAR color: INTEGER);


(* ------ StyleSheet ------ *)

PROCEDURE (this: StyleSheet) Init*, NEW;
BEGIN
	this.rulesets := Objects.NewArrayCollection();
	this.pages := Objects.NewArrayCollection();
	this.fontFaces := Objects.NewArrayCollection();
END Init;

PROCEDURE (this: StyleSheet) GetCharSet*(): String, NEW;
BEGIN
	RETURN this.charSet
END GetCharSet;

PROCEDURE (this: StyleSheet) SetCharSet*(charSet: String), NEW;
BEGIN
	this.charSet := charSet
END SetCharSet;

PROCEDURE (this: StyleSheet) GetRuleSets*(): Objects.Enumerator, NEW;
BEGIN
	RETURN this.rulesets.GetEnumerator()
END GetRuleSets;

PROCEDURE (this: StyleSheet) AddRuleSet*(rs: RuleSet), NEW;
BEGIN
	this.rulesets.Add(rs)
END AddRuleSet;

PROCEDURE (this: StyleSheet) GetPages*(): Objects.Enumerator, NEW;
BEGIN
	RETURN this.pages.GetEnumerator()
END GetPages;

PROCEDURE (this: StyleSheet) AddPage*(page: Page), NEW;
BEGIN
	this.pages.Add(page)
END AddPage;

PROCEDURE (this: StyleSheet) GetFontFaces*(): Objects.Enumerator, NEW;
BEGIN
	RETURN this.fontFaces.GetEnumerator()
END GetFontFaces;

PROCEDURE (this: StyleSheet) AddFontFace*(fontFace: FontFace), NEW;
BEGIN
	this.fontFaces.Add(fontFace)
END AddFontFace;


(* ------ RuleSet ------ *)

PROCEDURE (this: RuleSet) Init*, NEW;
BEGIN
	this.selectors := Objects.NewArrayCollection();
	this.declarations := Objects.NewArrayCollection();
	INCL(this.media, All);
	this.hasImportantDeclarations := FALSE; this.hasNotImportantDeclarations := FALSE
END Init;

PROCEDURE (this: RuleSet) GetMedia*(): SET, NEW;
BEGIN
	RETURN this.media
END GetMedia;

PROCEDURE (this: RuleSet) IsMediumSupported*(medium: SHORTINT): BOOLEAN, NEW;
BEGIN
	RETURN medium IN this.media
END IsMediumSupported;

PROCEDURE (this: RuleSet) AddMedium*(medium: SHORTINT), NEW;
BEGIN
	IF medium IN {All, Aural, Braille, Embossed, Handheld, Print, Projection, Screen, TTY, TV} THEN
		IF medium # All THEN EXCL(this.media, All) END;
		this.media := this.media + {medium}
	END
END AddMedium;

PROCEDURE (this: RuleSet) SetMedia*(media: SET), NEW;
BEGIN
	this.media := media
END SetMedia;

PROCEDURE (this: RuleSet) GetSelectors*(): Objects.Enumerator, NEW;
BEGIN
	RETURN this.selectors.GetEnumerator()
END GetSelectors;

PROCEDURE (this: RuleSet) AddSelector*(selector: Selector), NEW;
BEGIN
	this.selectors.Add(selector)
END AddSelector;

PROCEDURE (this: RuleSet) GetDeclarations*(): Objects.Enumerator, NEW;
BEGIN
	RETURN this.declarations.GetEnumerator();
END GetDeclarations;

PROCEDURE (this: RuleSet) AddDeclaration*(declaration: Declaration), NEW;
BEGIN
	IF declaration.IsImportant() THEN
		this.hasImportantDeclarations := TRUE
	ELSE
		this.hasNotImportantDeclarations := TRUE
	END;
	this.declarations.Add(declaration)
END AddDeclaration;

PROCEDURE (this: RuleSet) HasImportantDeclarations*(): BOOLEAN, NEW;
BEGIN
	RETURN this.hasImportantDeclarations
END HasImportantDeclarations;

PROCEDURE (this: RuleSet) HasNotImportantDeclarations*(): BOOLEAN, NEW;
BEGIN
	RETURN this.hasNotImportantDeclarations
END HasNotImportantDeclarations;


(* ------ Selector ------ *)

PROCEDURE (this: Selector) Init*, NEW;
BEGIN
	this.a := 0; this.b := 0; this.c := 0;
	this.simpleSelectors := Objects.NewArrayCollection();
END Init;

PROCEDURE (this: Selector) GetSpecifity*(VAR a, b, c: INTEGER), NEW;
BEGIN
	a := this.a; b := this.b; c := this.c
END GetSpecifity;

PROCEDURE (this: Selector) GetSimpleSelectors*(): Objects.Enumerator, NEW;
BEGIN
	RETURN this.simpleSelectors.GetEnumerator()
END GetSimpleSelectors;

PROCEDURE (this: Selector) AddSimpleSelector*(simpleSelector: SimpleSelector), NEW;
	VAR s: String; enum: Objects.Enumerator; p: ANYPTR;
BEGIN
	s := simpleSelector.GetElementName();
	IF (s # NIL) & (s^ # "*") THEN INC(this.c) END;
	enum := simpleSelector.GetSubSelectors();
	WHILE enum.HasMoreElements() DO
		p := enum.GetNext();
		IF p IS Id THEN
			INC(this.a)
		ELSE
			INC(this.b)
		END
	END;
	IF this.lastSimpleSel # NIL THEN this.lastSimpleSel.next := simpleSelector END;
	this.lastSimpleSel := simpleSelector;
	this.simpleSelectors.Add(simpleSelector)
END AddSimpleSelector;


(* ------ SimpleSelector ------ *)

PROCEDURE (this: SimpleSelector) Init*, NEW;
BEGIN
	this.combinator := Undefined;
	this.subSelectors := Objects.NewArrayCollection();
END Init;

PROCEDURE (this: SimpleSelector) GetNext*(): SimpleSelector, NEW;
BEGIN
	RETURN this.next
END GetNext;

PROCEDURE (this: SimpleSelector) GetCombinator*(): SHORTINT, NEW;
BEGIN
	RETURN this.combinator
END GetCombinator;

PROCEDURE (this: SimpleSelector) SetCombinator*(combinator: SHORTINT), NEW;
BEGIN
	IF combinator IN {Descendant, Child, Sibling} THEN
		this.combinator := combinator
	END
END SetCombinator;

PROCEDURE (this: SimpleSelector) GetElementName*(): String, NEW;
BEGIN
	RETURN this.elementName
END GetElementName;

PROCEDURE (this: SimpleSelector) SetElementName*(elementName: String), NEW;
BEGIN
	this.elementName := elementName
END SetElementName;

PROCEDURE (this: SimpleSelector) GetSubSelectors*(): Objects.Enumerator, NEW;
BEGIN
	RETURN this.subSelectors.GetEnumerator()
END GetSubSelectors;

PROCEDURE (this: SimpleSelector) AddSubSelector*(subSelector: SubSelector), NEW;
BEGIN
	this.subSelectors.Add(subSelector)
END AddSubSelector;


(* ------ Id ------ *)

PROCEDURE (this: Id) GetValue*(): String, NEW;
BEGIN
	RETURN this.value
END GetValue;

PROCEDURE (this: Id) SetValue*(value: String), NEW;
BEGIN
	this.value := value
END SetValue;


(* ------ Class ------ *)

PROCEDURE (this: Class) GetValue*(): String, NEW;
BEGIN
	RETURN this.value
END GetValue;

PROCEDURE (this: Class) SetValue*(value: String), NEW;
BEGIN
	this.value := value
END SetValue;


(* ------ Attribute ------ *)

PROCEDURE (this: Attribute) Init*, NEW;
BEGIN
	this.relation := Undefined
END Init;

PROCEDURE (this: Attribute) GetName*(): String, NEW;
BEGIN
	RETURN this.name
END GetName;

PROCEDURE (this: Attribute) SetName*(name: String), NEW;
BEGIN
	this.name := name
END SetName;

PROCEDURE (this: Attribute) GetRelation*(): SHORTINT, NEW;
BEGIN
	RETURN this.relation
END GetRelation;

PROCEDURE (this: Attribute) SetRelation*(relation: SHORTINT), NEW;
BEGIN
	IF relation IN {Equal, Includes, Dashmatch} THEN
		this.relation := relation
	END
END SetRelation;

PROCEDURE (this: Attribute) GetValue*(): String, NEW;
BEGIN
	RETURN this.value
END GetValue;

PROCEDURE (this: Attribute) SetValue*(value: String), NEW;
BEGIN
	this.value := value
END SetValue;


(* ------ Pseudo ------ *)

PROCEDURE (this: Pseudo) GetType*(): String, NEW;
BEGIN
	IF ~this.isLanguage THEN RETURN this.type ELSE RETURN NIL END
END GetType;

PROCEDURE (this: Pseudo) SetType*(type: String), NEW;
BEGIN
	this.type := type;
	this.isLanguage := FALSE
END SetType;

PROCEDURE (this: Pseudo) GetLanguage*(): String, NEW;
BEGIN
	IF this.isLanguage THEN RETURN this.type ELSE RETURN NIL END
END GetLanguage;

PROCEDURE (this: Pseudo) IsLanguage*(): BOOLEAN, NEW;
BEGIN
	RETURN this.isLanguage
END IsLanguage;

PROCEDURE (this: Pseudo) SetLanguage*(language: String), NEW;
BEGIN
	this.type := language;
	this.isLanguage := TRUE
END SetLanguage;


(* ------ Declaration ------ *)

PROCEDURE (this: Declaration) Init*, NEW;
BEGIN
	this.expr := Objects.NewArrayCollection();;
	this.important := FALSE
END Init;

PROCEDURE (this: Declaration) GetProperty*(): String, NEW;
BEGIN
	RETURN this.property
END GetProperty;

PROCEDURE (this: Declaration) SetProperty*(property: String), NEW;
BEGIN
	this.property := property
END SetProperty;

PROCEDURE (this: Declaration) GetTerms*(): Objects.Enumerator, NEW;
BEGIN
	RETURN this.expr.GetEnumerator()
END GetTerms;

PROCEDURE (this: Declaration) AddTerm*(term: Term), NEW;
BEGIN
	this.expr.Add(term)
END AddTerm;

PROCEDURE (this: Declaration) RemoveTerm*(term: Term), NEW;
BEGIN
	this.expr.Remove(term)
END RemoveTerm;

PROCEDURE (this: Declaration) IsImportant*(): BOOLEAN, NEW;
BEGIN
	RETURN this.important
END IsImportant;

PROCEDURE (this: Declaration) SetImportant*(important: BOOLEAN), NEW;
BEGIN
	this.important := important
END SetImportant;


(* ------ Term ------ *)

PROCEDURE (this: Term) Init*, NEW;
BEGIN
	this.operator := Undefined; this.unaryOperator := Plus; this.type := Undefined; this.unit := Undefined;
	this.intVal := 0; this.realVal := 0.0
END Init;

PROCEDURE (this: Term) GetOperator*(): SHORTINT, NEW;
BEGIN
	RETURN this.operator
END GetOperator;

PROCEDURE (this: Term) SetOperator*(operator: SHORTINT), NEW;
BEGIN
	IF operator IN {Add, Sub, Times, Slash, Seq} THEN
		this.operator := operator
	END
END SetOperator;

PROCEDURE (this: Term) GetUnaryOperator*(): SHORTINT, NEW;
BEGIN
	RETURN this.unaryOperator
END GetUnaryOperator;

PROCEDURE (this: Term) SetUnaryOperator*(unaryOperator: SHORTINT), NEW;
BEGIN
	IF (unaryOperator = Minus) OR (unaryOperator = Plus) THEN
		this.unaryOperator := unaryOperator
	END
END SetUnaryOperator;

PROCEDURE (this: Term) GetType*(): SHORTINT, NEW;
BEGIN
	RETURN this.type
END GetType;

PROCEDURE (this: Term) SetType*(type: SHORTINT), NEW;
BEGIN
	CASE type OF
	| IntNumber, Color, Ident: this.realVal := 0.0; this.stringVal := NIL; this.unit := Undefined; this.expr := NIL
	| RealNumber: this.intVal := 0; this.stringVal := NIL; this.unit := Undefined; this.expr := NIL
	| Percent: this.realVal := 0.0; this.stringVal := NIL; this.unit := Undefined; this.expr := NIL
	| IntDimension: this.realVal := 0.0; this.stringVal := NIL; this.expr := NIL
	| RealDimension: this.intVal := 0; this.stringVal := NIL; this.expr := NIL
	| Function: this.intVal := 0; this.realVal := 0.0; this.unit := Undefined
	| StringVal, StringIdent, URI: this.intVal := 0; this.realVal := 0.0; this.unit := Undefined; this.expr := NIL
	| UnicodeRange: this.intVal := 0; this.realVal := 0.0; this.stringVal := NIL; this.unit := Undefined; this.expr := NIL
	ELSE RETURN
	END;
	this.type := type
END SetType;

PROCEDURE (this: Term) GetIntVal*(): INTEGER, NEW;
BEGIN
	RETURN this.intVal
END GetIntVal;

PROCEDURE (this: Term) SetIntVal*(intVal: INTEGER), NEW;
BEGIN
	this.intVal := intVal
END SetIntVal;

PROCEDURE (this: Term) GetRealVal*(): REAL, NEW;
BEGIN
	RETURN this.realVal
END GetRealVal;

PROCEDURE (this: Term) SetRealVal*(realVal: REAL), NEW;
BEGIN
	this.realVal := realVal
END SetRealVal;

PROCEDURE (this: Term) GetStringVal*(): String, NEW;
BEGIN
	RETURN this.stringVal
END GetStringVal;

PROCEDURE (this: Term) SetStringVal*(stringVal: String), NEW;
BEGIN
	this.stringVal := stringVal
END SetStringVal;

PROCEDURE (this: Term) IsStringIdent*(IN ident: ARRAY OF CHAR): BOOLEAN, NEW;
BEGIN
	RETURN (this.type = StringIdent) & (this.stringVal # NIL) & (this.stringVal^ = ident)
END IsStringIdent;

PROCEDURE (this: Term) IsIdent*(ident: INTEGER): BOOLEAN, NEW;
BEGIN
	RETURN (this.type = Ident) & (this.intVal = ident)
END IsIdent;

PROCEDURE (this: Term) GetUnit*(): SHORTINT, NEW;
BEGIN
	RETURN this.unit
END GetUnit;

PROCEDURE (this: Term) SetUnit*(unit: SHORTINT), NEW;
BEGIN
	IF unit IN {em, ex, ch, rem, vw, vh, vmin, vmax, px, in, cm, mm, pt, pc, deg, grad, rad, ms, s, Hz, kHz} THEN
		this.unit := unit
	END
END SetUnit;

PROCEDURE (this: Term) IsLength*(): BOOLEAN, NEW;
BEGIN
	RETURN (this.type IN {IntDimension, RealDimension})
				& (this.unit IN {em, ex, ch, rem, vw, vh, vmin, vmax, px, in, cm, mm, pt, pc})
END IsLength;

PROCEDURE (this: Term) IsAngle*(): BOOLEAN, NEW;
BEGIN
	RETURN (this.type IN {IntDimension, RealDimension}) & (this.unit IN {deg, grad, rad})
END IsAngle;

PROCEDURE (this: Term) IsTime*(): BOOLEAN, NEW;
BEGIN
	RETURN (this.type IN {IntDimension, RealDimension}) & (this.unit IN {ms, s})
END IsTime;

PROCEDURE (this: Term) IsFrequency*(): BOOLEAN, NEW;
BEGIN
	RETURN (this.type IN {IntDimension, RealDimension}) & (this.unit IN {Hz, kHz})
END IsFrequency;

PROCEDURE (this: Term) GetColor*(VAR r, g, b, a: SHORTINT), NEW;
BEGIN
	IntToRGBA(this.intVal, r, g, b, a)
END GetColor;

PROCEDURE (this: Term) SetColor*(r, g, b, a: SHORTINT), NEW;
BEGIN
	RGBAToInt(r, g, b, a, this.intVal)
END SetColor;

PROCEDURE (this: Term) GetTerms*(): Objects.Enumerator, NEW;
BEGIN
	RETURN this.expr.GetEnumerator()
END GetTerms;

PROCEDURE (this: Term) AddTerm*(term: Term), NEW;
BEGIN
	IF this.expr = NIL THEN this.expr := Objects.NewArrayCollection() END;
	this.expr.Add(term)
END AddTerm;

(** added JT: convenience procedure e.g. for property 'font-family':
	return a single string or a concatenated sequence of strings with 'sep' in between.
	'buf' provides a reusabe string buffer allocated on demand if NIL is passed.
*)
PROCEDURE (this: Term) GetStringSeq*(IN sep: ARRAY OF CHAR; VAR buf: DStrings.DynamicString): String, NEW;
	VAR seq: Objects.Enumerator;  val: String;
BEGIN
	val := this.GetStringVal();
	IF (val = NIL) & (this.operator = Seq) THEN
		IF buf = NIL THEN buf := DStrings.NewDynamicString() ELSE buf.Clear END;
		seq := this.GetTerms();
		WHILE seq.HasMoreElements() DO
			val := seq.GetNext()(Term).GetStringVal();
			IF val # NIL THEN
				IF buf.length > 0 THEN buf.Append(sep) END;
				buf.Append(val)
			END
		END;
		val := buf.ToString()
	END;
	RETURN val
END GetStringSeq;


(* ------ Page ------ *)

PROCEDURE (this: Page) Init*, NEW;
BEGIN
	this.pseudoPage := Undefined;
	this.declarations := Objects.NewArrayCollection()
END Init;

PROCEDURE (this: Page) GetSelector*(): String, NEW;
BEGIN
	RETURN this.selector
END GetSelector;

PROCEDURE (this: Page) SetSelector*(selector: String), NEW;
BEGIN
	this.selector := selector
END SetSelector;

PROCEDURE (this: Page) GetPseudoPage*(): SHORTINT, NEW;
BEGIN
	RETURN this.pseudoPage
END GetPseudoPage;

PROCEDURE (this: Page) SetPseudoPage*(pseudoPage: SHORTINT), NEW;
BEGIN
	IF pseudoPage IN {Left, Right, First} THEN
		this.pseudoPage := pseudoPage
	END
END SetPseudoPage;

PROCEDURE (this: Page) GetDeclarations*(): Objects.Enumerator, NEW;
BEGIN
	RETURN this.declarations.GetEnumerator()
END GetDeclarations;

PROCEDURE (this: Page) AddDeclaration*(declaration: Declaration), NEW;
BEGIN
	this.declarations.Add(declaration)
END AddDeclaration;


(* ------ FontFace ------ *)

PROCEDURE (this: FontFace) Init*, NEW;
BEGIN
	this.declarations := Objects.NewArrayCollection()
END Init;

PROCEDURE (this: FontFace) GetDeclarations*(): Objects.Enumerator, NEW;
BEGIN
	RETURN this.declarations.GetEnumerator()
END GetDeclarations;

PROCEDURE (this: FontFace) AddDeclaration*(declaration: Declaration), NEW;
BEGIN
	this.declarations.Add(declaration)
END AddDeclaration;


PROCEDURE IntToRGBA*(color: INTEGER; VAR r, g, b, a: SHORTINT);
BEGIN
	a := SHORT(color DIV 1000000H);
	r := SHORT(color DIV 10000H MOD 100H);
	g := SHORT(color DIV 100H MOD 100H);
	b := SHORT(color MOD 100H)
END IntToRGBA;

PROCEDURE RGBAToInt*(r, g, b, a: SHORTINT; VAR color: INTEGER);
BEGIN
	color := ASH(a, 24) + ASH(r, 16) + ASH(g, 8) + b
END RGBAToInt;

END W3cCSS.