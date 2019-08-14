MODULE w3cDStrings;

(* This module provides dynamically growing strings, string pools, andstring splitting.

With statistics and pool dump: No

2017-01-27, J. Templ, adapted for BlackBox from ETH Oberon A2; original author Stefan Walthert 
*)

IMPORT Strings;

CONST
	InitialSize = 64; (* of DynamicString *)
	LoadFactor = 0.75; (* of Pool hash table *)
	InitialCapacity = 16; (* of Pool hash table *)
	
	CR = 0DX;

TYPE
	String* = POINTER TO ARRAY OF CHAR;
	
	StringArray* = POINTER TO ARRAY OF String;
	
	DynamicString* = POINTER TO RECORD
		length-: LONGINT; (* current length of string excluding 0X *)
		buffer: String; (* { (buffer # NIL) & (LEN(buffer) = bufferSize) & LEN(buffer$) = length } *)
		bufferSize: LONGINT; (* {bufferSize >= InitialSize} *)
	END;
	
	HashTableEntries = POINTER TO HashTableEntry;
	
	HashTableEntry = RECORD
		value: String;
		hashcode: LONGINT;
		next: HashTableEntries; (* for direct chaining of collisions, sorted in ascending hashcode order; 
												note that hashtable^[i] is outside of the sorted collison list *)
	END;
	
	HashTable = POINTER TO ARRAY OF HashTableEntry;
	
	Pool* = POINTER TO RECORD
		nofEntries-: LONGINT; (* the number of entries added to the pool's hash table *)
		hashtable: HashTable; (* the pool's hash table; doubles its size in case of exceeding the threshold *)
		threshold: LONGINT; (* threshold = LEN(hashtable) * LoadFactor & nofEntries <= threshold *)
	END;



(* Set string to empty string without changing bufferSize *)
PROCEDURE (this: DynamicString) Clear*;
BEGIN
	this.buffer[0] := 0X;
	this.length := 0
END Clear;

(* constructor *)
PROCEDURE (this: DynamicString) Init*;
BEGIN
	this.bufferSize := InitialSize;
	NEW(this.buffer, this.bufferSize);
	this.Clear
END Init;

PROCEDURE (this: DynamicString) AdjustBufferSize(minSize: LONGINT);
	VAR newBuffer: String;
BEGIN
	IF minSize >= this.bufferSize THEN
		REPEAT this.bufferSize := 2 * this.bufferSize; UNTIL (this.bufferSize > minSize);
		NEW(newBuffer, this.bufferSize);
		newBuffer^ := this.buffer^$;
		this.buffer := newBuffer
	END
END AdjustBufferSize;

PROCEDURE (this: DynamicString) Put*(ch: CHAR; at: LONGINT);
BEGIN
	IF ch = 0X THEN (* truncate *)
		IF at < this.length THEN this.buffer[at] := 0X; this.length := at END
	ELSE
		IF at < this.length THEN this.buffer[at] := ch (* patch *)
		ELSIF at = this.length THEN (* append *)
			IF (at + 2 >= this.bufferSize) THEN this.AdjustBufferSize(at + 2); END;
			this.buffer[at] := ch; this.buffer[at + 1] := 0X; INC(this.length)
		END
	END
END Put;

PROCEDURE (this: DynamicString) Get*(at: LONGINT): CHAR;
BEGIN
	IF at >= this.length THEN
		RETURN 0X
	ELSE
		RETURN this.buffer[at]
	END
END Get;

PROCEDURE (this: DynamicString) AppendChar*(ch: CHAR);
BEGIN
	IF (ch # 0X) THEN
		IF (this.length + 1 + 1 >= this.bufferSize) THEN this.AdjustBufferSize(this.length + 1 + 1) END;
		this.buffer[this.length] := ch;
		this.buffer[this.length + 1] := 0X;
		INC(this.length)
	END
END AppendChar;

PROCEDURE (this: DynamicString) Append*(IN str: ARRAY OF CHAR);
	VAR strLength: LONGINT;
BEGIN
	strLength := LEN(str$);
	IF (this.length + strLength + 1 >= this.bufferSize) THEN this.AdjustBufferSize(this.length + strLength + 1) END;
	Strings.Replace(this.buffer, this.length, 0, str);
	INC(this.length, strLength)
END Append;

PROCEDURE (this: DynamicString) AppendInt*(x: HUGEINT);
	VAR numStr: ARRAY 24 OF CHAR;
BEGIN
	Strings.IntToString(x, numStr); this.Append(numStr)
END AppendInt;

PROCEDURE (this: DynamicString) AppendLn*();
BEGIN
	this.AppendChar(CR)
END AppendLn;

PROCEDURE (this: DynamicString) Extract*(offset, len: LONGINT): String;
	VAR s: String; i: LONGINT;
BEGIN
	IF offset < this.length THEN
		IF offset + len > this.length THEN len := this.length - offset END;
		NEW(s, len + 1);
		FOR i := 0 TO len - 1 DO
			s[i] := this.buffer[i + offset]
		END;
		s[len] := 0X
	ELSE
		NEW(s, 1); s[0] := 0X
	END;
	RETURN s
END Extract;

PROCEDURE (this: DynamicString) ToString*(): String;
VAR string: String;
BEGIN
	NEW(string, this.length + 1);
	string^ := this.buffer$;
	RETURN string
END ToString;

PROCEDURE (this: DynamicString) ToUpper*();
BEGIN
	Strings.ToUpper(this.buffer, this.buffer)
END ToUpper;

PROCEDURE (this: DynamicString) ToLower*();
BEGIN
	Strings.ToLower(this.buffer, this.buffer)
END ToLower;

PROCEDURE (this: DynamicString) FromString*(s: String);
BEGIN
	this.length := LEN(s$);
	NEW(this.buffer, this.length + 1);
	this.buffer^ := s$
END FromString;

(** Copy <len> characters starting at <offset> from string <ds> into this dynamic string*)
PROCEDURE (this: DynamicString) CopyFrom*(ds: DynamicString; offset, len: LONGINT);
	VAR i: LONGINT;
BEGIN
	ASSERT((ds # NIL) & (offset >= 0) & (len >= 0));
	IF (offset < this.length) THEN
		IF (offset + len > this.length) THEN len := this.length - offset; END;
		this.AdjustBufferSize(len + 1);
		FOR i := 0 TO len - 1 DO
			this.buffer[i] := ds.buffer[i + offset]
		END;
		this.buffer[len] := 0X;
		this.length := len
	ELSE
		this.buffer[0] := 0X;
		this.length := 0
	END
END CopyFrom;

PROCEDURE (this: DynamicString) EqualsTo*(IN string: ARRAY OF CHAR; ignoreCase: BOOLEAN): BOOLEAN;
	VAR len: LONGINT; result: BOOLEAN; i: LONGINT;
BEGIN
	len := LEN(string$);
	result := (len = this.length);
	IF result THEN
		i := 0;
		IF ignoreCase THEN
			WHILE result & (i < this.length) DO
				result := Strings.Upper(string[i]) = Strings.Upper(this.buffer[i]);
				INC(i)
			END
		ELSE
			WHILE result & (i < this.length) DO
				result := string[i] = this.buffer[i];
				INC(i)
			END
		END
	END;
	RETURN result
END EqualsTo;

(* JT: this Pool version uses a growing hashtable and an improved hash function *)

PROCEDURE (this: Pool) Clear*;
	VAR i: LONGINT; empty: HashTableEntry;
BEGIN
	empty.value := NIL; empty.hashcode := 0; empty.next := NIL;
	FOR i := 0 TO LEN(this.hashtable) - 1 DO
		this.hashtable[i] := empty
	END;
	this.nofEntries := 0
END Clear;

(* constructor *)
PROCEDURE (this: Pool) Init*;
BEGIN
	this.threshold := ENTIER(InitialCapacity * LoadFactor);
	NEW(this.hashtable, InitialCapacity)
END Init;

PROCEDURE Hash(IN s: ARRAY OF CHAR): LONGINT;
	VAR hashcode, i: LONGINT; ch: CHAR;
BEGIN
	hashcode := 0; i := 0; ch := s[0];
	WHILE (ch # 0X) DO
		hashcode := hashcode * 31 + ORD(ch);
		INC(i); ch := s[i]
	END;
	RETURN hashcode
END Hash;

PROCEDURE Find(IN s: ARRAY OF CHAR; hashcode: LONGINT; IN entry: HashTableEntry): String;
	VAR e: HashTableEntries;
BEGIN
	IF entry.value # NIL THEN
		IF (entry.hashcode = hashcode) & (entry.value^ = s) THEN RETURN entry.value
		ELSE e := entry.next;
			WHILE (e # NIL) & (e.hashcode < hashcode) DO e := e.next END;
			WHILE (e # NIL) & (e.hashcode = hashcode) DO
				IF e.value^ = s THEN RETURN e.value
				ELSE e := e.next
				END
			END
		END
	END;
	RETURN NIL
END Find;

PROCEDURE Add(value: String; hashcode: LONGINT; VAR entry: HashTableEntry; VAR free: HashTableEntries);
	VAR e, n, p: HashTableEntries;
BEGIN
	IF entry.value = NIL THEN
		entry.value := value;
		entry.hashcode := hashcode;
	ELSE
		IF free # NIL THEN n := free; free := n.next; ELSE NEW(n); END;
		n.value := value; n.hashcode := hashcode;
		IF entry.next = NIL THEN (*create list*) entry.next := n; n.next := NIL
		ELSE e := entry.next;
			IF hashcode < e.hashcode THEN (*prepend*) n.next := e; entry.next := n
			ELSE (*sorted insert*)
				p := e; e := e.next;
				WHILE (e # NIL) & (e.hashcode < hashcode) DO p := e; e := e.next END;
				n.next := e; p.next := n
			END
		END
	END
END Add;

PROCEDURE MoveEntries(IN entry: HashTableEntry; newht: HashTable; VAR free: HashTableEntries);
	VAR len: LONGINT; e, n: HashTableEntries;
BEGIN
	IF entry.value # NIL THEN
		len := LEN(newht);
		Add(entry.value, entry.hashcode, newht[entry.hashcode MOD len], free);
		e := entry.next;
		WHILE e # NIL DO
			n := e.next; e.next := free; free := e; (* HashTableEntry may be reused via free *)
			Add(e.value, e.hashcode, newht[e.hashcode MOD len], free); e := n
		END
	END
END MoveEntries;

PROCEDURE (this: Pool) Grow();
	VAR newht: HashTable; i: LONGINT; free: HashTableEntries;
BEGIN
	NEW(newht, LEN(this.hashtable) * 2); free := NIL;
	FOR i := 0 TO LEN(this.hashtable) - 1 DO
		MoveEntries(this.hashtable[i], newht, free)
	END ;
	this.hashtable := newht;
	this.threshold := SHORT(ENTIER(LEN(newht) * LoadFactor))
END Grow;

(** Get string from pool. If the string is not contained in the pool, a copy of it is added to the pool *)
PROCEDURE (this: Pool) Get*(ds: DynamicString): String;
	VAR string: String; hashcode, entry: LONGINT; free: HashTableEntries;
BEGIN
	ASSERT(ds # NIL);
	hashcode := Hash(ds.buffer);
	entry := hashcode MOD LEN(this.hashtable);
	string := Find(ds.buffer, hashcode, this.hashtable[entry]);
	 
	IF string = NIL THEN (* Add *)
		IF this.nofEntries >= this.threshold THEN
			this.Grow();
			entry := hashcode MOD LEN(this.hashtable)
		END;
		NEW(string, ds.length + 1); string^ := ds.buffer$; free := NIL;
		Add(string, hashcode, this.hashtable[entry], free);
		INC(this.nofEntries)
	END;
	ASSERT(string # NIL);
	RETURN string
END Get;

(* creates, initializes and returns a new String object *)
PROCEDURE NewString* (IN str: ARRAY OF CHAR): String;
	VAR s: String;
BEGIN
	NEW(s, LEN(str$) + 1); s^ := str$; 
	RETURN s
END NewString;

(* creates, initializes and returns a new DynamicString object *)
PROCEDURE NewDynamicString* (): DynamicString;
	VAR ds: DynamicString;
BEGIN
	NEW(ds); ds.Init;
	RETURN ds
END NewDynamicString;

(* creates, initializes and returns a new Pool object *)
PROCEDURE NewPool* (): Pool;
	VAR p: Pool;
BEGIN
	NEW(p); p.Init;
	RETURN p
END NewPool;

(* returns the number of occurences of pat within string *)
PROCEDURE Count* (IN string, pat: ARRAY OF CHAR): LONGINT;
	VAR count, patLen, pos: LONGINT;
BEGIN
	ASSERT(pat # "", 20);
	count := 0; patLen := LEN(pat$); Strings.Find (string, pat, 0, pos);
	WHILE pos # -1 DO INC(count); Strings.Find(string, pat, pos + patLen, pos) END;
	RETURN count
END Count;

(* Splits 'string' into multiple strings separated by 'separator'.
 * Post:
 *      separator = "":         LEN(Result) = 1
 *      separator # "":         LEN(Result) = 1 + <Number of occurences of 'pat' in 'string'>
 *      StringArray[i] # NIL (0 <= i <= LEN(Result) - 1)
*)
PROCEDURE Split*(IN string, separator: ARRAY OF CHAR): StringArray;
	VAR count, sepLen, index, pos, next: LONGINT; result: StringArray;
	
	PROCEDURE Copy (IN src: ARRAY OF CHAR; pos, len: LONGINT; OUT dst: ARRAY OF CHAR);
		VAR i: LONGINT;
	BEGIN
		FOR i := 0 TO len - 1 DO dst[i] := src[pos + i] END;
		dst[len] := 0X
	END Copy;

BEGIN
	IF separator # "" THEN
		count := Count (string, separator); sepLen := LEN(separator$);
		NEW (result, count + 1); pos := 0;
		FOR index := 0 TO count DO
			Strings.Find (string, separator, pos, next);
			IF next = -1 THEN next := LEN(string$) END;
			NEW(result[index], next - pos + 1);
			Copy(string, pos, next - pos, result[index]^);
			pos := next + sepLen;
		END
	ELSE
		NEW(result, 1); result[0] := NewString(string)
	END;
	RETURN result;
END Split;



END w3cDStrings.
