Int FacI ( Int n )
{	Int r = 1;
		while ( n > 1 )
		{	r = r * n;
			n = n - 1;
		}
	return r;
}
