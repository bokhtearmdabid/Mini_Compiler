%{
#include "parser.tab.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int line_num = 1;
void yyerror(const char *s);
%}

%%

[ \t\r]+                  { /* ignore whitespace */ }
"\n"                      { line_num++; }
"//"[^\n]*                { /* ignore single-line comments */ }

"if"                      { return IF; }
"else"                    { return ELSE; }
"while"                   { return WHILE; }
"for"                     { return FOR; }
"print"                   { return PRINT; }
"int"                     { return INT; }
"return"                  { return RETURN; }
"func"                    { return FUNC; }

[a-zA-Z_][a-zA-Z0-9_]*   { yylval.str = strdup(yytext); return IDENTIFIER; }
[0-9]+                    { yylval.num = atoi(yytext); return NUMBER; }
\"[^\"]*\"                { yylval.str = strdup(yytext); return STRING; }

"=="                      { return EQUAL; }
"!="                      { return NOTEQUAL; }
"<="                      { return LESSEQUAL; }
">="                      { return GREATEREQUAL; }
"<"                       { return LESS; }
">"                       { return GREATER; }
"="                       { return ASSIGN; }
"+"                       { return PLUS; }
"-"                       { return MINUS; }
"*"                       { return MULTIPLY; }
"/"                       { return DIVIDE; }
"("                       { return LPAREN; }
")"                       { return RPAREN; }
"{"                       { return LBRACE; }
"}"                       { return RBRACE; }
";"                       { return SEMICOLON; }
","                       { return COMMA; }

.                         { fprintf(stderr, "Lexical Error: Unknown character '%s' at line %d\n", yytext, line_num); }

%%

int yywrap() { return 1; }
