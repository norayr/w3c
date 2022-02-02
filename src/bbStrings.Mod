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
  maxDig: INTEGER;
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

  PROCEDURE StringToInt* (VAR s: ARRAY OF CHAR; VAR x: LONGINT; VAR res: LONGINT);
    CONST hexLimit = MAX(LONGINT) DIV 8 + 1;
    VAR i, j, k, digits: LONGINT; ch, top: CHAR; neg: BOOLEAN; base: LONGINT;
  BEGIN
    res := 0; i := 0; ch := s[0];
    WHILE (ch # 0X) & (ch <= " ") OR (ch = 8BX) OR (ch = 8FX) OR (ch = 0A0X) DO (* ignore leading blanks *)
      INC(i); ch := s[i]
    END;
    j := i; top := "0";
    WHILE (ch # 0X) & (ch # "H") & (ch # "X") & (ch # "%") DO
      IF ch > top THEN top := ch END;
      INC(j); ch := s[j]
    END;
    IF (ch = "H") OR (ch = "X") THEN
      x := 0; ch := s[i];
      IF ("0" <= ch) & (ch <= "9") OR ("A" <= ch) & (ch <= "F") THEN
        WHILE ch = "0" DO INC(i); ch := s[i] END;
        digits := 0;
        WHILE (res = 0) & (("0" <= ch) & (ch <= "9") OR ("A" <= ch) & (ch <= "F")) DO
          IF ch < "A" THEN k := ORD(ch) - ORD("0")
          ELSE k := ORD(ch) - ORD("A") + 10
          END;
          IF digits < 8 THEN
            x := x MOD hexLimit;
            IF x >= hexLimit DIV 2 THEN x := x - hexLimit END;
            x := x * 16 + k; INC(i); ch := s[i]
          ELSE res := 1
          END;
          INC(digits)
        END;
        IF res = 0 THEN
          IF (ch # "H") & (ch # "X") OR (s[i+1] # 0X) THEN res := 2 END
        END
      ELSE res := 2
      END
    ELSE
      IF ch = "%" THEN
        INC(j); ch := s[j]; base := 0;
        IF ("0" <= ch) & (ch <= "9") THEN
          k := ORD(ch) - ORD("0");
          REPEAT
            base := base * 10 + k;
            INC(j); ch := s[j]; k := ORD(ch) - ORD("0")
          UNTIL (ch < "0") OR (ch > "9") OR (base > (MAX(LONGINT) - k) DIV 10);
          IF ("0" <= ch) & (ch <= "9") THEN base := 0 END
        END
      ELSE
        base := 10
      END;

      IF (base < 2) OR (base > 16) THEN
        res := 2
      ELSIF (base <= 10) & (ORD(top) < base + ORD("0"))
      OR (base > 10) & (ORD(top) < base - 10 + ORD("A")) THEN
        x := 0; ch := s[i]; neg := FALSE;
        IF ch = "-" THEN INC(i); ch := s[i]; neg := TRUE ELSIF ch = "+" THEN INC(i); ch := s[i] END;
        WHILE (ch # 0X) & (ch <= " ") DO INC(i); ch := s[i] END;
        IF ("0" <= ch) & (ch <= "9") OR ("A" <= ch) & (ch <= "F") THEN
          IF ch <= "9" THEN k := ORD(ch) - ORD("0") ELSE k := ORD(ch) - ORD("A") + 10 END;
          WHILE (("0" <= ch) & (ch <= "9") OR ("A" <= ch) & (ch <= "F")) & (res = 0) DO
            IF x >= (MIN(LONGINT) + (base - 1) + k) DIV base THEN
              x := x * base - k; INC(i); ch := s[i];
              IF ch <= "9" THEN k := ORD(ch) - ORD("0") ELSE k := ORD(ch) - ORD("A") + 10 END
            ELSE res := 1
            END
          END
        ELSE res := 2
        END;
        IF res = 0 THEN
          IF ~neg THEN
            IF x > MIN(LONGINT) THEN x := -x ELSE res := 1 END
          END;
          IF (ch # 0X) & (ch # "%") THEN res := 2 END
        END
      ELSE
        res := 2
      END
    END
  END StringToInt;
     
  PROCEDURE StringToLInt* (VAR s: ARRAY OF CHAR; VAR x: HUGEINT; VAR res: LONGINT);
    CONST hexLimit = MAX(HUGEINT) DIV 8 + 1;
    VAR i, j, k, digits: LONGINT; ch, top: CHAR; neg: BOOLEAN; base: LONGINT;
  BEGIN
    res := 0; i := 0; ch := s[0];
    WHILE (ch # 0X) & (ch <= " ") OR (ch = 8BX) OR (ch = 8FX) OR (ch = 0A0X) DO (* ignore leading blanks *)
      INC(i); ch := s[i]
    END;
    j := i; top := "0";
    WHILE (ch # 0X) & (ch # "H") & (ch # "X") & (ch # "%") DO
      IF ch > top THEN top := ch END;
      INC(j); ch := s[j]
    END;
    IF (ch = "H") OR (ch = "X") THEN
      x := 0; ch := s[i];
      IF ("0" <= ch) & (ch <= "9") OR ("A" <= ch) & (ch <= "F") THEN
        WHILE ch = "0" DO INC(i); ch := s[i] END;
        digits := 0;
        WHILE (res = 0) & (("0" <= ch) & (ch <= "9") OR ("A" <= ch) & (ch <= "F")) DO
          IF ch < "A" THEN k := ORD(ch) - ORD("0")
          ELSE k := ORD(ch) - ORD("A") + 10
          END;
          IF digits < 16 THEN
            x := x MOD hexLimit;
            IF x >= hexLimit DIV 2 THEN x := x - hexLimit END;
            x := x * 16 + k; INC(i); ch := s[i]
          ELSE res := 1
          END;
          INC(digits)
        END;
        IF res = 0 THEN
          IF (ch # "H") & (ch # "X") OR (s[i+1] # 0X) THEN res := 2 END
        END
      ELSE res := 2
      END
    ELSE
      IF ch = "%" THEN
        INC(j); ch := s[j]; base := 0;
        IF ("0" <= ch) & (ch <= "9") THEN
          k := ORD(ch) - ORD("0");
          REPEAT
            base := base * 10 + k;
            INC(j); ch := s[j]; k := ORD(ch) - ORD("0")
          UNTIL (ch < "0") OR (ch > "9") OR (base > (MAX(LONGINT) - k) DIV 10);
          IF ("0" <= ch) & (ch <= "9") THEN base := 0 END
        END
      ELSE
        base := 10
      END;

      IF (base < 2) OR (base > 16) THEN
        res := 2
      ELSIF (base <= 10) & (ORD(top) < base + ORD("0"))
      OR (base > 10) & (ORD(top) < base -10 + ORD("A")) THEN
        x := 0; ch := s[i]; neg := FALSE;
        IF ch = "-" THEN INC(i); ch := s[i]; neg := TRUE ELSIF ch = "+" THEN INC(i); ch := s[i] END;
        WHILE (ch # 0X) & (ch <= " ") DO INC(i); ch := s[i] END;
        IF ("0" <= ch) & (ch <= "9") OR ("A" <= ch) & (ch <= "F") THEN
          IF ch <= "9" THEN k := ORD(ch) - ORD("0") ELSE k := ORD(ch) - ORD("A") + 10 END;
          WHILE (("0" <= ch) & (ch <= "9") OR ("A" <= ch) & (ch <= "F")) & (res = 0) DO
            IF x >= (MIN(HUGEINT) + (base - 1) + k) DIV base THEN
              x := x * base - k; INC(i); ch := s[i];
              IF ch <= "9" THEN k := ORD(ch) - ORD("0") ELSE k := ORD(ch) - ORD("A") + 10 END
            ELSE res := 1
            END
          END
        ELSE res := 2
        END;
        IF res = 0 THEN
          IF ~neg THEN
            IF x > MIN(HUGEINT) THEN x := -x ELSE res := 1 END
          END;
          IF (ch # 0X) & (ch # "%") THEN res := 2 END
        END
      ELSE
        res := 2
      END
    END
  END StringToLInt;          

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

 PROCEDURE Find* (VAR s: ARRAY OF CHAR; VAR pat: ARRAY OF CHAR; start: LONGINT; VAR pos: LONGINT);
    VAR j: LONGINT;
 BEGIN
    ASSERT(start >= 0, 20);
    IF (start = 0) OR (start <= Strings.Length(s) - Strings.Length(pat)) THEN
      (* start = 0 is optimization: need not call Len *)
      pos := start;
      WHILE s[pos] # 0X DO j := 0;
        WHILE (s[pos+j] = pat[j]) & (pat[j] # 0X) DO INC(j) END;
        IF pat[j] = 0X THEN RETURN END;
        INC(pos)
      END
    END;
    pos := -1       (* pattern not found *)
 END Find;

END bbStrings.
