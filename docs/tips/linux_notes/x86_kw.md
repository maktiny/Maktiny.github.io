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
