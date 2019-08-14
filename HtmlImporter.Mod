MODULE W3cHtmlImporter;

	(* This module provides HTML importers for files and for the clipboard.
	J. Templ, 2018-05-05
	
	with debug code (writing the HTML tree, storing native clipboard data, dumping CCS terms): No
	*)

	IMPORT Stores, Files, TextModels, TextViews, WinOle, WinApi, Views, Properties, SYSTEM,
		Fonts, TextMappers, TextRulers, StdLinks, Strings, Ports, Math,
		Streams := W3cStreams,
		DStrings := W3cDStrings,
		Objects := W3cObjects,
		HTMLParsers := W3cHTMLParsers,
		DOM := W3cDOM,
		CSSParsers := W3cCSSParsers,
		CSS := W3cCSS
		;
	
	CONST
		CR = 0DX; LF = 0AX; TAB = 09X; SOFTHYPHEN = 0ADX;
		
		px = Fonts.point * 72 DIV 96;
		OffsetEm = 0.3; (* em, default for SUB and SUP *)
		
		(* states of lazy writer *)
		Para = 0;  (* a delayed WritePara is required *)
		Line = 1;  (* a delayed WriteLn is required *)
		Tab = 2;  (* a delayed WriteTab is required *)
		Space = 3; (* a delayed space is required *)
		Text = 4; (* nothing delayed *)
		
		(* initial property values *)
		TabSizeInitial = 8; (* for <PRE> *)
		FontSizeInitial = 12 * Fonts.point;
		WeightInitial = Fonts.normal;
		ColorInitial = Ports.black;
		OffsetInitial = 0;
		StyleInitial = {};
		OptsInitial = {TextRulers.leftAdjust};
		
		FontFamily_Serif = "Times New Roman";
		FontFamily_SansSerif = "Arial Unicode MS";
		FontFamily_Monospace = "Courier New";
		FontFamily_Initial = FontFamily_Serif;

		Display_Inline = 0;
		Display_Block = 1;
		Display_None = 2;
		
		ListStyleType_Disc = 0;
		ListStyleType_Circle = 1;
		ListStyleType_Square = 2;
		ListStyleType_None = 3;
		ListStyleType_Decimal = 4;
		ListStyleType_UpperAlpha = 5;
		ListStyleType_LowerAlpha = 6;
		ListStyleType_UpperRoman = 7;
		ListStyleType_LowerRoman = 8;
		ListStyleType_Initial = ListStyleType_Disc;
		Display_Initial = Display_Inline;
		
		(* elements of attrSet *)
		Attr_Style = 0;
		Attr_Type = 1;
		Attr_Start = 2;
		Attr_FontSize = 10;
		Attr_FontWeight = 11;
		Attr_FontStyle = 12;
		Attr_FontFamily = 13;
		Attr_Color = 14;
		Attr_MarginLeft = 15;
		Attr_MarginTop = 16;
		Attr_MarginBottom = 17;
		Attr_VerticalAlign = 18;
		Attr_Display = 19;
		
	TYPE
		String = DOM.String;
		
		Context = POINTER TO RECORD
			parent, dsc, root: Context;
			e: DOM.Element;
			attrSet: SET; (* out param of ProcessAttributes *)
			display: BYTE;
			pre: BOOLEAN; (* preserve white space; only used for PRE *)
			tabSize: SHORTINT; (* number of spaces used for TAB in PRE element *)
			listStyleType: BYTE;
			(* ruler attributes *)
			marginTop, marginBottom, left, indent: INTEGER; opts: SET;
			(* text attributes *)
			color, weight, size, offset: INTEGER;
			typeface-: Fonts.Typeface;
			style-: SET;
		END;
	
	VAR
		state: INTEGER; (* lazy writer state machine *)
		nofEmptyLines: INTEGER; (* for skipping the trailing empty lines in PRE *)
		paraAttr: TextModels.Attributes; (* the attributes to be used for WritePara *)
		out: TextMappers.Formatter;
		listNum: INTEGER;
		maxVerticalSpace: INTEGER;
		
		(* caching *)
		cssParser: CSSParsers.Parser; (* reusable parser for inline style attribute *)
		inlineStyle: CSS.RuleSet; (* if AttrStyle IN attrSet, for avoiding to parse style twice per element *)
		colorMap: Files.Reader;
		dstr: DStrings.DynamicString;
		
		
		
	PROCEDURE SetInitial(ctx: Context);
	BEGIN
		ctx.attrSet := {}; ctx.tabSize := TabSizeInitial; ctx.listStyleType := ListStyleType_Initial;
		ctx.marginTop := 0; ctx.marginBottom := 0; ctx.left := 0; ctx.indent := 0; ctx.opts := OptsInitial;
		ctx.color := ColorInitial; ctx.weight := WeightInitial; ctx.size := FontSizeInitial;
		ctx.offset := OffsetInitial; ctx.typeface := FontFamily_Initial; ctx.style := StyleInitial;
		ctx.display := Display_Initial;
	END SetInitial;

	PROCEDURE NewInitialContext(e: DOM.Element): Context;
		VAR ctx: Context;
	BEGIN
		NEW(ctx); ctx.parent := ctx; ctx.root := ctx; ctx.e := e; ctx.pre := FALSE;
		SetInitial(ctx);
		RETURN ctx;
	END NewInitialContext;
	
	PROCEDURE NewContext(ctx: Context; e: DOM.Element): Context;
		VAR dsc: Context;
	BEGIN
		dsc := ctx.dsc; (* tries to reuse unused stack elements *)
		IF dsc = NIL THEN NEW(dsc); dsc.parent := ctx; ctx.dsc := dsc; dsc.root := ctx.root; END; 
		dsc.e := e; dsc.attrSet := {};
		(* not inherited *)
		dsc.display := Display_Inline;
		dsc.marginTop := 0; dsc.marginBottom := 0;
		dsc.left := ctx.left; (* left is accumulative; marginLeft is not inherited *)
		dsc.indent := 0; 
		(* inherited *)
		dsc.pre := ctx.pre;
		dsc.tabSize := ctx.tabSize;
		dsc.listStyleType := ctx.listStyleType;
		dsc.opts := ctx.opts;
		dsc.color := ctx.color;
		dsc.weight := ctx.weight;
		dsc.size := ctx.size;
		dsc.offset := ctx.offset;
		dsc.typeface := ctx.typeface;
		dsc.style := ctx.style; (* defined as not inherited, but in all browsers it is *)
		RETURN dsc;
	END NewContext;

	PROCEDURE NewRuler(lead, left, indent: INTEGER; opts: SET): TextRulers.Ruler;
		VAR new: TextRulers.Ruler;
	BEGIN
		new := TextRulers.dir.New(TextRulers.dir.NewStyle(TextRulers.dir.attr));
		IF lead # new.style.attr.lead THEN TextRulers.SetLead(new, lead) END;
		IF left # new.style.attr.left THEN TextRulers.SetLeft(new, left) END;
		IF left + indent # new.style.attr.first THEN TextRulers.SetFirst(new, left + indent) END;
		IF opts # new.style.attr.opts THEN
			IF opts = {TextRulers.leftAdjust} THEN TextRulers.SetLeftFlush(new)
			ELSIF opts = {TextRulers.rightAdjust} THEN TextRulers.SetRightFlush(new)
			ELSIF opts = {TextRulers.leftAdjust, TextRulers.rightAdjust} THEN TextRulers.SetJustified(new)
			ELSIF opts = {} THEN TextRulers.SetCentered(new)
			ELSE (*internal error*) ASSERT(opts = new.style.attr.opts)
			END
		END;
		RETURN new
	END NewRuler;
	
	PROCEDURE GetEffectiveRulerAttr(): TextRulers.Attributes;
		VAR text: TextModels.Model;  last: TextRulers.Ruler; rpos: INTEGER; a: TextRulers.Attributes;
	BEGIN
		text := out.rider.Base();
		TextRulers.GetValidRuler(text, text.Length(), -1, last, rpos);
		IF last = NIL THEN a := TextRulers.dir.attr ELSE a := last.style.attr END;
		RETURN a
	END GetEffectiveRulerAttr;

	PROCEDURE OutRuler(ctx: Context);
		VAR textEmpty: BOOLEAN; a: TextRulers.Attributes; savedAttr: TextModels.Attributes;
	BEGIN
		textEmpty := out.rider.Base().Length() = 0;
		savedAttr := out.rider.attr; out.rider.SetAttr(paraAttr);
		IF ~textEmpty THEN out.WriteLn END;
		a := GetEffectiveRulerAttr();
		IF (maxVerticalSpace # a.lead) OR (ctx.left # a.left) OR (ctx.left + ctx.indent # a.first) OR (ctx.opts # a.opts) THEN
			out.WriteView(NewRuler(maxVerticalSpace, ctx.left, ctx.indent, ctx.opts))
		ELSIF ~textEmpty THEN
			out.WritePara
		END;
		maxVerticalSpace := 0; out.rider.SetAttr(savedAttr)
	END OutRuler;

	PROCEDURE OutLine;
		VAR i: INTEGER;
	BEGIN
		FOR i := 1 TO nofEmptyLines DO out.WriteLn END; (* TODO which attr?? *)
		nofEmptyLines := 0
	END OutLine;
	
	PROCEDURE WriteBR(ctx: Context);
	BEGIN
		IF state = Para THEN OutRuler(ctx) END;
		state := Line; INC(nofEmptyLines)
	END WriteBR;

	PROCEDURE WriteSpace(ctx: Context);
	BEGIN
		CASE state OF (* lazy write of appropriate white space before Text *)
		| Para: OutRuler(ctx); nofEmptyLines := 0
		| Line: OutLine
		| Tab: out.WriteTab
		| Space: out.WriteChar(" ")
		END;
	END WriteSpace;

	PROCEDURE WriteChar(ch: CHAR; ctx: Context);
		VAR i: INTEGER;
	BEGIN
		IF ch > " " THEN (* Text *)
			IF state # Text THEN WriteSpace(ctx) END;
			out.WriteChar(ch);
			state := Text
		ELSE (* white space *)
			IF ctx.pre THEN
				IF ch = " " THEN
					IF state # Text THEN WriteSpace(ctx) END;
					out.WriteChar(" "); state := Text; nofEmptyLines := 0
				ELSIF ch = TAB THEN
					IF state # Text THEN WriteSpace(ctx) END;
					FOR i := 1 TO ctx.tabSize DO out.WriteChar(" ") END;
					state := Text; nofEmptyLines := 0
				ELSE WriteBR(ctx)
				END
			ELSIF state = Text THEN state := Space
			END
		END
	END WriteChar;

	PROCEDURE WriteView(v: Views.View; ctx: Context);
	BEGIN
		IF state # Text THEN WriteSpace(ctx) END;
		out.WriteView(v);
		state := Text
	END WriteView;

	PROCEDURE WriteHiddenView(v: Views.View; ctx: Context); (* TODO required? *)
	BEGIN
		out.WriteView(v);
	END WriteHiddenView;
	
	(* writing ruler/para is delayed until required for follow-up Text.
		The current ruler style with a max. vertical space of all consumed rulers will be used then. *)
	PROCEDURE WritePara(verticalSpace: INTEGER);
	BEGIN
		(* a Para immediately following a Tab must be ignored because it would introduce a new line e.g. in a list.
		In order to continue after a list or table with an empty element, the state must be set to Text. *)
		IF state # Tab THEN
			IF state = Line THEN OutLine END;
			state := Para; maxVerticalSpace := MAX(verticalSpace, maxVerticalSpace)
		END
	END WritePara;
	
	PROCEDURE WriteParaTop(ctx: Context);
	BEGIN
		IF ctx.display = Display_Block THEN WritePara(ctx.marginTop) END
	END WriteParaTop;
	
	PROCEDURE WriteParaBottom(ctx: Context);
	BEGIN
		IF ctx.display = Display_Block THEN WritePara(ctx.marginBottom) END
	END WriteParaBottom;

	PROCEDURE WriteTab(ctx: Context);
	BEGIN
		IF ~(state IN {Text, Space}) THEN WriteSpace(ctx) END;
		state := Tab
	END WriteTab;

	PROCEDURE SetCtxAttr (ctx: Context);
		VAR i: INTEGER; ch, nch: CHAR; rider: TextModels.Writer; attr: TextModels.Attributes;
	BEGIN
		rider := out.rider; attr := rider.attr;
		IF ctx.size # attr.font.size THEN
			rider.SetAttr(TextModels.NewSize(rider.attr, ctx.size))
		END;
		IF ctx.weight # attr.font.weight THEN
			rider.SetAttr(TextModels.NewWeight(rider.attr, ctx.weight))
		END;
		IF ctx.typeface # attr.font.typeface THEN
			rider.SetAttr(TextModels.NewTypeface(rider.attr, ctx.typeface))
		END;
		IF ctx.style # attr.font.style THEN
			rider.SetAttr(TextModels.NewStyle(rider.attr, ctx.style))
		END;
		IF ctx.color # attr.color THEN
			rider.SetAttr(TextModels.NewColor(rider.attr, ctx.color))
		END;
		IF ctx.offset # attr.offset THEN
			rider.SetAttr(TextModels.NewOffset(rider.attr, ctx.offset))
		END;
	END SetCtxAttr;

	PROCEDURE WriteText(IN str: ARRAY OF CHAR; ctx: Context);
		VAR i: INTEGER; ch, nch: CHAR; rider: TextModels.Writer; attr: TextModels.Attributes;
	BEGIN
		i := 0; ch := str[0]; SetCtxAttr(ctx);
		WHILE ch # 0X DO
			WriteChar(ch, ctx); INC(i); nch := str[i];
			IF (ch = CR) & (nch = LF) THEN INC(i); ch := str[i]
			ELSE ch := nch
			END
		END
	END WriteText;

	PROCEDURE WriteRuler (ruler: TextRulers.Ruler; verticalSpace, nextState: INTEGER; ctx: Context);
		VAR len, rpos: INTEGER; t: TextModels.Model; tr: TextRulers.Ruler; p: TextRulers.Prop;
			rd: TextModels.Reader; ch: CHAR; a: TextRulers.Attributes; savedAttr: TextModels.Attributes;
	BEGIN
		maxVerticalSpace := MAX(verticalSpace, maxVerticalSpace);
		savedAttr := out.rider.attr; out.rider.SetAttr(paraAttr);
		t := out.rider.Base(); len := t.Length();
		(* merge if trailing ruler or para exists; thus avoids empty lines e.g. when using <HR> inside a table *)
		TextRulers.GetValidRuler(t, len, -1, tr, rpos);
		IF rpos = len - 1 THEN (* tr is the trailing ruler; apply ruler settings to tr *)
			TextRulers.SetLead(ruler, MAX(tr.style.attr.lead, maxVerticalSpace));
			p := ruler.style.attr.Prop()(TextRulers.Prop);
			ruler.style.SetAttr(TextRulers.ModifiedAttr(ruler.style.attr, p))
		ELSE (* check for trailing para *)
			IF tr = NIL THEN a := TextRulers.dir.attr ELSE a := tr.style.attr END;
			rd := t.NewReader(NIL); rd.SetPos(len); rd.ReadPrevChar(ch);
			IF ch = TextModels.para THEN (* trailing para; replace para by ruler *)
				t.Delete(len - 1, len);
				TextRulers.SetLead(ruler, MAX(a.lead, maxVerticalSpace));
				out.SetPos(len - 1);
				out.WriteView(ruler);
			ELSE (* nothing special *)
				IF len # 0 THEN out.WriteLn END;
				IF maxVerticalSpace # ruler.style.attr.lead THEN TextRulers.SetLead(ruler, maxVerticalSpace) END;
				IF ~a.Equals(ruler.style.attr) THEN out.WriteView(ruler) ELSE out.WritePara END
			END
		END;
		maxVerticalSpace := 0; state := nextState; out.rider.SetAttr(savedAttr)
	END WriteRuler;
	
	PROCEDURE Round (val: REAL): INTEGER;
	BEGIN RETURN SHORT(ENTIER(Math.Round(val)))
	END Round;

	PROCEDURE GetLength (term: CSS.Term; ctx: Context): INTEGER;
		VAR val: REAL; unitsize: INTEGER;
	BEGIN
		CASE term.GetType() OF
		| CSS.RealDimension: val := term.GetRealVal()
		| CSS.IntDimension: val := term.GetIntVal()
		END;
		CASE term.GetUnit() OF
		| CSS.Undefined: unitsize := ctx.size;
		| CSS.px: unitsize := px
		| CSS.pt: unitsize := Fonts.point
		| CSS.pc: unitsize := Fonts.point * 12
		| CSS.mm: unitsize := Fonts.mm
		| CSS.cm: unitsize := Fonts.mm * 10
		| CSS.in: unitsize := Fonts.point * 72
		| CSS.em: unitsize := ctx.size
		| CSS.ex: unitsize := ctx.size DIV 2 (* simplified *)
		| CSS.rem: unitsize := ctx.root.size
		END;
		IF term.GetUnaryOperator() = CSS.Minus THEN val := -val END;
		RETURN Round(val * unitsize)
	END GetLength;

	PROCEDURE SetFontFamily(decl: CSS.Declaration; ctx: Context);
		VAR terms: Objects.Enumerator; term: CSS.Term; fontfamily: String;
			attr: TextModels.Attributes;
	BEGIN
		terms := decl.GetTerms(); INCL(ctx.attrSet, Attr_FontFamily); attr := NIL;
		REPEAT
			term := terms.GetNext()(CSS.Term);
			fontfamily := term.GetStringSeq(" ", dstr);
			IF (fontfamily # NIL) & (fontfamily^ # "") THEN
				IF fontfamily^ = "sans-serif" THEN ctx.typeface := FontFamily_SansSerif
				ELSIF fontfamily^ = "serif" THEN ctx.typeface :=FontFamily_Serif
				ELSIF fontfamily^ = "monospace" THEN ctx.typeface :=FontFamily_Monospace
				ELSIF fontfamily^ = "inherit" THEN ctx.typeface := ctx.parent.typeface
				ELSIF fontfamily^ = "initial" THEN ctx.typeface := FontFamily_Initial
				ELSE ctx.typeface := fontfamily^$
				END;
				attr := TextModels.NewTypeface(out.rider.attr, ctx.typeface)
			END;
		UNTIL ~terms.HasMoreElements() OR ((attr # NIL) & ~attr.font.IsAlien());
	END SetFontFamily;

	PROCEDURE SetTextAlign(decl: CSS.Declaration; ctx: Context);
		VAR term: CSS.Term; ident: String;
	BEGIN
		term := decl.GetTerms().GetNext()(CSS.Term);
		ident := term.GetStringVal();
		IF ident # NIL THEN
			IF ident^ = "center" THEN ctx.opts := {}
			ELSIF ident^ = "left" THEN ctx.opts := {TextRulers.leftAdjust}
			ELSIF ident^ = "right" THEN ctx.opts := {TextRulers.rightAdjust}
			ELSIF ident^ = "justify" THEN ctx.opts := {TextRulers.leftAdjust, TextRulers.rightAdjust}
			ELSIF ident^ = "inherit" THEN ctx.opts := ctx.parent.opts
			ELSIF ident^ = "initial" THEN ctx.opts := OptsInitial
			END
		END
	END SetTextAlign;

	PROCEDURE SetMarginLeft(decl: CSS.Declaration; ctx: Context);
		VAR term: CSS.Term; ident: String; length: INTEGER;
	BEGIN
		term := decl.GetTerms().GetNext()(CSS.Term);
		IF term.IsLength() THEN length := GetLength(term, ctx)
		ELSE ident := term.GetStringVal();
			IF ident # NIL THEN
				IF ident^ = "inherit" THEN length := 0 (* TODO *)
				ELSIF ident^ = "initial" THEN length := 0
				ELSE RETURN
				END
			ELSE RETURN
			END
		END;
		INC(ctx.left, length);
		INCL(ctx.attrSet, Attr_MarginLeft)
	END SetMarginLeft;

	PROCEDURE SetMarginTop(decl: CSS.Declaration; ctx: Context);
		VAR term: CSS.Term; ident: String; length: INTEGER;
	BEGIN
		term := decl.GetTerms().GetNext()(CSS.Term);
		IF term.IsLength() THEN ctx.marginTop := GetLength(term, ctx)
		ELSE ident := term.GetStringVal();
			IF ident # NIL THEN
				IF ident^ = "inherit" THEN ctx.marginTop := ctx.parent.marginTop
				ELSIF ident^ = "initial" THEN ctx.marginTop := 0
				ELSE RETURN
				END
			ELSE RETURN
			END
		END;
		INCL(ctx.attrSet, Attr_MarginTop)
	END SetMarginTop;

	PROCEDURE SetMarginBottom(decl: CSS.Declaration; ctx: Context);
		VAR term: CSS.Term; ident: String; length: INTEGER;
	BEGIN
		term := decl.GetTerms().GetNext()(CSS.Term);
		IF term.IsLength() THEN ctx.marginBottom := GetLength(term, ctx)
		ELSE ident := term.GetStringVal();
			IF ident # NIL THEN
				IF ident^ = "inherit" THEN ctx.marginBottom := ctx.parent.marginBottom
				ELSIF ident^ = "initial" THEN ctx.marginBottom := 0
				ELSE RETURN
				END
			ELSE RETURN
			END
		END;
		INCL(ctx.attrSet, Attr_MarginBottom)
	END SetMarginBottom;

	PROCEDURE SetMargin(decl: CSS.Declaration; ctx: Context);
	BEGIN (* simplified; works only if margin has only one value *)
		SetMarginLeft(decl, ctx); SetMarginTop(decl, ctx); SetMarginBottom(decl, ctx)
	END SetMargin;

	PROCEDURE SetTextIndent(decl: CSS.Declaration; ctx: Context);
		VAR term: CSS.Term; length: INTEGER; ident: String;
	BEGIN
		term := decl.GetTerms().GetNext()(CSS.Term);
		IF term.IsLength() THEN length := GetLength(term, ctx)
		ELSE ident := term.GetStringVal();
			IF ident # NIL THEN
				IF ident^ = "initial" THEN length := 0
				ELSIF ident^ = "inherit" THEN length := ctx.parent.indent
				ELSE RETURN
				END
			ELSE RETURN
			END
		END;
		ctx.indent := length
	END SetTextIndent;

	(* since the line height (asc, dsc) cannot be edited in BlackBox, we better ignore it.
	PROCEDURE SetLineHeight(decl: CSS.Declaration; ctx: Context);
		VAR term: CSS.Term; ident: String; scale: REAL; asc, dsc, w: INTEGER;
	BEGIN
		out.rider.attr.font.GetBounds(asc, dsc, w);
		term := decl.GetTerms().GetNext()(CSS.Term);
		CASE term.GetType() OF
		| CSS.IntNumber: scale := term.GetIntVal()
		| CSS.RealNumber, CSS.Percent: scale := term.GetRealVal()
		| CSS.IntDimension, CSS.RealDimension: scale := GetLength(term) / (asc + dsc)
		ELSE ident := term.GetStringVal();
			IF ident # NIL THEN
				IF ident^ = "normal" THEN scale := 1 (* TODO  use named constant *)
				ELSIF ident^ = "inherit" THEN (* TODO *) RETURN
				ELSIF ident^ = "initial" THEN scale := 1
				ELSE RETURN
				END
			ELSE RETURN
			END
		END;
		TextRulers.SetAsc(RulerCopy(), Round(asc * scale));
		TextRulers.SetDsc(ruler, Round(dsc * scale));
	END SetLineHeight;
	*)

	PROCEDURE SetWhiteSpace(decl: CSS.Declaration; ctx: Context);
		VAR term: CSS.Term; ident: String;
	BEGIN
		term := decl.GetTerms().GetNext()(CSS.Term);
		ident := term.GetStringVal();
		IF ident # NIL THEN
			IF (ident^ = "pre") OR (ident^ = "pre-wrap") THEN ctx.pre := TRUE
			ELSIF ident^ = "inherit" THEN ctx.pre := ctx.parent.pre
			ELSIF ident^ = "initial" THEN ctx.pre := FALSE
			END
		END
	END SetWhiteSpace;

	PROCEDURE SetTabSize(decl: CSS.Declaration; ctx: Context);
		VAR term: CSS.Term; ident: String;
	BEGIN
		term := decl.GetTerms().GetNext()(CSS.Term);
		CASE term.GetType() OF
		| CSS.IntNumber: ctx.tabSize := SHORT(term.GetIntVal())
		| CSS.Ident: ident := term.GetStringVal();
			IF ident^ = "inherit" THEN ctx.tabSize := ctx.parent.tabSize
			ELSIF ident^ = "initial" THEN ctx.tabSize := TabSizeInitial
			END
		ELSE
		END 
	END SetTabSize;

	PROCEDURE SetListStyleType(decl: CSS.Declaration; ctx: Context);
		VAR term: CSS.Term; ident: String;
	BEGIN
		term := decl.GetTerms().GetNext()(CSS.Term);
		ident := term.GetStringVal();
		IF ident # NIL THEN
			IF ident^ = "disc" THEN ctx.listStyleType := ListStyleType_Disc
			ELSIF ident^ = "circle" THEN ctx.listStyleType := ListStyleType_Circle
			ELSIF ident^ = "square" THEN ctx.listStyleType := ListStyleType_Square
			ELSIF ident^ = "none" THEN ctx.listStyleType := ListStyleType_None
			ELSIF ident^ = "decimal" THEN ctx.listStyleType := ListStyleType_Decimal
			ELSIF ident^ = "upper-alpha" THEN ctx.listStyleType := ListStyleType_UpperAlpha
			ELSIF ident^ = "lower-alpha" THEN ctx.listStyleType := ListStyleType_LowerAlpha
			ELSIF ident^ = "upper-roman" THEN ctx.listStyleType := ListStyleType_UpperRoman
			ELSIF ident^ = "lower-roman" THEN ctx.listStyleType := ListStyleType_LowerRoman
			ELSIF ident^ = "inherit" THEN ctx.listStyleType := ctx.parent.listStyleType
			ELSIF ident^ = "initial" THEN ctx.listStyleType := ListStyleType_Initial
			ELSE RETURN
			END;
			INCL(ctx.attrSet, Attr_Type);
		END 
	END SetListStyleType;

	(* there is no formatting like this in BlackBox but we can at least insert some white space *)
	PROCEDURE SetFloat(decl: CSS.Declaration; ctx: Context);
		VAR term: CSS.Term; ident: String;
	BEGIN
		term := decl.GetTerms().GetNext()(CSS.Term);
		ident := term.GetStringVal();
		IF ident # NIL THEN
			IF ident^ # "left" THEN WriteChar(" ", ctx) (* TODO this is unsystematic *)
			END
		END
	END SetFloat;

	PROCEDURE SetVerticalAlign(decl: CSS.Declaration; ctx: Context);
		VAR term: CSS.Term; ident: String;
	BEGIN
		term := decl.GetTerms().GetNext()(CSS.Term);
		IF term.IsLength() THEN INC(ctx.offset, GetLength(term, ctx))
		ELSIF term.GetType() = CSS.Percent THEN (* % of line-height; we use font-size instead *)
			INC(ctx.offset, Round(term.GetRealVal() * ctx.size))
		ELSE
			ident := term.GetStringVal();
			IF ident # NIL THEN
				IF ident^ = "baseline" THEN (* unchanged *)
				ELSIF ident^ = "sub" THEN DEC(ctx.offset, Round(OffsetEm * ctx.size))
				ELSIF ident^ = "super" THEN INC(ctx.offset, Round(OffsetEm * ctx.size))
				ELSIF ident^ = "inherit" THEN ctx.offset := ctx.parent.offset - ctx.parent.parent.offset
				ELSIF ident^ = "initial" THEN 
				ELSE RETURN
				END
			ELSE RETURN
			END
		END;
		INCL(ctx.attrSet, Attr_VerticalAlign)
	END SetVerticalAlign;

	PROCEDURE SetDisplay(decl: CSS.Declaration; ctx: Context);
		VAR term: CSS.Term; ident: String;
	BEGIN
		term := decl.GetTerms().GetNext()(CSS.Term);
		ident := term.GetStringVal();
		IF ident # NIL THEN
			IF ident^ = "inline" THEN ctx.display := Display_Inline
			ELSIF ident^ = "block" THEN ctx.display := Display_Block
			ELSIF ident^ = "none" THEN ctx.display := Display_None
			ELSIF ident^ = "inherit" THEN ctx.display := ctx.parent.display
			ELSIF ident^ = "initial" THEN ctx.display := Display_Initial
			ELSE RETURN
			END
		ELSE RETURN
		END;
		INCL(ctx.attrSet, Attr_Display)
	END SetDisplay;

	PROCEDURE SetTextDecoration(decl: CSS.Declaration; ctx: Context);
		VAR term: CSS.Term; ident: String; style: SET;
	BEGIN
		term := decl.GetTerms().GetNext()(CSS.Term); 
		ident := term.GetStringVal(); style := ctx.style;
		IF ident # NIL THEN
			IF ident^ = "underline" THEN INCL(style, Fonts.underline)
			ELSIF ident^ = "line-through" THEN INCL(style, Fonts.strikeout)
			ELSIF ident^ = "none" THEN style := {}
			ELSIF ident^ = "inherit" THEN style := ctx.parent.style
			ELSIF ident^ = "initial" THEN style := StyleInitial
			ELSE RETURN
			END;
			ctx.style := style;
			INCL(ctx.attrSet, Attr_FontStyle);
		END
	END SetTextDecoration;
	
	(* color name mapping could also be added to the CSS parser but since it may also be needed in HTML
		attributes, we put it into the HTML importer where it serves both. *)
	PROCEDURE MapColorName(IN ident: ARRAY OF CHAR): INTEGER;
		VAR f: Files.File; pos, len, color, res: INTEGER;
			line, key, val: ARRAY 64 OF CHAR; red, green, blue: ARRAY 3 OF CHAR;
			
			PROCEDURE ReadLine(rd: Files.Reader; OUT line: ARRAY OF CHAR);
				VAR b: BYTE; i: INTEGER;
			BEGIN
				REPEAT rd.ReadByte(b) UNTIL (b >= ORD(" ")) OR rd.eof;
				line[0] := CHR(b); i := 1;
				REPEAT rd.ReadByte(b); line[i] := CHR(b); INC(i) UNTIL (b < ORD(" ")) OR rd.eof;
				line[i - 1] := 0X
			END ReadLine;
			
	BEGIN
		IF colorMap = NIL THEN 
			f := Files.dir.Old(Files.dir.This("W3c/Rsrc"), "CSSColorMap.txt", TRUE);
			IF f # NIL THEN colorMap := f.NewReader(NIL) END
		END;
		IF colorMap # NIL THEN
			colorMap.SetPos(0); Strings.ToLower(ident + ":#", key);
			ReadLine(colorMap, line);
			WHILE ~colorMap.eof DO (* the file is actually sorted by key, i.e. binary search would also work *)
				Strings.Find(line, key, 0, pos);
				IF pos = 0 THEN len := LEN(key$);
					Strings.Extract(line, len, 2, red);
					Strings.Extract(line, len + 2, 2, green);
					Strings.Extract(line, len + 4, 2, blue);
					val := "0" + blue + green + red + "H"; Strings.ToUpper(val, val);
					Strings.StringToInt(val, color, res);
					IF res = 0 THEN
						IF color = 0FFFFFFH THEN color := Ports.grey75; (* make white visible *) END;
						RETURN color 
					END
				END;
				ReadLine(colorMap, line);
			END
		END;
		RETURN -1
	END MapColorName;

	PROCEDURE SetColorTerm(term: CSS.Term; ctx: Context);
		VAR ident: String; color: INTEGER; red, green, blue, alpha: SHORTINT;
	BEGIN
		IF term.GetType() IN {CSS.Function, CSS.IntNumber, CSS.Color} THEN
			term.GetColor(red, green, blue, alpha);
			color := red + ASH(green, 8) + ASH(blue, 16)
		ELSE ident := term.GetStringVal();
			color := MapColorName(ident);
			IF color = -1 THEN
				IF ident^ = "inherit" THEN color := ctx.parent.color
				ELSIF ident^ = "initial" THEN color := ColorInitial
				ELSE RETURN
				END
			END
		END;
		ctx.color := color;
		INCL(ctx.attrSet, Attr_Color);
	END SetColorTerm;

	PROCEDURE SetColor(decl: CSS.Declaration; ctx: Context);
	BEGIN
		SetColorTerm(decl.GetTerms().GetNext()(CSS.Term), ctx)
	END SetColor;

	PROCEDURE Smaller(ctx: Context): INTEGER;
		VAR em: INTEGER;
	BEGIN
		em := ctx.size;
		IF em <= 11 * Fonts.point THEN RETURN em - Fonts.point
		ELSIF em <= 15 * Fonts.point THEN RETURN em - 2 * Fonts.point
		ELSE RETURN em - 4 * Fonts.point 
		END
	END Smaller;

	PROCEDURE Larger(ctx: Context): INTEGER;
		VAR em: INTEGER;
	BEGIN
		em := ctx.size;
		IF em <= 9 * Fonts.point THEN RETURN em + Fonts.point 
		ELSIF em <= 11 * Fonts.point THEN RETURN em + 2 * Fonts.point 
		ELSE RETURN em + 4 * Fonts.point 
		END
	END Larger;

	PROCEDURE SetFontSize(decl: CSS.Declaration; ctx: Context);
		VAR term: CSS.Term; ident: String;
	BEGIN
		term := decl.GetTerms().GetNext()(CSS.Term); 
		IF term.IsLength() THEN
			ctx.size := GetLength(term, ctx)
		ELSE
			ident := term.GetStringVal();
			IF ident # NIL THEN
				IF ident^ = "xx-small" THEN ctx.size := 8 * Fonts.point
				ELSIF ident^ = "x-small" THEN ctx.size := 9 * Fonts.point
				ELSIF ident^ = "small" THEN ctx.size := 10 * Fonts.point
				ELSIF ident^ = "medium" THEN ctx.size := 12 * Fonts.point
				ELSIF ident^ = "large" THEN ctx.size := 16 * Fonts.point
				ELSIF ident^ = "x-large" THEN ctx.size := 20 * Fonts.point
				ELSIF ident^ = "xx-large" THEN ctx.size := 24 * Fonts.point
				ELSIF ident^ = "smaller" THEN ctx.size := Smaller(ctx)
				ELSIF ident^ = "larger" THEN ctx.size := Larger(ctx)
				ELSIF ident^ = "inherit" THEN (* TODO use e *)
				ELSIF ident^ = "initial" THEN ctx.size := FontSizeInitial
				ELSE RETURN
				END
			ELSE RETURN
			END
		END;
		INCL(ctx.attrSet, Attr_FontSize);
	END SetFontSize;

	PROCEDURE SetFontWeight(decl: CSS.Declaration; ctx: Context);
		VAR term: CSS.Term; ident: String; weight: INTEGER;
	BEGIN
		term := decl.GetTerms().GetNext()(CSS.Term); 
		IF term.GetType() = CSS.IntNumber THEN
			weight := term.GetIntVal()
		ELSE ident := term.GetStringVal();
			IF ident # NIL THEN
				IF ident^ = "normal" THEN weight := Fonts.normal
				ELSIF ident^ = "bold" THEN weight := Fonts.bold
				ELSIF ident^ = "bolder" THEN weight := MIN(900, ctx.weight + 100)
				ELSIF ident^ = "lighter" THEN weight := MIN(100, ctx.weight - 100)
				ELSIF ident^ = "inherit" THEN weight := ctx.parent.weight
				ELSIF ident^ = "initial" THEN weight := WeightInitial
				ELSE RETURN
				END
			ELSE RETURN
			END
		END;
		ctx.weight := weight;
		INCL(ctx.attrSet, Attr_FontWeight)
	END SetFontWeight;
	
	PROCEDURE SetAll(decl: CSS.Declaration; ctx: Context);
		VAR term: CSS.Term; ident: String;
	BEGIN
		term := decl.GetTerms().GetNext()(CSS.Term);
		ident := term.GetStringVal();
		IF ident # NIL THEN
			IF ident^ = "initial" THEN SetInitial(ctx)
			ELSIF ident^ = "inherit" THEN (* TODO *)
			ELSIF ident^ = "unset" THEN (* TODO *)
			END
		END
	END SetAll;
	
	

	PROCEDURE GetCSSParser(attrVal: String): CSSParsers.Parser;
	BEGIN
		IF cssParser = NIL THEN
			cssParser := CSSParsers.NewParser(Streams.NewStringReader(attrVal, 0), NIL, NIL);
			cssParser.SetStringPooling(CSSParsers.DefaultStringPooling)
		ELSE
			cssParser.Reset(Streams.NewStringReader(attrVal, 0));
		END;
		(* error positions will be relative to the inline style attribute, but as long as errors are not
		displayed, it doesn't matter *)
		RETURN cssParser
	END GetCSSParser;
	
	(* note: the CSS  declaration 'font-size' defines the relative length 'em' based on its parent element.
		Other declarations that use em refer to the one set with font-size, independent of the declaration order.
		If font-size is not defined explicitly, it is inherited from the parent element.
	*)
	PROCEDURE ProcessStyleAttr (attrVal: String; ctx: Context);
		VAR decls: Objects.Enumerator; decl: CSS.Declaration; prop: String;
			
	BEGIN
		inlineStyle := GetCSSParser(attrVal).ParseInlineStyle(); (* save for later processing of properties that 
																							may depend on em *)
		
		INCL(ctx.attrSet, Attr_Style);
		decls := inlineStyle.GetDeclarations();
		WHILE decls.HasMoreElements() DO
			decl := decls.GetNext()(CSS.Declaration);
			prop := decl.GetProperty();
			IF prop^ = "font-size" THEN SetFontSize(decl, ctx)
			ELSIF prop^ = "all" THEN SetAll(decl, ctx)
			END
		END;
	END ProcessStyleAttr;

	PROCEDURE ProcessColorAttr (attrVal: String; ctx: Context);
		VAR term: CSS.Term;
	BEGIN
		term := GetCSSParser(attrVal).ParseExpr();
		
		SetColorTerm(term, ctx)
	END ProcessColorAttr;

	PROCEDURE ProcessSizeAttr (attrVal: String; ctx: Context);
		VAR size, res: INTEGER;
	BEGIN
		IF (attrVal = NIL) OR (attrVal^ = "") THEN (*default 3*)
			ctx.size := 12 * Fonts.point
		ELSE
			Strings.StringToInt(attrVal, size, res);
			IF res = 0 THEN
				CASE size OF
				| 1: ctx.size := 8 * Fonts.point
				| 2: ctx.size := 10 * Fonts.point
				| 3: ctx.size := 12 * Fonts.point
				| 4: ctx.size := 14 * Fonts.point
				| 5: ctx.size := 18 * Fonts.point
				| 6: ctx.size := 24 * Fonts.point
				| 7: ctx.size := 36 * Fonts.point
				ELSE RETURN
				END;
			END
		END;
		INCL(ctx.attrSet, Attr_FontSize)
	END ProcessSizeAttr;

	PROCEDURE ProcessFaceAttr (attrVal: String; ctx: Context);
		VAR decl: CSS.Declaration;
	BEGIN
		NEW(decl); decl.Init; GetCSSParser(attrVal).ParseExprList(decl);
		SetFontFamily(decl, ctx)
	END ProcessFaceAttr;

	PROCEDURE ProcessStartAttr (attrVal: String; ctx: Context);
		VAR start, res: INTEGER;
	BEGIN
		Strings.StringToInt(attrVal, start, res);
		IF res = 0 THEN listNum := start; INCL(ctx.attrSet, Attr_Start) END
	END ProcessStartAttr;

	PROCEDURE ProcessTypeAttr (attrVal: String; ctx: Context);
		VAR listStyleType: BYTE;
	BEGIN
		IF attrVal^ = "I" THEN listStyleType := ListStyleType_UpperRoman
		ELSIF attrVal^ = "i" THEN listStyleType := ListStyleType_LowerRoman
		ELSIF attrVal^ = "A" THEN listStyleType := ListStyleType_UpperAlpha
		ELSIF attrVal^ = "a" THEN listStyleType := ListStyleType_LowerAlpha
		ELSIF attrVal^ = "disc" THEN listStyleType := ListStyleType_Disc
		ELSIF attrVal^ = "circle" THEN listStyleType := ListStyleType_Circle
		ELSIF attrVal^ = "square" THEN listStyleType := ListStyleType_Square
		ELSIF attrVal^ = "none" THEN listStyleType := ListStyleType_None
		ELSE listStyleType := ListStyleType_Decimal
		END;
		INCL(ctx.attrSet, Attr_Type);
		ctx.listStyleType := listStyleType
	END ProcessTypeAttr;

	(* em is already defined *)
	PROCEDURE ProcessStyle (ctx: Context);
		VAR decls: Objects.Enumerator; decl: CSS.Declaration; prop: String;
	BEGIN
		IF Attr_Style IN ctx.attrSet THEN
			decls := inlineStyle.GetDeclarations();
			WHILE decls.HasMoreElements() DO
				decl := decls.GetNext()(CSS.Declaration);
				prop := decl.GetProperty();
				IF prop^ = "color" THEN SetColor(decl, ctx)
				ELSIF prop^ = "font-weight" THEN SetFontWeight(decl, ctx)
				ELSIF (prop^ = "text-decoration") OR (prop^= "text-decoration-line") THEN SetTextDecoration(decl, ctx)
				ELSIF prop^ = "font-family" THEN SetFontFamily(decl, ctx)
				ELSIF (prop^ = "text-align") OR (prop^ = "align") THEN SetTextAlign(decl, ctx)
				ELSIF prop^ = "margin-left" THEN SetMarginLeft(decl, ctx)
				ELSIF prop^ = "margin-top" THEN SetMarginTop(decl, ctx)
				ELSIF prop^ = "margin-bottom" THEN SetMarginBottom(decl, ctx)
				ELSIF prop^ = "margin" THEN SetMargin(decl, ctx)
				ELSIF prop^ = "text-indent" THEN SetTextIndent(decl, ctx)
				(*ELSIF prop^ = "line-height" THEN SetLineHeight(decl, ctx)*)
				ELSIF prop^ = "white-space" THEN SetWhiteSpace(decl, ctx)
				ELSIF prop^ = "tab-size" THEN SetTabSize(decl, ctx)
				ELSIF (prop^ = "list-style-type") OR (prop^ = "list-style") THEN SetListStyleType(decl, ctx)
				ELSIF prop^ = "float" THEN SetFloat(decl, ctx)
				ELSIF prop^ = "vertical-align" THEN SetVerticalAlign(decl, ctx)
				ELSIF prop^ = "display" THEN SetDisplay(decl, ctx)
				END
			END
		END
	END ProcessStyle;

	(* We process html attributes first and, if present, inline style properties second; style dominates.
		Note: the CSS  style property 'font-size' defines the relative length 'em' based on its parent element.
		Other declarations that use em refer to the one set with font-size, independent of the declaration order.
		If font-size is not defined explicitly, it is inherited from the parent element or set by e.g. H1-H6.
	*)
	PROCEDURE ProcessAttributes (ctx: Context);
		VAR e: DOM.Element; a: DOM.Attribute; attrName, attrVal, styleVal: String;
	BEGIN
		e := ctx.e; a := e.GetFirstAttribute(); styleVal := NIL;
		WHILE a # NIL DO
			attrName := a.GetName(); attrVal := a.GetValue();
			IF (attrName^ = "style") THEN styleVal := attrVal
			ELSIF attrName^ = "color" THEN ProcessColorAttr(attrVal, ctx) (* not in HTML5 *)
			ELSIF attrName^ = "size" THEN ProcessSizeAttr(attrVal, ctx) (* not in HTML5 *)
			ELSIF attrName^ = "face" THEN ProcessFaceAttr(attrVal, ctx) (* not in HTML5 *)
			ELSIF attrName^ = "start" THEN ProcessStartAttr(attrVal, ctx)
			ELSIF attrName^ = "type" THEN ProcessTypeAttr(attrVal, ctx)
			END;
			a := e.GetNextAttribute(a)
		END;
		IF styleVal # NIL THEN ProcessStyleAttr(styleVal, ctx);  ProcessStyle(ctx) END
	END ProcessAttributes;

	PROCEDURE SetDefaultDisplay(display: BYTE; ctx: Context);
	BEGIN
		IF ~(Attr_Display IN ctx.attrSet) THEN ctx.display := display END
	END SetDefaultDisplay;

	PROCEDURE SetDefaultWeight(weight: INTEGER; ctx: Context);
	BEGIN
		IF ~(Attr_FontWeight IN ctx.attrSet) THEN ctx.weight := weight END
	END SetDefaultWeight;

	PROCEDURE SetDefaultSize(size: INTEGER; ctx: Context);
	BEGIN
		IF ~(Attr_FontSize IN ctx.attrSet) THEN ctx.size := size END
	END SetDefaultSize;

	PROCEDURE SetDefaultStyle(style: INTEGER; ctx: Context);
	BEGIN
		IF ~(Attr_FontStyle IN ctx.attrSet) THEN ctx.style := {style} END
	END SetDefaultStyle;

	PROCEDURE SetDefaultColor(color: INTEGER; ctx: Context);
	BEGIN
		IF ~(Attr_Color IN ctx.attrSet) THEN ctx.color := color END
	END SetDefaultColor;

	PROCEDURE SetDefaultFontFamily(IN fontFamily: ARRAY OF CHAR; ctx: Context);
	BEGIN
		IF ~(Attr_FontFamily IN ctx.attrSet) THEN ctx.typeface := fontFamily$ END
	END SetDefaultFontFamily;

	PROCEDURE SetDefaultMarginLeft(marginLeft: INTEGER; ctx: Context);
	BEGIN
		IF ~(Attr_MarginLeft IN ctx.attrSet) THEN INC(ctx.left, marginLeft) END;
	END SetDefaultMarginLeft;

	PROCEDURE SetDefaultMargin(margin: INTEGER; ctx: Context);
	BEGIN
		IF ~(Attr_MarginTop IN ctx.attrSet) THEN ctx.marginTop := margin END;
		IF ~(Attr_MarginBottom IN ctx.attrSet) THEN ctx.marginBottom := margin END
	END SetDefaultMargin;

	PROCEDURE SetDefaultSmaller(ctx: Context);
	BEGIN
		IF ~(Attr_FontSize IN ctx.attrSet) THEN ctx.size := Smaller(ctx) END
	END SetDefaultSmaller;

	PROCEDURE SetDefaultListStyleType(listStyleType: BYTE; ctx: Context);
	BEGIN
		IF ~(Attr_Type IN ctx.attrSet) THEN ctx.listStyleType := listStyleType END;
	END SetDefaultListStyleType;
		
	PROCEDURE^ WriteElement (ctx: Context);

	PROCEDURE WriteContents (ctx: Context);
		VAR n: DOM.Content;
	BEGIN
		n := ctx.e.GetFirst();
		WHILE n # NIL DO
			WITH n: DOM.Element DO
				WriteElement(NewContext(ctx, n))
			| n: DOM.Comment DO
				(* ignore; do not delete because DOM.Comment is a subclass of DOM.Chars *)
			| n: DOM.Chars DO
				WriteText(n.GetStr(), ctx); paraAttr := out.rider.attr
			ELSE (* skip *)
			END;
			n := ctx.e.GetNext(n)
		END
	END WriteContents;
		
	PROCEDURE WriteBlock(ctx: Context);
	BEGIN
		SetDefaultDisplay(Display_Block, ctx);
		IF ctx.display # Display_None THEN
			WriteParaTop(ctx);
			WriteContents(ctx);
			WriteParaBottom(ctx)
		END
	END WriteBlock;
		
	PROCEDURE WriteInline(ctx: Context);
	BEGIN
		(* Display_Inline is already set as default *)
		IF ctx.display # Display_None THEN WriteParaTop(ctx); WriteContents(ctx); WriteParaBottom(ctx) END
	END WriteInline;

	PROCEDURE WriteH (sizeEm, marginEm: REAL; ctx: Context);
	BEGIN
		SetDefaultWeight(Fonts.bold, ctx);
		SetDefaultSize(Round(sizeEm * ctx.size), ctx);
		SetDefaultMargin(Round(marginEm * ctx.size), ctx);
		WriteBlock(ctx)
	END WriteH;

	PROCEDURE WriteA (ctx: Context);
		VAR e: DOM.Element;href, name, id: String;
	BEGIN
		e := ctx.e;
		(* 1. write left link *)
		href := e.GetAttributeValue("href");
		name := e.GetAttributeValue("name");
		id := e.GetAttributeValue("id");
		(* href and name/id may both exist; the link views must be properly nested inside the target views *)
		IF name # NIL THEN
			WriteHiddenView(StdLinks.dir.NewTarget(name), ctx);
		ELSIF id # NIL THEN
			WriteHiddenView(StdLinks.dir.NewTarget(id), ctx);
		END;
		IF href # NIL THEN
			IF href[0] # "#" THEN
				WriteView(StdLinks.dir.NewLink("Dialog.OpenExternal('" + href + "')"), ctx);
			ELSE
				NEW(id, LEN(href) - 1);
				Strings.Extract(href, 1, LEN(href$) - 1, id);
				WriteView(StdLinks.dir.NewLink("StdLinks.ShowTarget('" + id + "')"), ctx);
			END;
			SetDefaultColor(Ports.blue, ctx);
			SetDefaultStyle(Fonts.underline, ctx)
		END;
		(* 2. write contents *)
		WriteInline(ctx);
		(* 3. write right link *)
		IF href # NIL THEN WriteView(StdLinks.dir.NewLink(""), ctx) END;
		IF (name # NIL) OR (id # NIL) THEN WriteHiddenView(StdLinks.dir.NewTarget(""), ctx) END
	END WriteA;

	PROCEDURE WriteWBR;
	BEGIN
		IF state = Text THEN out.WriteChar(SOFTHYPHEN) END
	END WriteWBR;

	PROCEDURE WriteLI (ctx: Context);
		VAR ruler: TextRulers.Ruler; numStr: ARRAY 20 OF CHAR;
	BEGIN 
		INC(ctx.left, 10 * Fonts.mm);
		IF ctx.listStyleType <= ListStyleType_None THEN (* for UL *)
			ruler := NewRuler(0, ctx.left , -ctx.size, {TextRulers.leftAdjust});
			TextRulers.AddTab(ruler, ctx.left);
		ELSE (* for OL *)
			ruler := NewRuler(0, ctx.left , -ctx.left, {TextRulers.leftAdjust});
			TextRulers.AddTab(ruler, ctx.left - ctx.size DIV 3);
			TextRulers.MakeRightTab(ruler);
			TextRulers.AddTab(ruler, ctx.left);
			SetDefaultListStyleType(ListStyleType_Decimal, ctx);
		END;
		WriteRuler(ruler, Round(0.3 * ctx.size), Text, ctx);
		SetCtxAttr(ctx);
		CASE ctx.listStyleType OF
		| ListStyleType_Disc: WriteChar(2022X, ctx)
		| ListStyleType_Circle: WriteChar(25E6X, ctx)
		| ListStyleType_Square: WriteChar(25AAX, ctx)
		| ListStyleType_None: (* skip *)
		ELSE (* for <OL> *)
			CASE ctx.listStyleType OF
			| ListStyleType_UpperRoman, ListStyleType_LowerRoman:
				Strings.IntToStringForm(listNum, Strings.roman, 0, 0X, FALSE, numStr);
				IF ctx.listStyleType = ListStyleType_LowerRoman THEN Strings.ToLower(numStr, numStr) END;
			| ListStyleType_UpperAlpha:
				numStr[0] := CHR(ORD("A") - 1 + listNum); numStr[1] := 0X;
			| ListStyleType_LowerAlpha:
				numStr[0] := CHR(ORD("a") - 1 + listNum); numStr[1] := 0X;
			ELSE (* ListStyleType_Decimal*)
				Strings.IntToString(listNum, numStr);
			END;
			WriteTab(ctx); WriteText(numStr, ctx); WriteChar(".", ctx);
			INC(listNum)
		END;
		paraAttr := out.rider.attr;
		WriteTab(ctx); WriteContents(ctx); 
		WritePara(ctx.marginBottom)
	END WriteLI;
	
	PROCEDURE WriteUL (ctx: Context);
	BEGIN
		SetDefaultListStyleType(ListStyleType_Disc, ctx); WriteBlock(ctx)
		(* TODO maybe also support property 'padding-left', which is currently hard-coded in WriteLI *)
	END WriteUL;
	
	PROCEDURE WriteOL (ctx: Context);
		VAR savedListNum: INTEGER;
	BEGIN
		SetDefaultListStyleType(ListStyleType_Decimal, ctx);
		savedListNum := listNum;
		IF ~(Attr_Start IN ctx.attrSet) THEN listNum := 1 END;
		WriteBlock(ctx); listNum := savedListNum
	END WriteOL;

	PROCEDURE WriteHR (ctx: Context);
		VAR ruler: TextRulers.Ruler;
	BEGIN
		SetCtxAttr(ctx);
		out.rider.SetAttr(TextModels.NewStyle(out.rider.attr, {Fonts.strikeout}));
		ruler := NewRuler(0, 0, 0, {TextRulers.leftAdjust});
		TextRulers.AddTab(ruler, 170 * Fonts.mm);
		WriteRuler(ruler, Round(0.5 * ctx.size), Para, ctx); out.WriteTab; paraAttr := out.rider.attr
	END WriteHR;
	
	PROCEDURE WriteTR (ctx: Context);
		VAR ruler: TextRulers.Ruler;
	BEGIN
		ruler := NewRuler(0, ctx.left , 0, {TextRulers.leftAdjust});
		(* any tab stops required may be set by the user in the document *)
		WriteRuler(ruler, ctx.marginTop, Text, ctx); paraAttr := out.rider.attr;
		WriteContents(ctx);
		WritePara(ctx.marginBottom)
	END WriteTR;

	PROCEDURE WritePRE (ctx: Context);
	BEGIN
		(* standard CSS is 'font-size: inherit' but browsers typically use 10pt default size *)
		SetDefaultSize(10 * Fonts.point, ctx);
		SetDefaultFontFamily(FontFamily_Monospace, ctx);
		SetDefaultMargin(ctx.size, ctx);
		SetDefaultDisplay(Display_Block, ctx);
		ctx.pre := TRUE; nofEmptyLines := -1; (* skip empty first Ln in PRE *)
		WriteParaTop(ctx);
		WriteContents(ctx);
		IF ~ctx.parent.pre THEN nofEmptyLines := 0 END;
		WriteParaBottom(ctx)
	END WritePRE;

	PROCEDURE WriteSU (alignEm: REAL; ctx: Context);
	BEGIN
		IF ~(Attr_VerticalAlign IN ctx.attrSet) THEN INC(ctx.offset, Round(alignEm * ctx.size)) END;
		SetDefaultSmaller(ctx); WriteInline(ctx)
	END WriteSU;

	PROCEDURE WriteElement (ctx: Context);
		VAR (*savedAttr: TextModels.Attributes;*) tag: String;
	BEGIN
		(*savedAttr := out.rider.attr;*)
		ProcessAttributes(ctx);
		IF ctx.display = Display_None THEN RETURN END;
		tag := ctx.e.GetName();
		IF tag^  = "A" THEN WriteA(ctx)
		ELSIF tag^ = "BR" THEN WriteBR(ctx)
		ELSIF tag^ = "WBR" THEN WriteWBR
		ELSIF tag^  = "H1" THEN WriteH(2, 0.67, ctx)
		ELSIF tag^  = "H2" THEN WriteH(1.5, 0.83, ctx)
		ELSIF tag^  = "H3" THEN WriteH(1.17, 1, ctx)
		ELSIF tag^  = "H4" THEN WriteH(1, 1.33, ctx)
		ELSIF tag^  = "H5" THEN WriteH(0.83, 1.67, ctx)
		ELSIF tag^  = "H6" THEN WriteH(0.67, 2.33, ctx)
		ELSIF (tag^  = "B") OR (tag^= "STRONG") THEN SetDefaultWeight(Fonts.bold, ctx); WriteInline(ctx)
		ELSIF (tag^  = "I") OR (tag^ = "EM") OR (tag^ = "VAR") THEN SetDefaultStyle(Fonts.italic, ctx); WriteInline(ctx)
		ELSIF tag^  = "U" THEN SetDefaultStyle(Fonts.underline, ctx); WriteInline(ctx)
		ELSIF (tag^  = "DEL") OR (tag^ = "STRIKE") THEN SetDefaultStyle(Fonts.strikeout, ctx); WriteInline(ctx)
		ELSIF (tag^  = "DL") OR (tag^  = "P")  THEN SetDefaultMargin(ctx.size, ctx); WriteBlock(ctx)
		ELSIF tag^ = "DD" THEN SetDefaultMarginLeft(10 * Fonts.mm, ctx); WriteBlock(ctx)
		ELSIF tag^ = "CENTER" THEN ctx.opts := {}; WriteBlock(ctx)
		ELSIF tag^ = "PRE" THEN WritePRE(ctx)
		ELSIF tag^ = "LI" THEN WriteLI(ctx)
		ELSIF tag^ = "UL" THEN WriteUL(ctx)
		ELSIF tag^ = "OL" THEN WriteOL(ctx)
		ELSIF tag^ = "TR" THEN WriteTR(ctx)
		ELSIF tag^ = "TH" THEN SetDefaultWeight(Fonts.bold, ctx); SetCtxAttr(ctx); WriteTab(ctx); WriteInline(ctx)
		ELSIF tag^ = "TD" THEN SetCtxAttr(ctx); WriteTab(ctx); WriteInline(ctx)
		ELSIF tag^ = "SMALL" THEN SetDefaultSmaller(ctx); WriteInline(ctx)
		ELSIF tag^ = "HR" THEN WriteHR(ctx)
		ELSIF tag^ = "SUB" THEN WriteSU(-OffsetEm, ctx)
		ELSIF tag^ = "SUP" THEN WriteSU(OffsetEm, ctx)
		ELSIF tag^ = "BLOCKQUOTE" THEN
			SetDefaultMarginLeft(10 * Fonts.mm, ctx); SetDefaultMargin(ctx.size, ctx); WriteBlock(ctx)
		ELSIF (tag^ = "CODE") OR (tag^ = "TT") OR (tag^ = "SAMP") OR (tag^ = "KBD") THEN
			(* standard CSS is 'font-size: inherit' but browsers typically use 10pt default size *)
			SetDefaultSize(10 * Fonts.point, ctx); SetDefaultFontFamily(FontFamily_Monospace, ctx); WriteInline(ctx)
		ELSIF (tag^  = "DIV") OR (tag^ = "DT") OR (tag^ = "TABLE") OR (tag^ = "SECTION") OR (tag^ = "DETAILS") 
			OR (tag^ = "FIGCAPTION")OR (tag^ = "HEADER") OR (tag^ = "FOOTER") OR (tag^ = "NAV") 
			OR (tag^ = "SUMMARY") OR (tag^ = "ASIDE") THEN WriteBlock(ctx)
		ELSIF (tag^  = "HEAD") OR (tag^  = "SCRIPT") OR (tag^  = "STYLE") THEN
			(* skip; also skips <BASEFONT>, but this is not HTML5 anyway * *)
		ELSE WriteInline(ctx)
		END;
		(*out.rider.SetAttr(savedAttr)*)
	END WriteElement;

	

	(* Note: There are almost no LFs in the clipboard, i.e. we would get very long lines, which are very slow in BlackBox.
		Therefore we put every tag on a separate line.
		The text position is not the same as that reported in an error message.
		For debugging, the unmodified contents can be seen with StoreNative.
	*)
	PROCEDURE ImportNative (f: Files.File; OUT s: Stores.Store);
		VAR text: TextModels.Model; utf8Rd: Streams.Utf8FileReader;
			wr: TextModels.Writer; ch: CHAR; outputCR: BOOLEAN;
	BEGIN
		ASSERT(f # NIL, 20);
		
		NEW(utf8Rd); utf8Rd.Init(f.NewReader(NIL));
		text := TextModels.dir.New();
		wr := text.NewWriter(NIL);
		ch := utf8Rd.Get(); outputCR := FALSE;
		WHILE (ch # 0X) & utf8Rd.ok DO
			IF (ch = "<") & outputCR THEN wr.WriteChar(CR); wr.WriteChar("<")
			ELSIF ch = ">" THEN wr.WriteChar(">"); wr.WriteChar(CR); outputCR := FALSE
			ELSIF ch >= " " THEN wr.WriteChar(ch); outputCR := TRUE
			ELSIF ((ch = CR) OR (ch = LF)) & outputCR THEN wr.WriteChar(CR); outputCR := FALSE
			ELSIF ch = TAB THEN wr.WriteChar(TAB)
			END;
			ch := utf8Rd.Get()
		END;
		s := TextViews.dir.New(text);
	END ImportNative;

	PROCEDURE ImportHtml* (f: Files.File; OUT s: Stores.Store);
		VAR text: TextModels.Model; utf8Rd: Streams.Utf8FileReader;
			htmlParser: HTMLParsers.Parser; dom: DOM.Document; iniCtx: Context;
			
	BEGIN
		ASSERT(f # NIL, 20);
		NEW(utf8Rd); utf8Rd.Init(f.NewReader(NIL));
		htmlParser := HTMLParsers.NewParser(utf8Rd, NIL);
		htmlParser.SetStringPooling(HTMLParsers.DefaultStringPooling);
		dom := htmlParser.Parse();
		IF dom # NIL THEN
			text := TextModels.dir.New();
			out.ConnectTo(text);
			state := Para; listNum := 1; maxVerticalSpace := 0; nofEmptyLines := 0;
			paraAttr := TextModels.dir.attr;
			iniCtx := NewInitialContext(dom.GetRoot());
			WriteElement(iniCtx);
			out.ConnectTo(NIL); inlineStyle := NIL; cssParser := NIL; colorMap := NIL; dstr := NIL; paraAttr := NIL;
			
			s := TextViews.dir.New(text);
		ELSE s := NIL
		END;
	END ImportHtml;
	
	PROCEDURE MediumGlobal (VAR sm: WinOle.STGMEDIUM): WinApi.HGLOBAL;
	BEGIN
		ASSERT(sm.tymed = WinOle.TYMED_HGLOBAL, 20);
		RETURN sm.u.hGlobal
	END MediumGlobal;

	PROCEDURE ImportDHtml* (VAR med: WinOle.STGMEDIUM; OUT v: Views.View;
											OUT w, h: INTEGER; OUT isSingle: BOOLEAN);
		VAR res, adr: INTEGER; ch: BYTE;
			hnd: WinApi.HANDLE; pref: Properties.BoundsPref;
			f: Files.File; wr: Files.Writer; s: Stores.Store; lineno: INTEGER;
	BEGIN
		hnd := MediumGlobal(med);
		ASSERT(hnd # 0, 20);
		adr := WinApi.GlobalLock(hnd);
		f := Files.dir.Temp();
		wr := f.NewWriter(NIL);
		SYSTEM.GET(adr, ch);
		lineno := 0;
		WHILE ch # 0 DO
			IF lineno >= 6 THEN wr.WriteByte(ch) END;
			IF ch = ORD(LF) THEN INC(lineno) END;
			INC(adr); SYSTEM.GET(adr, ch)
		END;
		res := WinApi.GlobalUnlock(hnd);
		
		IF WinApi.GetKeyState(WinApi.VK_MENU) < 0 THEN (*  Alt key, no conversion  *) ImportNative(f, s)
		ELSE ImportHtml(f, s);
		END;
		v := s(Views.View);
		pref.w := Views.undefined; pref.h := Views.undefined;
		Views.HandlePropMsg(v, pref);
		w := pref.w; h := pref.h; isSingle := FALSE;
	END ImportDHtml;

	(* aux. procedure for creaing the HTML entity map
	PROCEDURE ConvertHTMLEntityMapFromJSONFile*;
		VAR t: TextModels.Model; s: TextMappers.Scanner; name: ARRAY 64 OF CHAR; val, res: INTEGER;
	BEGIN
		t := Views.OldView(Files.dir.This("W3c/Rsrc"), "HTMLEntityMap.odc").ThisModel()(TextModels.Model);
		s.ConnectTo(t);
		s.Scan();
		WHILE s.type = TextMappers.string DO
			IF s.string[LEN(s.string$) - 1] = ";" THEN
				Strings.Extract(s.string, 1, LEN(s.string$) - 2, name);
				s.Scan; (* ":" *);
				s.Scan; (* "{" *);
				s.Scan; (* "codepoints" *);
				s.Scan; (* ":" *);
				s.Scan; (* "[" *);
				s.Scan; (* decimal code *);
				ASSERT(s.type = TextMappers.int);
				Strings.StringToInt(s.string, val, res);
				ASSERT(res = 0);
				IF val <= 0FFFFH THEN
					StdLog.String(name + ":" + s.string); StdLog.Ln;
				END
			END;
			REPEAT s.Scan UNTIL (s.type = TextMappers.char) & (s.char = "}") OR (s.type = TextMappers.eot);
			s.Scan; s.Scan
		END
	END ConvertHTMLEntityMapFromJSONFile;
	*)

END W3cHtmlImporter.
