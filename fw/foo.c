int xx[10];		// uninitialized - goes into .bss
int yy = 0x12345678;	// initialized - goes into .data

char qq = 0xe;

int goo()
{
	return yy * qq;
}

int mains()
{
	int z = 456;
	xx[1] = 10;

	xx[1] -= z;
	goo();

	return xx[1] + z;
}
