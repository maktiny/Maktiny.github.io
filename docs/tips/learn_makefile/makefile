#files = file1 file2 
#some_file: $(files)
#	echo "look at this variable: "$(files)
#	touch some_file


#file1:
#	touch file1

#file2:
#	touch file2

#clean:
#rm -f file1 file2 some_file

#x = dule
#all:
#	echo $(x)
#	echo ${x}
#	echo $x
#	
objects = foo.o bar.o all.o
all: $(objects)

# These files compile via implicit rules
# Syntax - targets ...: target-pattern: prereq-patterns ...
# In the case of the first target, foo.o, the target-pattern matches foo.o and sets the "stem" to be "foo".
# It then replaces the '%' in prereq-patterns with that stem
$(objects): %.o: %.c

all.c:
	echo "int main() { return 0; }" > all.c

%.c:
	touch $@

clean:
	rm -f *.c *.o all
