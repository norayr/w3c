MODULE W3cObjects;

(* This module provides a simple collection framework for Component Pascal.

Original author: swalthert
Ported from A2 Oberon build 7131 to BlackBox Component Pascal, J. Templ, 2017-05-10 *)

TYPE
	String = POINTER TO ARRAY OF CHAR;
	
	Collection* = POINTER TO ABSTRACT RECORD END;

	ListElem = POINTER TO RECORD
		elem: ANYPTR;
		next: ListElem;
	END;

	List* = POINTER TO LIMITED RECORD (Collection)
		first, last: ListElem;
		nofElems: INTEGER;
	END;
	
	PTRArray* = POINTER TO ARRAY OF ANYPTR;
	
	ArrayCollection* = POINTER TO LIMITED RECORD (Collection)
		elems: PTRArray;
		nofElems: INTEGER;
	END;

	Enumerator* = POINTER TO ABSTRACT RECORD END;

	DictEnumerator* = POINTER TO ABSTRACT RECORD (Enumerator) END;

	ListEnumerator* = POINTER TO LIMITED RECORD (Enumerator)
		coll: List;
		current: ListElem;
	END;

	ArrayEnumerator* = POINTER TO LIMITED RECORD (Enumerator)
		array: PTRArray;
		current: INTEGER;
	END;

	ArrayDictEnumerator* = POINTER TO LIMITED RECORD (DictEnumerator)
		keys: StringArray;
		elems: PTRArray;
		current: INTEGER;
	END;

	Dictionary* = POINTER TO ABSTRACT RECORD END;
	
	StringArray = POINTER TO ARRAY OF String;

	ArrayDict* = POINTER TO LIMITED RECORD (Dictionary)
		nofElems: INTEGER;
		keys: StringArray;
		elems: PTRArray;
	END;

PROCEDURE^ (this: ListEnumerator) Init*(list: List), NEW;
PROCEDURE^ (this: ArrayEnumerator) Init*(array: PTRArray), NEW;


(* ------ Collection ------ *)

PROCEDURE (this: Collection) GetNumberOfElements*(): INTEGER, NEW, ABSTRACT;

PROCEDURE (this: Collection) GetEnumerator*(): Enumerator, NEW, ABSTRACT;

PROCEDURE (this: Collection) Add*(p: ANYPTR), NEW, ABSTRACT;

PROCEDURE (this: Collection) Remove*(p: ANYPTR), NEW, ABSTRACT;


(* ------ ListElem ------ *)

PROCEDURE (this: ListElem) Init(elem: ANYPTR), NEW;
BEGIN
	this.elem := elem;
	this.next := NIL;
END Init;


(* ------ List ------ *)

PROCEDURE (this: List) Init*, NEW;
BEGIN
	this.nofElems := 0
END Init;

PROCEDURE (this: List) GetNumberOfElements*(): INTEGER;
BEGIN
	RETURN this.nofElems
END GetNumberOfElements;

PROCEDURE (this: List) GetEnumerator*(): Enumerator;
	VAR le: ListEnumerator;
BEGIN
	NEW(le); le.Init(this);
	RETURN le
END GetEnumerator;

PROCEDURE (this: List) Add*(p: ANYPTR);
	VAR newListElem: ListElem;
BEGIN
	IF p # NIL THEN
		NEW(newListElem); newListElem.Init(p);
		IF this.last = NIL THEN
			this.first := newListElem;
			this.last := newListElem
		ELSE
			this.last.next := newListElem;
			this.last := this.last.next
		END;
		INC(this.nofElems)
	END
END Add;

PROCEDURE (this: List) Remove*(p: ANYPTR);
	VAR le: ListElem;
