%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void yyerror(const char *s);
int yylex(void);
extern int line_num;

/* ============================================================
   SYMBOL TABLE
   ============================================================ */
typedef struct {
    char *name;
    int   value;
    int   is_func;
    int   scope;       /* 0 = global, >0 = function scope */
} Symbol;

#define MAX_SYMBOLS 200
Symbol symbol_table[MAX_SYMBOLS];
int symbol_count = 0;
int current_scope = 0;

int lookup_symbol(const char *name) {
    /* search from current scope outward */
    for (int i = symbol_count - 1; i >= 0; i--) {
        if (strcmp(symbol_table[i].name, name) == 0 &&
            symbol_table[i].scope <= current_scope)
            return i;
    }
    return -1;
}

void add_symbol(const char *name, int value, int is_func) {
    int idx = lookup_symbol(name);
    if (idx != -1 && symbol_table[idx].scope == current_scope) {
        symbol_table[idx].value = value;
        return;
    }
    symbol_table[symbol_count].name    = strdup(name);
    symbol_table[symbol_count].value   = value;
    symbol_table[symbol_count].is_func = is_func;
    symbol_table[symbol_count].scope   = current_scope;
    symbol_count++;
}

int get_symbol_value(const char *name) {
    int idx = lookup_symbol(name);
    if (idx == -1) {
        fprintf(stderr, "Semantic Error: Undefined variable '%s' at line %d\n", name, line_num);
        return 0;
    }
    return symbol_table[idx].value;
}

void print_symbol_table(void) {
    printf("\n========== SYMBOL TABLE ==========\n");
    printf("%-20s %-10s %-10s %-10s\n", "Name", "Value", "Type", "Scope");
    printf("--------------------------------------------------\n");
    for (int i = 0; i < symbol_count; i++) {
        printf("%-20s %-10d %-10s %-10d\n",
               symbol_table[i].name,
               symbol_table[i].value,
               symbol_table[i].is_func ? "function" : "variable",
               symbol_table[i].scope);
    }
    printf("==================================\n\n");
}

/* ============================================================
   THREE-ADDRESS CODE (Intermediate Representation)
   ============================================================ */
typedef struct {
    char op[16];
    char arg1[64];
    char arg2[64];
    char result[64];
} TAC;

#define MAX_TAC 500
TAC tac_code[MAX_TAC];
int tac_count = 0;
int temp_count = 0;
int label_count = 0;

char* new_temp(void) {
    char *t = malloc(16);
    sprintf(t, "t%d", temp_count++);
    return t;
}

char* new_label(void) {
    char *l = malloc(16);
    sprintf(l, "L%d", label_count++);
    return l;
}

void emit(const char *op, const char *arg1, const char *arg2, const char *result) {
    strcpy(tac_code[tac_count].op,     op     ? op     : "");
    strcpy(tac_code[tac_count].arg1,   arg1   ? arg1   : "");
    strcpy(tac_code[tac_count].arg2,   arg2   ? arg2   : "");
    strcpy(tac_code[tac_count].result, result ? result : "");
    tac_count++;
}

void print_tac(void) {
    printf("\n===== INTERMEDIATE CODE (3-Address) =====\n");
    for (int i = 0; i < tac_count; i++) {
        TAC *t = &tac_code[i];
        if (strcmp(t->op, "LABEL") == 0) {
            printf("%s:\n", t->result);
        } else if (strcmp(t->op, "=") == 0) {
            printf("  %s = %s\n", t->result, t->arg1);
        } else if (strcmp(t->op, "PRINT") == 0) {
            printf("  print %s\n", t->arg1);
        } else if (strcmp(t->op, "GOTO") == 0) {
            printf("  goto %s\n", t->result);
        } else if (strcmp(t->op, "IF_FALSE") == 0) {
            printf("  if_false %s goto %s\n", t->arg1, t->result);
        } else if (strcmp(t->op, "FUNC_BEGIN") == 0) {
            printf("\nfunc %s:\n", t->result);
        } else if (strcmp(t->op, "FUNC_END") == 0) {
            printf("  end_func\n\n");
        } else if (strcmp(t->op, "RETURN") == 0) {
            printf("  return %s\n", t->arg1);
        } else if (strcmp(t->op, "CALL") == 0) {
            printf("  %s = call %s\n", t->result, t->arg1);
        } else {
            printf("  %s = %s %s %s\n", t->result, t->arg1, t->op, t->arg2);
        }
    }
    printf("==========================================\n\n");
}

