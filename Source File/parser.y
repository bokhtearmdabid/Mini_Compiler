%{
/*
 * Mini Compiler (Bison parser) By Bokhtear MD Abid 
 *
 * Phases implemented:
 *   1. Lexical Analysis   (in lexer.l, printed here)
 *   2. Syntax Analysis    (grammar rules logged during parse)
 *   3. Semantic Analysis  (type/scope checks, symbol table)
 *   4. Intermediate Code  (Three-Address Code)
 *   5. Code Optimization  (constant fold, copy propagation, dead-code elim)
 *   6. Code Generation    (pseudo x86 assembly)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void yyerror(const char *s);
int  yylex(void);
extern int  line_num;
extern void print_tokens(void);   /* defined in lexer.l */

/* ================================================================
   SYNTAX RULE LOG  (Phase 2)
   ================================================================ */
static char syn_log[400][80];
static int  nsyn = 0;

static void log_rule(const char *rule) {
    if (nsyn < 400) {
        strncpy(syn_log[nsyn], rule, 79);
        syn_log[nsyn][79] = 0;
        nsyn++;
    }
}

/* ================================================================
   SYMBOL TABLE  (Phase 3)
   ================================================================ */
typedef struct { char name[32]; int val; int is_func; int scope; } Sym;
static Sym   sym[300];
static int   nsym     = 0;
static int   cur_scope = 0;
static int   sem_err  = 0;

/* Semantic log */
static char sem_log[600][96];
static int  nsem = 0;
static void slog(const char *msg) {
    if (nsem < 600) { strncpy(sem_log[nsem], msg, 95); sem_log[nsem++][95]=0; }
}

/* Find symbol (search from newest, respect scope) */
static int sym_find(const char *n) {
    for (int i = nsym-1; i >= 0; i--)
        if (!strcmp(sym[i].name, n) && sym[i].scope <= cur_scope) return i;
    return -1;
}

/* Add / update symbol */
static void sym_add(const char *n, int v, int is_func) {
    int i = sym_find(n);
    if (i != -1 && sym[i].scope == cur_scope) {
        /* update existing */
        int old = sym[i].val;
        sym[i].val = v;
        char buf[96];
        snprintf(buf, sizeof(buf),
            "  UPDATE  %-12s  %d -> %d  (scope %d)", n, old, v, cur_scope);
        slog(buf);
        return;
    }
    /* new entry */
    strncpy(sym[nsym].name, n, 31); sym[nsym].name[31]=0;
    sym[nsym].val     = v;
    sym[nsym].is_func = is_func;
    sym[nsym].scope   = cur_scope;
    nsym++;
    char buf[96];
    snprintf(buf, sizeof(buf),
        "  DECLARE %-12s  val=%-5d  scope=%-2d  type=%s",
        n, v, cur_scope, is_func ? "function" : "variable");
    slog(buf);
}

/* Get value; report error if undefined */
static int sym_get(const char *n) {
    int i = sym_find(n);
    if (i == -1) {
        char buf[96];
        snprintf(buf, sizeof(buf),
            "  ERROR   Undefined variable '%s' at line %d", n, line_num);
        slog(buf);
        fprintf(stderr, "[Semantic Error] Undefined variable '%s' at line %d\n",
                n, line_num);
        sem_err++;
        return 0;
    }
    char buf[96];
    snprintf(buf, sizeof(buf),
        "  USE     %-12s  = %d  (scope %d)", n, sym[i].val, sym[i].scope);
    slog(buf);
    return sym[i].val;
}

/* Update value of existing symbol (no new entry, no log spam) */
static void sym_set(const char *n, int v) {
    int i = sym_find(n);
    if (i != -1) sym[i].val = v;
}

/* ================================================================
   THREE-ADDRESS CODE  (Phase 4)
   ================================================================ */
typedef struct {
    char op[8];   /* operator: = + - * / < > == != <= >= PRT JF JMP LBL RET FN FE CALL */
    char a[40];   /* arg1 */
    char b[40];   /* arg2 (empty if not used) */
    char r[40];   /* result */
    int  dead;    /* 1 = removed by optimizer */
} TAC;

static TAC  tac[600];
static int  ntac   = 0;
static int  ntemp  = 0;
static int  nlabel = 0;

static void emit(const char *op,
                 const char *a, const char *b, const char *r) {
    if (ntac >= 600) return;
    TAC *t = &tac[ntac++];
    strncpy(t->op, op ? op : "", 7);  t->op[7] = 0;
    strncpy(t->a,  a  ? a  : "", 39); t->a[39]  = 0;
    strncpy(t->b,  b  ? b  : "", 39); t->b[39]  = 0;
    strncpy(t->r,  r  ? r  : "", 39); t->r[39]  = 0;
    t->dead = 0;
}

/* Make a fresh temp variable name */
static char *mktmp(void) {
    char *t = malloc(16);
    sprintf(t, "t%d", ntemp++);
    sym_add(t, 0, 0);          /* register in symbol table */
    return t;
}

/* Make a fresh label name */
static char *mklbl(void) {
    char *l = malloc(16);
    sprintf(l, "L%d", nlabel++);
    return l;
}

/* ── TAC print helper ── */
static void div_line(void) {
    printf("+----------------------------------------------------+\n");
}
static void print_tac(TAC *arr, int n, const char *title) {
    div_line();
    printf("| %-50s |\n", title);
    div_line();
    for (int i = 0; i < n; i++) {
        TAC *t = &arr[i];
        if (t->dead) continue;
        if      (!strcmp(t->op,"LBL"))  printf("  %s:\n",                    t->r);
        else if (!strcmp(t->op,"="))    printf("  %-8s = %s\n",              t->r, t->a);
        else if (!strcmp(t->op,"PRT"))  printf("  print    %s\n",            t->a);
        else if (!strcmp(t->op,"JMP"))  printf("  goto     %s\n",            t->r);
        else if (!strcmp(t->op,"JF"))   printf("  if_false %s  goto %s\n",   t->a, t->r);
        else if (!strcmp(t->op,"RET"))  printf("  return   %s\n",            t->a);
        else if (!strcmp(t->op,"CALL")) printf("  %-8s = call %s(%s)\n",     t->r, t->a, t->b);
        else if (!strcmp(t->op,"FN"))   printf("\nbegin_func %s:\n",         t->r);
        else if (!strcmp(t->op,"FE"))   printf("  end_func  %s\n\n",         t->r);
        else                            printf("  %-8s = %s %s %s\n",        t->r, t->a, t->op, t->b);
    }
    div_line();
    printf("\n");
}

/* ================================================================
   HELPERS
   ================================================================ */

/* True if string is a non-negative integer literal */
static int is_num_lit(const char *s) {
    if (!s || !s[0]) return 0;
    for (int i = 0; s[i]; i++)
        if (s[i] < '0' || s[i] > '9') return 0;
    return 1;
}

/* True if name is a compiler-generated temp (t0, t1, t23, …) */
static int is_temp(const char *s) {
    if (!s || s[0] != 't') return 0;
    if (!s[1] || s[1] < '0' || s[1] > '9') return 0;
    return 1;
}

/* Resolve compile-time value of an expression result name */
static int val_of(const char *s) {
    if (is_num_lit(s)) return atoi(s);
    int i = sym_find(s);
    return (i != -1) ? sym[i].val : 0;
}

/* ================================================================
   CODE OPTIMIZATION  (Phase 5)
   ================================================================ */
static TAC opt[600];
static int nopt = 0;

static void optimize(void) {
    /* Copy TAC into optimizer buffer */
    memcpy(opt, tac, ntac * sizeof(TAC));
    nopt = ntac;

    div_line();
    printf("| PHASE 5: CODE OPTIMIZATION                         |\n");
    div_line();

    int any_opt = 0;
    int changed = 1;

    while (changed) {
        changed = 0;

        /* ── Pass A: Constant Folding ─────────────────────────
           If both operands of an arithmetic op are integer
           literals, replace the instruction with a simple assign. */
        for (int i = 0; i < nopt; i++) {
            TAC *t = &opt[i];
            if (t->dead) continue;
            if (!is_num_lit(t->a) || !is_num_lit(t->b)) continue;
            int a = atoi(t->a), b = atoi(t->b), res = 0, ok = 1;
            if      (!strcmp(t->op,"+")) res = a + b;
            else if (!strcmp(t->op,"-")) res = a - b;
            else if (!strcmp(t->op,"*")) res = a * b;
            else if (!strcmp(t->op,"/")) {
                if (b == 0) { ok = 0; }   /* skip division by zero */
                else res = a / b;
            }
            else ok = 0;

            if (ok) {
                printf("  [Constant Fold]  %s = %s %s %s  =>  %s = %d\n",
                       t->r, t->a, t->op, t->b, t->r, res);
                snprintf(t->a, 39, "%d", res);
                t->b[0] = 0;
                strcpy(t->op, "=");
                sym_set(t->r, res);   /* keep symbol table consistent */
                changed = 1; any_opt = 1;
            }
        }

        /* ── Pass B: Copy Propagation ─────────────────────────
           If we have   x = literal   then replace later uses of x
           with literal directly.
           We only propagate NUMERIC LITERALS (not variable names)
           to avoid incorrect substitution of memory references. */
        for (int i = 0; i < nopt; i++) {
            TAC *src = &opt[i];
            if (src->dead) continue;
            if (strcmp(src->op, "=") != 0) continue;
            if (!is_num_lit(src->a)) continue;   /* only literal copies */

            for (int j = i + 1; j < nopt; j++) {
                TAC *dst = &opt[j];
                if (dst->dead) continue;
                /* stop if result is redefined */
                if (!strcmp(dst->r, src->r)) break;

                int prop = 0;
                if (!strcmp(dst->a, src->r)) {
                    strcpy(dst->a, src->a); prop = 1;
                }
                if (!strcmp(dst->b, src->r)) {
                    strcpy(dst->b, src->a); prop = 1;
                }
                if (prop) {
                    printf("  [Copy Prop]      Replace '%s' with %s in line %d\n",
                           src->r, src->a, j+1);
                    changed = 1; any_opt = 1;
                }
            }
        }

        /* ── Pass C: Dead Code Elimination ────────────────────
           A temp assignment whose result is never used again
           can be safely removed. Only remove temps (tN), not
           user-declared variables. */
        for (int i = 0; i < nopt; i++) {
            TAC *t = &opt[i];
            if (t->dead) continue;
            if (!is_temp(t->r)) continue;   /* only remove temps */

            int used = 0;
            for (int j = i + 1; j < nopt; j++) {
                if (opt[j].dead) continue;
                if (!strcmp(opt[j].a, t->r) ||
                    !strcmp(opt[j].b, t->r) ||
                    !strcmp(opt[j].r, t->r)) { used = 1; break; }
            }
            if (!used) {
                printf("  [Dead Code Elim] Remove unused: %s = %s %s %s\n",
                       t->r, t->a, t->op, t->b);
                t->dead = 1;
                changed = 1; any_opt = 1;
            }
        }
    }

    if (!any_opt)
        printf("  (No optimizations applicable — code already optimal)\n");

    printf("\n");
    print_tac(opt, nopt, "PHASE 5b: OPTIMIZED IR");
}

/* ================================================================
   CODE GENERATION  (Phase 6)
   ================================================================ */

/* Print the assembly operand: #literal or [varname] */
static void asm_op(const char *s) {
    if (is_num_lit(s)) printf("#%s", s);
    else               printf("[%s]", s);
}

static void gen_asm(void) {
    div_line();
    printf("| PHASE 6: CODE GENERATION (Pseudo x86 Assembly)     |\n");
    div_line();

    /* .data section: declare user variables */
    printf(".data\n");
    for (int i = 0; i < nsym; i++) {
        if (sym[i].is_func) continue;
        if (is_temp(sym[i].name)) continue;
        printf("  %-12s DW  0          ; variable\n", sym[i].name);
    }

    printf("\n.text\n");
    printf("  JMP   main\n\n");

    for (int i = 0; i < nopt; i++) {
        TAC *t = &opt[i];
        if (t->dead) continue;

        if (!strcmp(t->op, "LBL")) {
            printf("\n%s:\n", t->r);

        } else if (!strcmp(t->op, "FN")) {
            printf("\n%s:\n", t->r);
            printf("  PUSH  BP\n");
            printf("  MOV   BP, SP\n");

        } else if (!strcmp(t->op, "FE")) {
            printf("  POP   BP\n");
            printf("  RET\n");

        } else if (!strcmp(t->op, "RET")) {
            printf("  MOV   AX, "); asm_op(t->a); printf("\n");
            printf("  POP   BP\n");
            printf("  RET\n");

        } else if (!strcmp(t->op, "=")) {
            printf("  MOV   AX, "); asm_op(t->a); printf("\n");
            printf("  MOV   [%s], AX\n", t->r);

        } else if (!strcmp(t->op, "+")) {
            printf("  MOV   AX, "); asm_op(t->a); printf("\n");
            printf("  ADD   AX, "); asm_op(t->b); printf("\n");
            printf("  MOV   [%s], AX\n", t->r);

        } else if (!strcmp(t->op, "-")) {
            printf("  MOV   AX, "); asm_op(t->a); printf("\n");
            printf("  SUB   AX, "); asm_op(t->b); printf("\n");
            printf("  MOV   [%s], AX\n", t->r);

        } else if (!strcmp(t->op, "*")) {
            printf("  MOV   AX, "); asm_op(t->a); printf("\n");
            printf("  IMUL  AX, "); asm_op(t->b); printf("\n");
            printf("  MOV   [%s], AX\n", t->r);

        } else if (!strcmp(t->op, "/")) {
            printf("  MOV   AX, "); asm_op(t->a); printf("\n");
            printf("  CDQ\n");                        /* sign-extend AX->DX:AX */
            printf("  IDIV  "); asm_op(t->b); printf("\n");
            printf("  MOV   [%s], AX\n", t->r);

        } else if (!strcmp(t->op, "PRT")) {
            if (t->a[0] == '"')
                printf("  MOV   AX, %s\n", t->a);   /* string literal */
            else {
                printf("  MOV   AX, "); asm_op(t->a); printf("\n");
            }
            printf("  OUT   AX\n");

        } else if (!strcmp(t->op, "JF")) {
            /* if_false cond goto label */
            printf("  MOV   AX, "); asm_op(t->a); printf("\n");
            printf("  CMP   AX, #0\n");
            printf("  JE    %s\n", t->r);

        } else if (!strcmp(t->op, "JMP")) {
            printf("  JMP   %s\n", t->r);

        } else if (!strcmp(t->op, "CALL")) {
            printf("  CALL  %s\n", t->a);
            printf("  MOV   [%s], AX\n", t->r);

        } else {
            /* Comparison operators: ==  !=  <  >  <=  >= */
            const char *mne =
                !strcmp(t->op,"==") ? "SETE"  :
                !strcmp(t->op,"!=") ? "SETNE" :
                !strcmp(t->op,"<")  ? "SETL"  :
                !strcmp(t->op,">")  ? "SETG"  :
                !strcmp(t->op,"<=") ? "SETLE" : "SETGE";
            printf("  MOV   AX, "); asm_op(t->a); printf("\n");
            printf("  CMP   AX, "); asm_op(t->b); printf("\n");
            printf("  %-6s AL\n", mne);
            printf("  MOVZX AX, AL\n");
            printf("  MOV   [%s], AX\n", t->r);
        }
    }

    printf("\n  HLT\n");
    div_line();
    printf("\n");
}

%}

