all: minicompiler

minicompiler: parser.tab.c parser.tab.h lex.yy.c
	gcc -o minicompiler parser.tab.c lex.yy.c -lfl -w

parser.tab.c parser.tab.h: parser.y
	bison -d parser.y

lex.yy.c: lexer.l parser.tab.h
	flex lexer.l

clean:
	rm -f minicompiler parser.tab.c parser.tab.h lex.yy.c

.PHONY: all clean
