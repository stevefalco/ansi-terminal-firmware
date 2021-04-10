void
main()
{
	volatile char *pControl = (volatile char *)0x0000c060;

	// Enable video sync
	*pControl = 1;
}
