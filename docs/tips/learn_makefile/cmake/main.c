#include <stdio.h>
#include "config.h"
#ifdef USE_MYFUNCTION
	#include "math.h"
#else
	#include <math.h>
#endif

int main() {

	printf("hello cmake\n");
#ifdef USE_MYFUNCTION
	printf("use my function add\n");
	add(2,3);
#else
	printf("lib function\n");
#endif 
	return 0;
}
