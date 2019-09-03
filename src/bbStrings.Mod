MODULE bbStrings;
(* wrapper module to implement functions that have different interface or absent in usual Strings.Mod *)
IMPORT Strings;

CONST
  charCode* = -1; decimal* = 10; hexadecimal* = -2; roman*= -3;
  digitspace* = 08FX;
  showBase* = TRUE; hideBase* = FALSE;
  minLongIntRev = "8085774586302733229"; (* reversed string of -MIN(LONGINT) *)

 VAR
  maxExp: LONGINT;
  maxDig: LONGINT;
  factor: REAL; (* 10^maxDig *)
  digits: ARRAY 17 OF CHAR;
  toUpper, toLower: ARRAY 256 OF CHAR;

PROCEDURE Replace* (VAR s: ARRAY OF CHAR; pos, len: HUGEINT; VAR rep: ARRAY OF CHAR);
  (* replace stretch s[pos]..s[pos+len-1] with rep *)
  (* insert semantics if len = 0; delete semantics if Len(rep) = 0 *)
  VAR i, j, k, max, lenS: HUGEINT; ch: CHAR;
 BEGIN
  ASSERT(len >= 0, 20); ASSERT(pos >= 0, 21);
  lenS := Strings.Length(s); max := LEN(s) - 1;
  IF pos <= lenS THEN i := pos; j := 0;
   IF pos+len > lenS THEN len := lenS - pos END;
   WHILE (rep[j] # 0X) & (len > 0) DO
    s[i] := rep[j]; INC(i); INC(j); DEC(len)
   END;
   IF len > 0 THEN (* delete the remaining part of the stretch [pos, pos+len) *)
    REPEAT ch := s[i+len]; s[i] := ch; INC(i) UNTIL ch = 0X
   ELSE (* insert the remaining part of rep *)
    len := Strings.Length(rep) - j; k := lenS + len;
    IF k > max THEN k := max END;
    s[k] := 0X;
    WHILE k - len >= i DO s[k] := s[k-len]; DEC(k) END;
    WHILE (rep[j] # 0X) & (i < max) DO s[i] := rep[j]; INC(i); INC(j) END
   END
  END
END Replace;


 (* integer conversions *)

 PROCEDURE IntToString* (x: HUGEINT; VAR s: ARRAY OF CHAR);
  VAR j, k: LONGINT; ch: CHAR; a: ARRAY 32 OF CHAR;
 BEGIN
  IF x # MIN(HUGEINT) THEN
   IF x < 0 THEN s[0] := "-"; k := 1; x := -x ELSE k := 0 END;
   j := 0; REPEAT a[j] := CHR(x MOD 10 + ORD("0")); x := x DIV 10; INC(j) UNTIL x = 0
  ELSE
   a := minLongIntRev; s[0] := "-"; k := 1;
   j := 0; WHILE a[j] # 0X DO INC(j) END
  END;
  ASSERT(k + j < LEN(s), 23);
  REPEAT DEC(j); ch := a[j]; s[k] := ch; INC(k) UNTIL j = 0;
  s[k] := 0X
 END IntToString;

(* string manipulation routines *)

PROCEDURE Upper* (ch: CHAR): CHAR;
 BEGIN
  IF ORD(ch) < 256 THEN RETURN toUpper[ORD(ch)] ELSE RETURN ch END
 END Upper;

PROCEDURE ToUpper* (in: ARRAY OF CHAR; VAR out: ARRAY OF CHAR);
  VAR i, max: LONGINT;
 BEGIN i := 0; max := LEN(out)-1;
  WHILE (in[i] # 0X) & (i < max) DO
   IF ORD(in[i]) < 256 THEN out[i] := toUpper[ORD(in[i])] ELSE out[i] := in[i] END;
   INC(i)
  END;
  out[i] := 0X
 END ToUpper;

 PROCEDURE Lower* (ch: CHAR): CHAR;
 BEGIN 
  IF ORD(ch) < 256 THEN RETURN toLower[ORD(ch)] ELSE RETURN ch END
 END Lower;

 PROCEDURE ToLower* (in: ARRAY OF CHAR; VAR out: ARRAY OF CHAR);
  VAR i, max: LONGINT;
 BEGIN i := 0; max := LEN(out)-1;
  WHILE (in[i] # 0X) & (i < max) DO
   IF ORD(in[i]) < 256 THEN out[i] := toLower[ORD(in[i])] ELSE out[i] := in[i] END;
   INC(i)
  END;
  out[i] := 0X
 END ToLower;

END bbStrings.
