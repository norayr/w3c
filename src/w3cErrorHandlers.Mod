MODULE W3cErrorHandlers;

(* This module provides a base class and default implementation for error handling in scanners and parsers. *)

IMPORT Strings, Dialog,
	DStrings := W3cDStrings;

CONST
	MinErrorDist = 4;
	MaxErrNum = 20;

TYPE
	ErrorHandler* = POINTER TO EXTENSIBLE RECORD
		configMinErrorDist*, (* configured minimum distance between handled errors *)
		configMaxErrNum*: LONGINT; (* configured maximum number of errors reported *)
		errorLog*: DStrings.DynamicString; (* buffer for default error reporting; one line per error *)
		cont*: BOOLEAN; (* continue after error handling *)
		nofErrors*, (* total number of errors reported *)
		lastErrorPos*: LONGINT; (* last error position, initially -configMinErrorDist *)
	END;

PROCEDURE (this: ErrorHandler) Reset* (), NEW, EXTENSIBLE;
BEGIN
	this.lastErrorPos := -this.configMinErrorDist; this.nofErrors := 0; this.cont := TRUE;
	this.errorLog.Clear
END Reset;

(* constructor *)
PROCEDURE (this: ErrorHandler) Init* (), NEW, EXTENSIBLE;
BEGIN
	this.configMinErrorDist := MinErrorDist;
	this.configMaxErrNum := MaxErrNum;
	this.errorLog := DStrings.NewDynamicString();
	this.Reset
END Init;

(* appends error message to errorLog and continues; can be overridden *)
PROCEDURE (this: ErrorHandler) ReportError* (pos, line, col: LONGINT; VAR msg: ARRAY OF CHAR),
																	NEW, EXTENSIBLE;
	VAR posStr, lineStr, colStr: ARRAY 24 OF CHAR; errPos, errMsg: Dialog.String;
BEGIN
	Strings.IntToString(pos, posStr);
	Strings.IntToString(line, lineStr);
	Strings.IntToString(col, colStr);
	Dialog.MapParamString("#W3c:errPos", posStr, lineStr, colStr, errPos);
	Dialog.MapParamString("#W3c:errMsg", errPos, msg, "", errMsg);
	this.errorLog.Append(errMsg); this.errorLog.AppendLn
END ReportError;

(* handles an error message, usually not overridden *)
PROCEDURE (this: ErrorHandler) HandleError* (pos, line, col: LONGINT; VAR msg: ARRAY OF CHAR),
																	NEW, EXTENSIBLE;
BEGIN
	IF this.cont & (pos - this.lastErrorPos >= this.configMinErrorDist) & (this.nofErrors < this.configMaxErrNum) THEN
		this.lastErrorPos := pos; INC(this.nofErrors);
		this.ReportError(pos, line, col, msg);
	END
END HandleError;

END W3cErrorHandlers.