/* ============================================================
   ASSEMBLY CODE GENERATION
   ============================================================ */
void generate_assembly(void) {
    printf("\n========== ASSEMBLY CODE ==========\n");
    printf(".data\n");
    for (int i = 0; i < symbol_count; i++) {
        if (!symbol_table[i].is_func)
            printf("  %s: DW 0\n", symbol_table[i].name);
    }
    printf("\n.text\n");
    printf("  JMP main\n\n");

    for (int i = 0; i < tac_count; i++) {
        TAC *t = &tac_code[i];

        if (strcmp(t->op, "LABEL") == 0) {
            printf("%s:\n", t->result);

        } else if (strcmp(t->op, "FUNC_BEGIN") == 0) {
            printf("\n%s:\n", t->result);
            printf("  PUSH BP\n");
            printf("  MOV BP, SP\n");

        } else if (strcmp(t->op, "FUNC_END") == 0) {
            printf("  POP BP\n");
            printf("  RET\n\n");

        } else if (strcmp(t->op, "RETURN") == 0) {
            if (strlen(t->arg1) > 0)
                printf("  MOV AX, %s\n", t->arg1);
            printf("  POP BP\n");
            printf("  RET\n");

        } else if (strcmp(t->op, "=") == 0) {
            /* check if arg1 is a number */
            int is_num = 1;
            for (int c = 0; c < (int)strlen(t->arg1); c++)
                if (t->arg1[c] < '0' || t->arg1[c] > '9') { is_num = 0; break; }
            if (is_num)
                printf("  MOV AX, #%s\n", t->arg1);
            else
                printf("  MOV AX, [%s]\n", t->arg1);
            printf("  MOV [%s], AX\n", t->result);

        } else if (strcmp(t->op, "+") == 0) {
            printf("  MOV AX, [%s]\n", t->arg1);
            printf("  ADD AX, [%s]\n", t->arg2);
            printf("  MOV [%s], AX\n", t->result);

        } else if (strcmp(t->op, "-") == 0) {
            printf("  MOV AX, [%s]\n", t->arg1);
            printf("  SUB AX, [%s]\n", t->arg2);
            printf("  MOV [%s], AX\n", t->result);

        } else if (strcmp(t->op, "*") == 0) {
            printf("  MOV AX, [%s]\n", t->arg1);
            printf("  MUL AX, [%s]\n", t->arg2);
            printf("  MOV [%s], AX\n", t->result);

        } else if (strcmp(t->op, "/") == 0) {
            printf("  MOV AX, [%s]\n", t->arg1);
            printf("  DIV AX, [%s]\n", t->arg2);
            printf("  MOV [%s], AX\n", t->result);

        } else if (strcmp(t->op, "PRINT") == 0) {
            int is_str = (t->arg1[0] == '"');
            if (is_str)
                printf("  MOV AX, %s\n", t->arg1);
            else
                printf("  MOV AX, [%s]\n", t->arg1);
            printf("  OUT AX\n");

        } else if (strcmp(t->op, "IF_FALSE") == 0) {
            printf("  CMP [%s], #0\n", t->arg1);
            printf("  JE %s\n", t->result);

        } else if (strcmp(t->op, "GOTO") == 0) {
            printf("  JMP %s\n", t->result);

        } else if (strcmp(t->op, "CALL") == 0) {
            printf("  CALL %s\n", t->arg1);
            printf("  MOV [%s], AX\n", t->result);

        } else if (strcmp(t->op, "<") == 0 || strcmp(t->op, ">") == 0 ||
                   strcmp(t->op, "==") == 0 || strcmp(t->op, "!=") == 0 ||
                   strcmp(t->op, "<=") == 0 || strcmp(t->op, ">=") == 0) {
            printf("  MOV AX, [%s]\n", t->arg1);
            printf("  CMP AX, [%s]\n", t->arg2);
            printf("  SET%s [%s]\n",
                   strcmp(t->op,"<")  == 0 ? "L"  :
                   strcmp(t->op,">")  == 0 ? "G"  :
                   strcmp(t->op,"==") == 0 ? "E"  :
                   strcmp(t->op,"!=") == 0 ? "NE" :
                   strcmp(t->op,"<=") == 0 ? "LE" : "GE",
                   t->result);
        }
    }
    printf("===================================\n\n");
}

