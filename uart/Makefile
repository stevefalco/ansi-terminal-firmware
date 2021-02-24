all: divtable

divtable: divisors
	./divisors > divtable

divisors: divisors.c
	cc -o $@ $^ -lm
