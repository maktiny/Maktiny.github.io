# some programing tips
1. #define functionname (参数){()} 使用这种方式把函数封装成为宏，{()}中最后一条语句的执行结果为其返回值
   ，宏在编译器编译的时候被替换，函数宏不能进行参数类型检查，不可调试，而inline可以

2. lazy TLB：当普通进程切换到内核线程的时候，进入 lazy TLB 模式，内核线程切换出来，切出lazy TLB 模式，内核线程访问内核地址空间
，不能访问用户态地址空间，因此不需要刷新TLB. 在SMP情况下，IPI(核间中断)会是当前cpu刷新一次TLB(数据一致性)，之后不刷新TLB.

3. static 函数或者变量限制了其作用域只在该源文件，即只在定义该变量或者函数的源文件内有效.

4.  __thread变量每一个线程有一份独立实体，各个线程的值互不干扰

5. 希望在头文件中定义一个全局变量，然后包含到两个不同的c文件中，希望这个全局变量能在两个文件中共用

```c

//（1）main.c文件

 　#include "common.h"
　 unsigned char key;
 

　//　（2）common.c文件：

 　#include "common.h"
　 extern unsigned char key;
```

6. 防止一个头文件被重复包含
```c

#ifndef COMDEF_H
#define COMDEF_H

//头文件内容 …
#endif

```

7.  当定义了_DEBUG，输出数据信息和所在文件所在行
```c

#ifdef _DEBUG
#define DEBUGMSG(msg,date) printf(msg);printf(“%d%d%d”,date,_LINE_,_FILE_)
#else
#define DEBUGMSG(msg,date)
#endif
```
8. 用#把宏参数变为一个字符串,用##把两个宏参数贴合在一起

```c
＃include<cstdio>
＃include<climits>
using namespace std;

#define STR(s)     #s
#define CONS(a,b)  int(a##e##b)

int main()

{
printf(STR(vck));               // 输出字符串vck
printf(%dn, CONS(2,3));  // 2e3 输出:2000
return 0;
}

```
9. glibc和libc都是Linux下的C函数库，libc是Linux下的ANSI C的函数库；
glibc是Linux下的GUN C的函数库；GNU C是一种ANSI C的扩展实现

10. uClibc 是一个面向嵌入式Linux系统的小型的C标准库。最初uClibc是为了支持uClinux而开发，这是一个不需要内存管理单元（MMU）的Linux版本。
uClibc比一般用于Linux发行版的C库GNU C Library (glibc)要小得多， uClibc专注于嵌入式Linux。很多功能可以根据空间需求进行取舍。

11. Newlib是一个面向嵌入式系统的C运行库。最初是由Cygnus Solutions收集组装的一个源代码集合，取名为newlib，现在由Red Hat维护
Newlib并不是唯一的选择，但是从成熟度来讲，newlib是最优秀的, 相比Minilibc更加健全
