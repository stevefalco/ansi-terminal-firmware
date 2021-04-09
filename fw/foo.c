int xx;			// uninitialized - goes into .bss
int yy = 0x1234;	// initialized - goes into .data

int goo()
{
	return yy;
}

int mains()
{
	int z = 456;
	xx = 10;

	xx -= z;
	goo();

	return xx + z;
}
