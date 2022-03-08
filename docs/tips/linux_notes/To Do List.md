# To Do List

### call return 优化

1. 维护一个栈（数组），存放SPC和TPC，call入栈，return出栈
2. 栈大小实验确定， 

#### indirect imp优化

1. 也使用两个寄存器来缓存SPC和TPC
2. 

# Hot code

1. NET算法：通过tb_lookup()查找的TB块为头块(profile 置为1)，如果profile == 1，开始count计数，count > threashold 调用helper_superblock()函数，把热路径合并成超级块

```c
if (profile == 1 )
        count++;
        if(count > threashold)
              go helper_superblock()
              
              
 helper_superblock() 遍历TB链，把TB 前面插桩 和 后面处理跳转的代码 去掉，变成一个超级块。
 超级块优化之后存储在内存中，也是用jmp_hash_cache[]的方法索引， 在tb_find()函数调用tb_lookup()之前调用他。
```

2. 一般helper_superblock()太重，可以把头块放到队列里，触发另一函数，让另一个函数区处理优化的工作。
3. 优化好之后放到jmp_hash_cache中。