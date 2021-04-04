# ANSI Terminal
#
# (c) 2021 Steven A. Falco

all: divisors
	./divisors > divtable

divisors: divisors.c
	cc -o $@ $^ -lm
