MODULE bbStringsTest;
IMPORT Out, bbStrings;

VAR i: LONGINT;
  str: ARRAY 64 OF CHAR;
BEGIN

  i := 1000000;
  bbStrings.IntToString(i, str);
  Out.String(str); Out.Ln;

  i := -1000000;
  bbStrings.IntToString(i, str);
  Out.String(str); Out.Ln;


END bbStringsTest.