/* ============================================================
   EXPRESSION VALUE TRACKING (for constant folding / eval)
   ============================================================ */

/* We track expression results as named temporaries.
   value_of() resolves a name (number literal or variable). */
int value_of(const char *s) {
    /* try numeric */
    int alldig = 1;
    for (int i = 0; s[i]; i++) if (s[i] < '0' || s[i] > '9') { alldig = 0; break; }
    if (alldig) return atoi(s);
    return get_symbol_value(s);
}

/* ============================================================
   EXPRESSION RESULT STRUCT  (holds name of temp or literal)
   ============================================================ */
%}

%union {
    int   num;
    char *str;
}

%token <num> NUMBER
%token <str> STRING IDENTIFIER
%token ASSIGN EQUAL NOTEQUAL LESS GREATER LESSEQUAL GREATEREQUAL
%token PLUS MINUS MULTIPLY DIVIDE LPAREN RPAREN LBRACE RBRACE SEMICOLON COMMA
%token IF ELSE WHILE FOR PRINT INT RETURN FUNC

%type <str> expression comparison statement program arg_list param_list

%left PLUS MINUS
%left MULTIPLY DIVIDE
%nonassoc EQUAL NOTEQUAL LESS GREATER LESSEQUAL GREATEREQUAL

%%

program:
    program statement   { }
    | statement         { }
    ;

statement:
    /* Variable declaration & assignment */
    INT IDENTIFIER ASSIGN expression SEMICOLON
    {
        add_symbol($2, value_of($4), 0);
        emit("=", $4, NULL, $2);
        printf("[Parser] Assigned '%s' = %s\n", $2, $4);
    }
    | IDENTIFIER ASSIGN expression SEMICOLON
    {
        add_symbol($1, value_of($3), 0);
        emit("=", $3, NULL, $1);
        printf("[Parser] Reassigned '%s' = %s\n", $1, $3);
    }

    /* print expression */
    | PRINT expression SEMICOLON
    {
        emit("PRINT", $2, NULL, NULL);
        printf("[Parser] Print '%s'\n", $2);
    }
    | PRINT STRING SEMICOLON
    {
        emit("PRINT", $2, NULL, NULL);
        printf("[Parser] Print string %s\n", $2);
    }

    /* if-else */
    | IF LPAREN comparison RPAREN LBRACE program RBRACE
    {
        /* labels already emitted inside comparison + program */
    }
    | IF LPAREN comparison RPAREN LBRACE program RBRACE ELSE LBRACE program RBRACE
    {
    }

    /* while loop */
    | WHILE LPAREN comparison RPAREN LBRACE program RBRACE
    {
    }

    /* for loop */
    | FOR LPAREN IDENTIFIER ASSIGN expression SEMICOLON comparison SEMICOLON IDENTIFIER ASSIGN expression RPAREN LBRACE program RBRACE
    {
    }

    /* function definition */
    | FUNC IDENTIFIER LPAREN param_list RPAREN LBRACE program RBRACE
    {
        add_symbol($2, 0, 1);
        emit("FUNC_END", NULL, NULL, $2);
        current_scope--;
        printf("[Parser] Function '%s' defined\n", $2);
    }

    /* return */
    | RETURN expression SEMICOLON
    {
        emit("RETURN", $2, NULL, NULL);
    }
    ;

param_list:
    /* empty */  { $$ = strdup(""); }
    | INT IDENTIFIER
    {
        add_symbol($2, 0, 0);
        $$ = $2;
    }
    | param_list COMMA INT IDENTIFIER
    {
        add_symbol($4, 0, 0);
        $$ = $4;
    }
    ;