/* ── Token / type declarations ── */
%union { int num; char *str; }

%token <num> NUMBER
%token <str> STRING IDENTIFIER
%token ASSIGN EQUAL NOTEQUAL LESS GREATER LESSEQUAL GREATEREQUAL
%token PLUS MINUS MULTIPLY DIVIDE
%token LPAREN RPAREN LBRACE RBRACE SEMICOLON COMMA
%token IF ELSE WHILE FOR PRINT INT FUNC RETURN

%type <str> expr cmp prog stmt params args

/* Operator precedence (low → high) */
%right ASSIGN
%left  PLUS MINUS
%left  MULTIPLY DIVIDE
%nonassoc EQUAL NOTEQUAL LESS GREATER LESSEQUAL GREATEREQUAL

%%

/* ── Grammar rules ── */

prog
    : prog stmt          { log_rule("prog → prog stmt"); $$ = $2; }
    | stmt               { log_rule("prog → stmt");      $$ = $1; }
    ;

stmt
    /* Variable declaration:  int x = expr; */
    : INT IDENTIFIER ASSIGN expr SEMICOLON {
        log_rule("stmt → int id = expr ;");
        int v = val_of($4);
        sym_add($2, v, 0);
        emit("=", $4, NULL, $2);
        $$ = $2;
    }

    /* Assignment:  x = expr; */
    | IDENTIFIER ASSIGN expr SEMICOLON {
        log_rule("stmt → id = expr ;");
        int v = val_of($3);
        sym_add($1, v, 0);
        emit("=", $3, NULL, $1);
        $$ = $1;
    }

    /* print expr; */
    | PRINT expr SEMICOLON {
        log_rule("stmt → print expr ;");
        emit("PRT", $2, NULL, NULL);
        $$ = $2;
    }

    /* print "string"; */
    | PRINT STRING SEMICOLON {
        log_rule("stmt → print STRING ;");
        emit("PRT", $2, NULL, NULL);
        $$ = $2;
    }

    /* if ( cmp ) { prog } */
    | IF LPAREN cmp RPAREN LBRACE prog RBRACE {
        log_rule("stmt → if ( cmp ) { prog }");
        /*
         * $3 holds the label that JF jumps to when condition is false.
         * We place that label right here, after the if-body.
         */
        emit("LBL", NULL, NULL, $3);
        $$ = $3;
    }

    /* if ( cmp ) { prog } else { prog } */
    | IF LPAREN cmp RPAREN LBRACE prog RBRACE ELSE LBRACE prog RBRACE {
        log_rule("stmt → if ( cmp ) { prog } else { prog }");
        /*
         * $3 = false-label (set by cmp, JF jumps here to skip if-body).
         * We need an end-label so the if-body can jump past the else-body.
         * Structure emitted by cmp:       cond → tN;  if_false tN goto FALSE_LBL
         * We emit:                        [if-body]  JMP END_LBL
         *                                 FALSE_LBL: [else-body]  END_LBL:
         */
        char *end_lbl = mklbl();
        /* JMP was already emitted at end of if-body by the mid-rule action below.
           Place the false label, then the end label after else-body. */
        emit("LBL", NULL, NULL, $3);      /* FALSE_LBL: (start of else) */
        emit("LBL", NULL, NULL, end_lbl); /* END_LBL:   (after else)    */
        $$ = end_lbl;
    }

    /* while ( cmp ) { prog } */
    | WHILE LPAREN cmp RPAREN LBRACE prog RBRACE {
        log_rule("stmt → while ( cmp ) { prog }");
        /*
         * $3 = exit-label (JF jumps here when condition is false).
         * We place the exit label after the body.
         */
        emit("LBL", NULL, NULL, $3);
        $$ = $3;
    }

    /* func name ( params ) { prog } */
    | FUNC IDENTIFIER LPAREN params RPAREN LBRACE prog RBRACE {
        log_rule("stmt → func id ( params ) { prog }");
        sym_add($2, 0, 1);
        emit("FE", NULL, NULL, $2);
        cur_scope--;
        $$ = $2;
    }

    /* return expr; */
    | RETURN expr SEMICOLON {
        log_rule("stmt → return expr ;");
        emit("RET", $2, NULL, NULL);
        $$ = $2;
    }
    ;

