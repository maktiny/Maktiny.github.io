1. cache一致性协议
 MESI协议:
M(Modified)
这行数据有效，数据被修改了，和内存中的数据不一致，数据只存在于本Cache中。
E(Exclusive)
这行数据有效，数据和内存中的数据一致，数据只存在于本Cache中。
S(Shared)
这行数据有效，数据和内存中的数据一致，数据存在于很多Cache中。
I(Invalid)
这行数据无效。
[参考](https://blog.csdn.net/muxiqingyang/article/details/6615199)

2. 内存序：为了提高计算机的性能，编译器在编译程序的时候会对代码进行重排，
内存的排序既可能发生在编译器编译期间，也可能发生在 CPU 指令执行期间。
  内存屏障
3. 内存管理

4. 内核态和用户态的区别：内核态特权级0，可以使用特权指令；用户态特权级3，
  
5. malloc new brk mmeorymap
[参考](https://blog.csdn.net/weixin_39940770/article/details/110588878)
6. slab分配器，伙伴系统

7. c++ 偏特化模板：模板中的部分类型明确
 类模板和函数模板都可以被全特化；
 类模板能偏特化，不能被重载；
 函数模板全特化，不能被偏特化，可以重载。
 [参考](https://blog.csdn.net/lyn_00/article/details/83548629)
8. 构造析构
构造函数：建立对象时自动调用的函数
析构函数：对象的所有引用都被删除或者当对象被显式销毁时执行
[参考](https://baijiahao.baidu.com/s?id=1707202523649611541&wfr=spider&for=pc)
10. 多重继承,多继承