comparison:
    expression EQUAL expression
    {
        char *t = new_temp(); add_symbol(t, 0, 0);
        char *lend = new_label();
        emit("==", $1, $3, t);
        emit("IF_FALSE", t, NULL, lend);
        $$ = lend;
    }
    | expression NOTEQUAL expression
    {
        char *t = new_temp(); add_symbol(t, 0, 0);
        char *lend = new_label();
        emit("!=", $1, $3, t);
        emit("IF_FALSE", t, NULL, lend);
        $$ = lend;
    }
    | expression LESS expression
    {
        char *t = new_temp(); add_symbol(t, 0, 0);
        char *lend = new_label();
        emit("<", $1, $3, t);
        emit("IF_FALSE", t, NULL, lend);
        $$ = lend;
    }
    | expression GREATER expression
    {
        char *t = new_temp(); add_symbol(t, 0, 0);
        char *lend = new_label();
        emit(">", $1, $3, t);
        emit("IF_FALSE", t, NULL, lend);
        $$ = lend;
    }
    | expression LESSEQUAL expression
    {
        char *t = new_temp(); add_symbol(t, 0, 0);
        char *lend = new_label();
        emit("<=", $1, $3, t);
        emit("IF_FALSE", t, NULL, lend);
        $$ = lend;
    }
    | expression GREATEREQUAL expression
    {
        char *t = new_temp(); add_symbol(t, 0, 0);
        char *lend = new_label();
        emit(">=", $1, $3, t);
        emit("IF_FALSE", t, NULL, lend);
        $$ = lend;
    }
    ;

expression:
    expression PLUS expression
    {
        char *t = new_temp(); add_symbol(t, 0, 0);
        emit("+", $1, $3, t);
        symbol_table[lookup_symbol(t)].value = value_of($1) + value_of($3);
        char vbuf[32]; sprintf(vbuf, "%d", value_of($1) + value_of($3));
        $$ = t;
    }
    | expression MINUS expression
    {
        char *t = new_temp(); add_symbol(t, 0, 0);
        emit("-", $1, $3, t);
        symbol_table[lookup_symbol(t)].value = value_of($1) - value_of($3);
        $$ = t;
    }
    | expression MULTIPLY expression
    {
        char *t = new_temp(); add_symbol(t, 0, 0);
        emit("*", $1, $3, t);
        symbol_table[lookup_symbol(t)].value = value_of($1) * value_of($3);
        $$ = t;
    }
    | expression DIVIDE expression
    {
        char *t = new_temp(); add_symbol(t, 0, 0);
        emit("/", $1, $3, t);
        if (value_of($3) != 0)
            symbol_table[lookup_symbol(t)].value = value_of($1) / value_of($3);
        $$ = t;
    }
    | LPAREN expression RPAREN  { $$ = $2; }
    | NUMBER
    {
        char *buf = malloc(32);
        sprintf(buf, "%d", $1);
        $$ = buf;
    }
    | IDENTIFIER
    {
        $$ = $1;
    }
    | IDENTIFIER LPAREN arg_list RPAREN
    {
        char *t = new_temp(); add_symbol(t, 0, 0);
        emit("CALL", $1, $3, t);
        $$ = t;
        printf("[Parser] Function call '%s'\n", $1);
    }
    ;

arg_list:
    /* empty */  { $$ = strdup(""); }
    | expression { $$ = $1; }
    | arg_list COMMA expression { $$ = $3; }
    ;

%%

void yyerror(const char *s) {
    fprintf(stderr, "Syntax Error: %s at line %d\n", s, line_num);
}

int main(void) {
    printf("========== MINI COMPILER ==========\n");
    printf("   CSE 430 - Compiler Design Lab\n");
    printf("====================================\n\n");
    printf("----- Phase 1: Lexical Analysis -----\n");
    printf("[Lexer] Tokenizing input...\n\n");
    printf("----- Phase 2: Parsing & Semantic Analysis -----\n");

    int result = yyparse();

    printf("\n----- Phase 3: Symbol Table -----\n");
    print_symbol_table();

    printf("----- Phase 4: Intermediate Code -----\n");
    print_tac();

    printf("----- Phase 5: Code Generation (Assembly) -----\n");
    generate_assembly();

    if (result == 0)
        printf("[Compiler] Compilation successful!\n");
    else
        fprintf(stderr, "[Compiler] Compilation failed.\n");

    return result;
}