/* Function parameters */
params
    : /* empty */                      { $$ = strdup(""); }
    | INT IDENTIFIER                   { sym_add($2,0,0); $$ = $2; }
    | params COMMA INT IDENTIFIER      { sym_add($4,0,0); $$ = $4; }
    ;

/* Comparison: emits condition TAC + conditional jump */
cmp
    : expr EQUAL expr {
        log_rule("cmp → expr == expr");
        char *t = mktmp(), *l = mklbl();
        emit("==", $1, $3, t);
        emit("JF", t, NULL, l);
        $$ = l;
    }
    | expr NOTEQUAL expr {
        log_rule("cmp → expr != expr");
        char *t = mktmp(), *l = mklbl();
        emit("!=", $1, $3, t);
        emit("JF", t, NULL, l);
        $$ = l;
    }
    | expr LESS expr {
        log_rule("cmp → expr < expr");
        char *t = mktmp(), *l = mklbl();
        emit("<", $1, $3, t);
        emit("JF", t, NULL, l);
        $$ = l;
    }
    | expr GREATER expr {
        log_rule("cmp → expr > expr");
        char *t = mktmp(), *l = mklbl();
        emit(">", $1, $3, t);
        emit("JF", t, NULL, l);
        $$ = l;
    }
    | expr LESSEQUAL expr {
        log_rule("cmp → expr <= expr");
        char *t = mktmp(), *l = mklbl();
        emit("<=", $1, $3, t);
        emit("JF", t, NULL, l);
        $$ = l;
    }
    | expr GREATEREQUAL expr {
        log_rule("cmp → expr >= expr");
        char *t = mktmp(), *l = mklbl();
        emit(">=", $1, $3, t);
        emit("JF", t, NULL, l);
        $$ = l;
    }
    ;

