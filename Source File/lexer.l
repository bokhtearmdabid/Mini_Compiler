%{
/*
 * Mini Compiler
 * Logs every token silently; print_tokens() called after parsing.
 */
#include "parser.tab.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int line_num = 1;

/* ── Token log ── */
#define MAXTOK 1000
struct TokEntry { char type[24]; char lex[48]; int line; } tlog[MAXTOK];
int ntok = 0;

static void logt(const char *type, const char *lex) {
    if (ntok < MAXTOK) {
        strncpy(tlog[ntok].type, type, 23); tlog[ntok].type[23] = 0;
        strncpy(tlog[ntok].lex,  lex,  47); tlog[ntok].lex[47]  = 0;
        tlog[ntok].line = line_num;
        ntok++;
    }
}

void print_tokens(void) {
    printf("+--------------------------------------------------+\n");
    printf("| PHASE 1: LEXICAL ANALYSIS                        |\n");
    printf("+------+---------------------+--------------------+\n");
    printf("| Line | Token Type          | Lexeme             |\n");
    printf("+------+---------------------+--------------------+\n");
    for (int i = 0; i < ntok; i++)
        printf("| %-4d | %-19s | %-18s |\n",
               tlog[i].line, tlog[i].type, tlog[i].lex);
    printf("+------+---------------------+--------------------+\n");
    printf("  Total tokens scanned: %d\n\n", ntok);
}
%}

%%
[ \t\r]+            { /* skip whitespace */ }
\n                  { line_num++; }
"//"[^\n]*          { /* skip comment */ }

"if"                { logt("KEYWORD",    "if");     return IF; }
"else"              { logt("KEYWORD",    "else");   return ELSE; }
"while"             { logt("KEYWORD",    "while");  return WHILE; }
"for"               { logt("KEYWORD",    "for");    return FOR; }
"print"             { logt("KEYWORD",    "print");  return PRINT; }
"int"               { logt("KEYWORD",    "int");    return INT; }
"func"              { logt("KEYWORD",    "func");   return FUNC; }
"return"            { logt("KEYWORD",    "return"); return RETURN; }

[a-zA-Z_][a-zA-Z0-9_]* {
    logt("IDENTIFIER", yytext);
    yylval.str = strdup(yytext); return IDENTIFIER;
}
[0-9]+ {
    logt("NUMBER", yytext);
    yylval.num = atoi(yytext); return NUMBER;
}
\"[^\"]*\" {
    logt("STRING", yytext);
    yylval.str = strdup(yytext); return STRING;
}

"=="  { logt("OP_EQUAL",     "=="); return EQUAL; }
"!="  { logt("OP_NOTEQUAL",  "!="); return NOTEQUAL; }
"<="  { logt("OP_LESSEQ",    "<="); return LESSEQUAL; }
">="  { logt("OP_GREATEREQ", ">="); return GREATEREQUAL; }
"<"   { logt("OP_LESS",      "<");  return LESS; }
">"   { logt("OP_GREATER",   ">");  return GREATER; }
"="   { logt("OP_ASSIGN",    "=");  return ASSIGN; }
"+"   { logt("OP_PLUS",      "+");  return PLUS; }
"-"   { logt("OP_MINUS",     "-");  return MINUS; }
"*"   { logt("OP_MULTIPLY",  "*");  return MULTIPLY; }
"/"   { logt("OP_DIVIDE",    "/");  return DIVIDE; }
"("   { logt("LPAREN",       "(");  return LPAREN; }
")"   { logt("RPAREN",       ")");  return RPAREN; }
"{"   { logt("LBRACE",       "{");  return LBRACE; }
"}"   { logt("RBRACE",       "}");  return RBRACE; }
";"   { logt("SEMICOLON",    ";");  return SEMICOLON; }
","   { logt("COMMA",        ",");  return COMMA; }

. {
    char buf[32];
    snprintf(buf, sizeof(buf), "ERR:'%s'", yytext);
    logt("LEXICAL_ERROR", buf);
    fprintf(stderr, "[Lex Error] Unknown character '%s' at line %d\n",
            yytext, line_num);
}
%%
int yywrap(void) { return 1; }
