# CMAKE generated file: DO NOT EDIT!
# Generated by "Unix Makefiles" Generator, CMake Version 3.25

# Delete rule output on recipe failure.
.DELETE_ON_ERROR:

#=============================================================================
# Special targets provided by cmake.

# Disable implicit rules so canonical targets will work.
.SUFFIXES:

# Disable VCS-based implicit rules.
% : %,v

# Disable VCS-based implicit rules.
% : RCS/%

# Disable VCS-based implicit rules.
% : RCS/%,v

# Disable VCS-based implicit rules.
% : SCCS/s.%

# Disable VCS-based implicit rules.
% : s.%

.SUFFIXES: .hpux_make_needs_suffix_list

# Command-line flag to silence nested $(MAKE).
$(VERBOSE)MAKESILENT = -s

#Suppress display of executed commands.
$(VERBOSE).SILENT:

# A target that is always out of date.
cmake_force:
.PHONY : cmake_force

#=============================================================================
# Set environment variables for the build.

# The shell in which to execute make rules.
SHELL = /bin/sh

# The CMake executable.
CMAKE_COMMAND = /snap/cmake/1216/bin/cmake

# The command to remove a file.
RM = /snap/cmake/1216/bin/cmake -E rm -f

# Escaping for special characters.
EQUALS = =

# The top-level source directory on which CMake was run.
CMAKE_SOURCE_DIR = /home/liyi/programs/homepage/Maktiny.github.io/docs/tips/learn_makefile/cmake

# The top-level build directory on which CMake was run.
CMAKE_BINARY_DIR = /home/liyi/programs/homepage/Maktiny.github.io/docs/tips/learn_makefile/cmake/build

# Include any dependencies generated for this target.
include src/CMakeFiles/mathfunction.dir/depend.make
# Include any dependencies generated by the compiler for this target.
include src/CMakeFiles/mathfunction.dir/compiler_depend.make

# Include the progress variables for this target.
include src/CMakeFiles/mathfunction.dir/progress.make

# Include the compile flags for this target's objects.
include src/CMakeFiles/mathfunction.dir/flags.make

src/CMakeFiles/mathfunction.dir/math.c.o: src/CMakeFiles/mathfunction.dir/flags.make
src/CMakeFiles/mathfunction.dir/math.c.o: /home/liyi/programs/homepage/Maktiny.github.io/docs/tips/learn_makefile/cmake/src/math.c
src/CMakeFiles/mathfunction.dir/math.c.o: src/CMakeFiles/mathfunction.dir/compiler_depend.ts
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green --progress-dir=/home/liyi/programs/homepage/Maktiny.github.io/docs/tips/learn_makefile/cmake/build/CMakeFiles --progress-num=$(CMAKE_PROGRESS_1) "Building C object src/CMakeFiles/mathfunction.dir/math.c.o"
	cd /home/liyi/programs/homepage/Maktiny.github.io/docs/tips/learn_makefile/cmake/build/src && /usr/bin/cc $(C_DEFINES) $(C_INCLUDES) $(C_FLAGS) -MD -MT src/CMakeFiles/mathfunction.dir/math.c.o -MF CMakeFiles/mathfunction.dir/math.c.o.d -o CMakeFiles/mathfunction.dir/math.c.o -c /home/liyi/programs/homepage/Maktiny.github.io/docs/tips/learn_makefile/cmake/src/math.c

src/CMakeFiles/mathfunction.dir/math.c.i: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Preprocessing C source to CMakeFiles/mathfunction.dir/math.c.i"
	cd /home/liyi/programs/homepage/Maktiny.github.io/docs/tips/learn_makefile/cmake/build/src && /usr/bin/cc $(C_DEFINES) $(C_INCLUDES) $(C_FLAGS) -E /home/liyi/programs/homepage/Maktiny.github.io/docs/tips/learn_makefile/cmake/src/math.c > CMakeFiles/mathfunction.dir/math.c.i

src/CMakeFiles/mathfunction.dir/math.c.s: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Compiling C source to assembly CMakeFiles/mathfunction.dir/math.c.s"
	cd /home/liyi/programs/homepage/Maktiny.github.io/docs/tips/learn_makefile/cmake/build/src && /usr/bin/cc $(C_DEFINES) $(C_INCLUDES) $(C_FLAGS) -S /home/liyi/programs/homepage/Maktiny.github.io/docs/tips/learn_makefile/cmake/src/math.c -o CMakeFiles/mathfunction.dir/math.c.s

# Object files for target mathfunction
mathfunction_OBJECTS = \
"CMakeFiles/mathfunction.dir/math.c.o"

# External object files for target mathfunction
mathfunction_EXTERNAL_OBJECTS =

src/libmathfunction.a: src/CMakeFiles/mathfunction.dir/math.c.o
src/libmathfunction.a: src/CMakeFiles/mathfunction.dir/build.make
src/libmathfunction.a: src/CMakeFiles/mathfunction.dir/link.txt
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green --bold --progress-dir=/home/liyi/programs/homepage/Maktiny.github.io/docs/tips/learn_makefile/cmake/build/CMakeFiles --progress-num=$(CMAKE_PROGRESS_2) "Linking C static library libmathfunction.a"
	cd /home/liyi/programs/homepage/Maktiny.github.io/docs/tips/learn_makefile/cmake/build/src && $(CMAKE_COMMAND) -P CMakeFiles/mathfunction.dir/cmake_clean_target.cmake
	cd /home/liyi/programs/homepage/Maktiny.github.io/docs/tips/learn_makefile/cmake/build/src && $(CMAKE_COMMAND) -E cmake_link_script CMakeFiles/mathfunction.dir/link.txt --verbose=$(VERBOSE)

# Rule to build all files generated by this target.
src/CMakeFiles/mathfunction.dir/build: src/libmathfunction.a
.PHONY : src/CMakeFiles/mathfunction.dir/build

src/CMakeFiles/mathfunction.dir/clean:
	cd /home/liyi/programs/homepage/Maktiny.github.io/docs/tips/learn_makefile/cmake/build/src && $(CMAKE_COMMAND) -P CMakeFiles/mathfunction.dir/cmake_clean.cmake
.PHONY : src/CMakeFiles/mathfunction.dir/clean

src/CMakeFiles/mathfunction.dir/depend:
	cd /home/liyi/programs/homepage/Maktiny.github.io/docs/tips/learn_makefile/cmake/build && $(CMAKE_COMMAND) -E cmake_depends "Unix Makefiles" /home/liyi/programs/homepage/Maktiny.github.io/docs/tips/learn_makefile/cmake /home/liyi/programs/homepage/Maktiny.github.io/docs/tips/learn_makefile/cmake/src /home/liyi/programs/homepage/Maktiny.github.io/docs/tips/learn_makefile/cmake/build /home/liyi/programs/homepage/Maktiny.github.io/docs/tips/learn_makefile/cmake/build/src /home/liyi/programs/homepage/Maktiny.github.io/docs/tips/learn_makefile/cmake/build/src/CMakeFiles/mathfunction.dir/DependInfo.cmake --color=$(COLOR)
.PHONY : src/CMakeFiles/mathfunction.dir/depend