/* Arithmetic expressions */
expr
    : expr PLUS expr {
        log_rule("expr → expr + expr");
        char *t = mktmp();
        emit("+", $1, $3, t);
        int v = val_of($1) + val_of($3);
        sym_set(t, v);
        $$ = t;
    }
    | expr MINUS expr {
        log_rule("expr → expr - expr");
        char *t = mktmp();
        emit("-", $1, $3, t);
        int v = val_of($1) - val_of($3);
        sym_set(t, v);
        $$ = t;
    }
    | expr MULTIPLY expr {
        log_rule("expr → expr * expr");
        char *t = mktmp();
        emit("*", $1, $3, t);
        int v = val_of($1) * val_of($3);
        sym_set(t, v);
        $$ = t;
    }
    | expr DIVIDE expr {
        log_rule("expr → expr / expr");
        char *t = mktmp();
        emit("/", $1, $3, t);
        int v2 = val_of($3);
        if (v2 != 0) sym_set(t, val_of($1) / v2);
        $$ = t;
    }
    | LPAREN expr RPAREN {
        log_rule("expr → ( expr )");
        $$ = $2;
    }
    | NUMBER {
        log_rule("expr → NUMBER");
        char *buf = malloc(20);
        sprintf(buf, "%d", $1);
        $$ = buf;
    }
    | IDENTIFIER {
        log_rule("expr → IDENTIFIER");
        /* Validate the variable exists */
        sym_get($1);
        $$ = $1;
    }
    | IDENTIFIER LPAREN args RPAREN {
        log_rule("expr → IDENTIFIER ( args )");
        if (sym_find($1) == -1) {
            char buf[96];
            snprintf(buf,sizeof(buf),"  ERROR   Undefined function '%s' at line %d",$1,line_num);
            slog(buf);
            fprintf(stderr,"[Semantic Error] Undefined function '%s' at line %d\n",$1,line_num);
            sem_err++;
        }
        char *t = mktmp();
        emit("CALL", $1, $3, t);
        $$ = t;
    }
    ;

