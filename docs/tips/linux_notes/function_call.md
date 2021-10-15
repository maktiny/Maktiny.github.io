# Function Calling Seauence 

## 函数调用协议
1. __stdcall: Windows API默认的函数调用协议，函数参数由右向左入栈
   函数调用结束之后，由callee清除栈内数据

2. __cdecl: C/C++的默认函数调用协议，函数参数由右向左入栈
   函数调用结束之后，由caller清除栈内数据

3. __fastcall:从左开始,参数放在寄存器中，其他参数从右到左入栈
   函数调用结束之后，由callee清除栈内数据

除了Windows之外,x86_64的OS都使用System V psABI标准,也就是fastcall函数调用协议


## System V psABI-i386

### Passing Parameter

32位的大部分参数都是通过栈来传递的，一些列外：
1. 首先从左到右三个__m64类型的参数通过%mm0, %mm1, %mm2来传递，其他的通过栈来传递
2. 首先从左到右三个__m128类型的参数通过%xmm0, %xmm1, %xmm2来传递，其他的通过栈来传递
3. 首先从左到右三个__m256类型的参数通过%ymm0, %ymm1, %ymm2来传递，其他的通过栈来传递
如果%ymm0的低128位%xmm0被占用，使用%ymm1

32位寄存器在函数传参中的使用
![](http://tva1.sinaimg.cn/large/0070vHShgy1gv886gry7hj60l60nkwji02.jpg)

### Return Value
![](http://tva1.sinaimg.cn/large/0070vHShgy1gv8t3h0iodj60kz0katco02.jpg)

### example
![2021-10-09 09-36-15 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShgy1gv8t5xlg8lj60hm0jmq4s02.jpg)

## System V psABI-x86_64

### The stack frame
```
long myfunc(long a, long b, long c, long d,
            long e, long f, long g, long h)
{
    long xx = a * b * c * d * e * f * g * h;
    long yy = a + b + c + d + e + f + g + h;
    long zz = utilfunc(xx, yy, xx % yy);
    return zz + 20;
}
```
```
long utilfunc(long a, long b, long c)
{
    long xx = a + 2;
    long yy = b + 3;
    long zz = c + 4;
    long sum = xx + yy + zz;

    return xx * yy * zz + sum;
}
``` 
![](http://tva1.sinaimg.cn/large/0070vHShgy1gv8t1pmzs4j60gb09yaaq02.jpg#pic_left =587x358)
![](http://tva1.sinaimg.cn/large/0070vHShgy1gv8szkqzw7j60g909uwf502.jpg#pic_right =585x384)


#### Red Zone
red zone 不会被信号量和中断处理器修改，所以可以用来存储函数的临时数据，可以用作优化的目的
，特别是叶节点函数可以用来存储局部数据，不需要使用栈来存储。


### Parameter Passing
| Type                            | Classfication  | Passing              |
| :-----------------------------: | :------------: | :------------------: |
| _Bool,char,short,int,long,long long,__int128 | INTEGER | %rdi,%rsi,%rdx,%rcx,%r8,%r9 |
| float,double,_Decimal32,_Decimal64,_m64 | SSE | %xmm0-%xmm7 |
| __float128,_Decimal128,__m128,__m256,__m512 | SSEUP | 对应的%ymm0-%ymm15,%zmm0-%zmm31 |
| long double,复数 | X87，X87UP, COMPLES_X87 | 栈传递 |


注：当出现可变长参数列表的时候，%al被用来指明参数列表所使用的寄存器的数量
，不必精确，但是有上限，范围0-8
```
Test(unsigned int n, ...)
```

### Return Values
| Type                            | Classfication  | Return              |
| :-----------------------------: | :------------: | :------------------: |
| _Bool,char,short,int,long,long long,__int128 | INTEGER | %rax,%rdx |
| float,double,_Decimal32,_Decimal64,_m64 | SSE | %xmm0,%xmm1 |
| __float128,_Decimal128,__m128,__m256,__m512 | SSEUP | 顺序找一个未使用的寄存器 |
| long double,复数 | X87，X87UP, COMPLES_X87 | %st0, %st1 |

### 寄存器使用简介
![2021-10-09 14-49-30 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShgy1gv927rybfhj60le0owq9n02.jpg)

### example
![2021-10-09 14-50-47 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShgy1gv92byk8udj60k30n1wh802.jpg)