BEGIN
	IF (p # NIL) & (this.first # NIL) THEN
		IF this.first.elem = p THEN
			this.first := this.first.next; DEC(this.nofElems)
		ELSE
			le := this.first;
			WHILE (le.next # NIL) & (le.next.elem # p) DO
				le := le.next
			END;
			IF le.next # NIL THEN (* le.next.elem = o *)
				le.next := le.next.next; DEC(this.nofElems)
			END
		END
	END
END Remove;


(* ------ ArrayCollection ------ *)

PROCEDURE (this: ArrayCollection) Init*, NEW;
BEGIN
	this.nofElems := 0;
	NEW(this.elems, 1);
END Init;

PROCEDURE (this: ArrayCollection) GetNumberOfElements*(): INTEGER;
BEGIN
	RETURN this.nofElems
END GetNumberOfElements;

PROCEDURE (this: ArrayCollection) GetEnumerator*(): Enumerator;
	VAR ace: ArrayEnumerator;
BEGIN
	NEW(ace); ace.Init(this.elems);
	RETURN ace
END GetEnumerator;

PROCEDURE (this: ArrayCollection) Grow, NEW;
	VAR i: INTEGER; oldElems: PTRArray;
BEGIN
	oldElems := this.elems;
	NEW(this.elems, 2 * LEN(this.elems));
	FOR i := 0 TO this.nofElems - 1 DO
		this.elems[i] := oldElems[i]
	END
END Grow;

PROCEDURE (this: ArrayCollection) Add*(p: ANYPTR);
BEGIN
	IF p # NIL THEN
		IF this.nofElems = LEN(this.elems) THEN this.Grow() END;
		this.elems[this.nofElems] := p;
		INC(this.nofElems)
	END
END Add;

PROCEDURE (this: ArrayCollection) Remove*(p: ANYPTR);
	VAR i: INTEGER;
BEGIN
	i := 0;
	WHILE (i < this.nofElems) & (this.elems[i] # p) DO
		INC(i)
	END;
	IF i < this.nofElems THEN
		WHILE (i < this.nofElems - 1) DO
			this.elems[i] := this.elems[i + 1]; INC(i)
		END;
		DEC(this.nofElems); this.elems[this.nofElems] := NIL
	END
END Remove;

PROCEDURE (this: ArrayCollection) GetElement*(i: INTEGER): ANYPTR, NEW;
BEGIN
	IF (0 <= i) & (i < this.nofElems) THEN RETURN this.elems[i]
	ELSE RETURN NIL
	END
END GetElement;

PROCEDURE (this: ArrayCollection) Invert(ptr1, ptr2: ANYPTR): BOOLEAN, NEW;
	VAR pos1, pos2, i: INTEGER; ptr: ANYPTR;
BEGIN
	i := 0; pos1 := -1; pos2 := -1;
	WHILE (i < this.nofElems) & ((pos1 < 0) OR (pos2 < 0)) DO
		IF this.elems[i] = ptr1 THEN pos1 := i END;
		IF this.elems[i] = ptr2 THEN pos2 := i END;
		INC(i)
	END;
	IF (pos1 >= 0) & (pos2 >= 0) & (pos1 # pos2) THEN
		this.elems[pos1] := ptr2; this.elems[pos2] := ptr1;
		RETURN TRUE
	END;
	RETURN FALSE
END Invert;

PROCEDURE (this: ArrayCollection) GetElementPos*(ptr: ANYPTR): INTEGER, NEW;
	VAR i: INTEGER;
BEGIN
	WHILE i < this.nofElems DO
		IF this.elems[i] = ptr THEN RETURN i END;
		INC(i)
	END;
	RETURN -1
END GetElementPos;

PROCEDURE (this: ArrayCollection) MoveUp*(ptr: ANYPTR; i: INTEGER): BOOLEAN, NEW;
	VAR p: ANYPTR;
BEGIN
	IF ptr # NIL THEN i := this.GetElementPos(ptr) END;
	IF (i > 0) & (i < this.nofElems) THEN
		p := this.elems[i]; this.elems[i] := this.elems[i-1]; this.elems[i-1] := p;
		RETURN TRUE
	END;
	RETURN FALSE
END MoveUp;

PROCEDURE (this: ArrayCollection) MoveDown*(ptr: ANYPTR; i: INTEGER): BOOLEAN, NEW;
	VAR p: ANYPTR;
BEGIN
	IF ptr # NIL THEN i := this.GetElementPos(ptr) END;
	IF (i >=0) & (i < this.nofElems-1) THEN
		p := this.elems[i]; this.elems[i] := this.elems[i+1]; this.elems[i+1] := p;
		RETURN TRUE
	END;
	RETURN FALSE
END MoveDown;


(* ------ Enumerator ------ *)

PROCEDURE (this: Enumerator) HasMoreElements*(): BOOLEAN, NEW, ABSTRACT;

PROCEDURE (this: Enumerator) GetNext*(): ANYPTR, NEW, ABSTRACT;

PROCEDURE (this: Enumerator) Reset*, NEW, ABSTRACT;


(* ------ DictEnumerator ------ *)

(* refers to the entry selected by GetNext() *)
PROCEDURE (this: DictEnumerator) GetKey*(): String, NEW, ABSTRACT;


(* ------ ListEnumerator ------ *)

PROCEDURE (this: ListEnumerator) Init*(list: List), NEW;
BEGIN
	this.coll := list;
	this.current := list.first
END Init;

PROCEDURE (this: ListEnumerator) HasMoreElements*(): BOOLEAN;
BEGIN
	RETURN this.current # NIL
END HasMoreElements;

PROCEDURE (this: ListEnumerator) GetNext*(): ANYPTR;
	VAR p: ANYPTR;
BEGIN
	IF this.HasMoreElements() THEN p := this.current.elem; this.current := this.current.next; ELSE p := NIL; END;
	RETURN p
END GetNext;

PROCEDURE (this: ListEnumerator) Reset*;
BEGIN
	this.Init(this.coll)
END Reset;


(* ------ ArrayEnumerator ------ *)

PROCEDURE (this: ArrayEnumerator) Init*(array: PTRArray), NEW;
BEGIN
	this.array := array;
	this.current := 0
END Init;

PROCEDURE (this: ArrayEnumerator) HasMoreElements*(): BOOLEAN;
BEGIN
	RETURN (this.current < LEN(this.array)) & (this.array[this.current] # NIL)
END HasMoreElements;

PROCEDURE (this: ArrayEnumerator) GetNext*(): ANYPTR;
	VAR p: ANYPTR;
BEGIN
	IF this.HasMoreElements() THEN
		p := this.array[this.current]; INC(this.current);
	ELSE
		p := NIL;
	END;
	RETURN p
END GetNext;

PROCEDURE (this: ArrayEnumerator) Reset*;
BEGIN
	this.Init(this.array)
END Reset;


(* ------ Dictionary ------ *)

PROCEDURE (this: Dictionary) GetNumberOfElements*(): INTEGER, NEW, ABSTRACT;

PROCEDURE (this: Dictionary) Get*(IN key: ARRAY OF CHAR): ANYPTR, NEW, ABSTRACT;

PROCEDURE (this: Dictionary) GetEnumerator*(): DictEnumerator, NEW, ABSTRACT;

PROCEDURE (this: Dictionary) Add*(IN key: ARRAY OF CHAR; p: ANYPTR), NEW, ABSTRACT;

PROCEDURE (this: Dictionary) Remove*(IN key: ARRAY OF CHAR), NEW, ABSTRACT;


(* ------ArrayDictEnumerator ------ *)

PROCEDURE (this: ArrayDictEnumerator) Init*(keys: StringArray; elems: PTRArray), NEW;
BEGIN
	this.keys := keys;
	this.elems := elems;
	this.current := 0
END Init;

PROCEDURE (this: ArrayDictEnumerator) HasMoreElements*(): BOOLEAN;
BEGIN
	RETURN (this.current < LEN(this.elems)) & (this.elems[this.current] # NIL)
END HasMoreElements;

PROCEDURE (this: ArrayDictEnumerator) GetNext*(): ANYPTR;
	VAR p: ANYPTR;
BEGIN
	IF this.HasMoreElements() THEN
		p := this.elems[this.current]; INC(this.current);
	ELSE
		p := NIL;
	END;
	RETURN p
END GetNext;

PROCEDURE (this: ArrayDictEnumerator) GetKey*(): String;
BEGIN
	RETURN this.keys[this.current - 1]
END GetKey;

PROCEDURE (this: ArrayDictEnumerator) Reset*;
BEGIN
	this.Init(this.keys, this.elems)
END Reset;


(* ------ ArrayDict ------ *)

PROCEDURE (this: ArrayDict) Init*, NEW;
BEGIN
	this.nofElems := 0;
	NEW(this.keys, 16);
	NEW(this.elems, 16)
END Init;

PROCEDURE (this: ArrayDict) GetNumberOfElements*(): INTEGER;
BEGIN
	RETURN this.nofElems
END GetNumberOfElements;

PROCEDURE (this: ArrayDict) Get*(IN key: ARRAY OF CHAR): ANYPTR;
	VAR i: INTEGER;
BEGIN
	i := 0;
	WHILE (i < this.nofElems) & (this.keys[i]^ # key) DO
		INC(i)
	END;
	IF i < this.nofElems THEN RETURN this.elems[i]
	ELSE RETURN NIL
	END
END Get;

PROCEDURE (this: ArrayDict) GetEnumerator*(): DictEnumerator;
	VAR ade: ArrayDictEnumerator;
BEGIN
	NEW(ade); ade.Init(this.keys, this.elems);
	RETURN ade
END GetEnumerator;

PROCEDURE (this: ArrayDict) Grow, NEW;
	VAR i: INTEGER; oldKeys: StringArray; oldElems: PTRArray;
BEGIN
	oldKeys := this.keys; oldElems := this.elems;
	NEW(this.keys, 2 * LEN(this.keys)); NEW(this.elems, 2 * LEN(this.elems));
	FOR i := 0 TO this.nofElems - 1 DO
		this.keys[i] := oldKeys[i]; this.elems[i] := oldElems[i]
	END
END Grow;

PROCEDURE (this: ArrayDict) Add*(IN key: ARRAY OF CHAR; p: ANYPTR);
BEGIN
	IF this.Get(key) = NIL THEN
		IF this.nofElems = LEN(this.elems) THEN this.Grow() END;
		NEW(this.keys[this.nofElems], LEN(key$) + 1); this.keys[this.nofElems]^ := key$;
		this.elems[this.nofElems] := p;
		INC(this.nofElems)
	(* TODO J. Templ: ignoring Add if key exists is not what is expected in JSON objects for example;
		it also differs from Java Dictionary. A better strategy may be: the last one wins, i.e. Remove(key) first *)
	END
END Add;

PROCEDURE (this: ArrayDict) Remove*(IN key: ARRAY OF CHAR);
	VAR i: INTEGER;
BEGIN
	i := 0;
	WHILE (i < this.nofElems) & (this.keys[i]^ # key) DO
		INC(i)
	END;
	IF i < this.nofElems THEN
		WHILE (i < this.nofElems - 1) DO
			this.elems[i] := this.elems[i + 1];
			this.keys[i] := this.keys[i + 1];
			INC(i)
		END;
		DEC(this.nofElems); this.keys[this.nofElems] := NIL; this.elems[this.nofElems] := NIL
	END
END Remove;


(* ------ constructor functions ------ *)

PROCEDURE NewList*(): List;
	VAR lc: List;
BEGIN
	NEW(lc); lc.Init;
	RETURN lc
END NewList;

PROCEDURE NewArrayCollection*(): ArrayCollection;
	VAR ac: ArrayCollection;
BEGIN
	NEW(ac); ac.Init;
	RETURN ac
END NewArrayCollection;

PROCEDURE NewArrayEnumerator*(array: PTRArray): ArrayEnumerator;
	VAR ae: ArrayEnumerator;
BEGIN
	NEW(ae); ae.Init(array);
	RETURN ae
END NewArrayEnumerator;

PROCEDURE NewArrayDict*(): ArrayDict;
	VAR ad: ArrayDict;
BEGIN
	NEW(ad); ad.Init;
	RETURN ad
END NewArrayDict;

END W3cObjects.