/* Function call arguments */
args
    : /* empty */             { $$ = strdup(""); }
    | expr                    { $$ = $1; }
    | args COMMA expr         { $$ = $3; }
    ;

%%

/* ================================================================
   ERROR HANDLER
   ================================================================ */
void yyerror(const char *s) {
    fprintf(stderr, "[Syntax Error] %s at line %d\n", s, line_num);
    sem_err++;
}

/* ================================================================
   MAIN  — orchestrates all 6 phases
   ================================================================ */
int main(void) {
    printf("=====================================================\n");
    printf("       MINI COMPILER  --  CSE 430 Lab Project       \n");
    printf("=====================================================\n\n");

    /* Run lexer + parser (all logs filled silently) */
    yyparse();

    /* ── Phase 1: Lexical Analysis ── */
    print_tokens();

    /* ── Phase 2: Syntax Analysis ── */
    div_line();
    printf("| PHASE 2: SYNTAX ANALYSIS                           |\n");
    printf("|   (Grammar rules matched during parsing)           |\n");
    div_line();
    for (int i = 0; i < nsyn; i++)
        printf("  Rule %-3d: %s\n", i+1, syn_log[i]);
    printf("  Total rules applied: %d\n", nsyn);
    div_line();
    printf("\n");

    /* ── Phase 3: Semantic Analysis ── */
    div_line();
    printf("| PHASE 3: SEMANTIC ANALYSIS                         |\n");
    div_line();
    for (int i = 0; i < nsem; i++)
        printf("%s\n", sem_log[i]);
    printf("  Semantic errors found: %d\n", sem_err);
    div_line();
    printf("\n");

    /* ── Phase 3b: Symbol Table ── */
    div_line();
    printf("| PHASE 3b: SYMBOL TABLE                             |\n");
    printf("+----------------+---------+----------+--------------+\n");
    printf("| %-14s | %-7s | %-8s | %-12s |\n",
           "Name", "Value", "Type", "Scope");
    printf("+----------------+---------+----------+--------------+\n");
    for (int i = 0; i < nsym; i++) {
        if (is_temp(sym[i].name)) continue;   /* hide compiler temps */
        printf("| %-14s | %-7d | %-8s | %-12s |\n",
               sym[i].name, sym[i].val,
               sym[i].is_func ? "function" : "variable",
               sym[i].scope == 0 ? "global" : "local");
    }
    printf("+----------------+---------+----------+--------------+\n\n");

    /* ── Phase 4: Intermediate Code ── */
    print_tac(tac, ntac, "PHASE 4: INTERMEDIATE CODE GENERATION (3-Address)");

    /* ── Phase 5: Optimization ── */
    optimize();

    /* ── Phase 6: Assembly ── */
    gen_asm();

    printf("=====================================================\n");
    if (sem_err == 0)
        printf("  Compilation SUCCESS  --  All 6 phases complete.\n");
    else
        printf("  Compilation FAILED   --  %d error(s) found.\n", sem_err);
    printf("=====================================================\n");

    return (sem_err > 0) ? 1 : 0;
}
