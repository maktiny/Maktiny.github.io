## slab分配器
1. 伙伴系统分配以页为单位，如果需要更小的内存分配使用slab,slab最终使用伙伴系统来
分配物理页面，只不过alsb分配器在物理页面上实现自己的机制，然后管理小内存。
slab分配器在创建的不分配物理内存，只有在分配slab对象的时候，没有空闲对象的时候才分配物理内存
2. slab机制创建了多层缓冲池：共享对象缓冲池和每个CPU对象缓冲池
3. linux内核实现三种slab分配器机制
* slab机制：一般的操作系统
* slub机制：使用在大型系统中，性能比slab更好
* slob机制：slob机制适合嵌入式系统


```
//创建slab描述符
struct kmem_cache *
kmem_cache_create(const char *name, unsigned int size, unsigned int align,
		slab_flags_t flags, void (*ctor)(void *))

//释放slab描述符
void kmem_cache_destroy(struct kmem_cache *s)

//分配缓存对象
void *kmem_cache_alloc(struct kmem_cache *s, gfp_t gfpflags)

//释放缓存对象
void kmem_cache_free(struct kmem_cache *s, void *x)


  //slab描述符
struct kmem_cache {
	struct kmem_cache_cpu __percpu *cpu_slab; //kmem_cache_cpu->freelist指向本地对象缓冲池（array_acche）
	/* Used for retrieving partial slabs, etc. */
	slab_flags_t flags;
	unsigned long min_partial;
	unsigned int size;	/* The size of an object including metadata */
	unsigned int object_size;/* The size of an object without metadata */
	struct reciprocal_value reciprocal_size;
	unsigned int offset;	/* Free pointer offset */
#ifdef CONFIG_SLUB_CPU_PARTIAL
	/* Number of per cpu partial objects to keep around */
	unsigned int cpu_partial;
#endif
	struct kmem_cache_order_objects oo;

	/* Allocation and freeing of slabs */
	struct kmem_cache_order_objects max;
	struct kmem_cache_order_objects min;
	gfp_t allocflags;	/* gfp flags to use on each alloc */
	int refcount;		/* Refcount for slab cache destroy */
	void (*ctor)(void *);
	unsigned int inuse;		/* Offset to metadata */
	unsigned int align;		/* Alignment */
	unsigned int red_left_pad;	/* Left redzone padding size */
	const char *name;	/* Name (only for display!) */
	struct list_head list;	/* List of slab caches */
	
.....................................

  unsigned int useroffset;	/* Usercopy region offset */
	unsigned int usersize;		/* Usercopy region size */

	struct kmem_cache_node *node[MAX_NUMNODES];
};

//缓冲池结构体(本地对象缓冲池 共享对象缓冲池)
struct array_cache {
	unsigned int avail;
	unsigned int limit;
	unsigned int batchcount;
	unsigned int touched;
	void *entry[];	/*
			 * Must have this definition in here for the proper
			 * alignment of array_cache. Also simplifies accessing
			 * the entries.
			 */
};
```
4. 创建slab描述符(slab分配器)
 ```
    kmem_cache_create()
                |
             kmem_cache_create_usercopy()
                |
            __kmem_cache_alias()//判断是否可以复用现成的slab描述符------>create_cache()
                |                                                            |
                |                                                       __kmem_cache_creae()//创建一个slab描述符
            返回slab描述符                                                   |
                                                                            list_add()//添加到slab_cache链表中
                                                                                | 返回slab描述符
calculate_slab_order()函数用来计算slab分配器需要的页面数
```

5. 分配slab对象
```
   slab分配器创建slab对象的时候使用伙伴系统的借口分配物理页
   cache_alloc_refille()--->cache_grow_begin()--->kmem_getpages()--->__alloc_pages_node()分配物理页

   kmem_cache_alloc()
              |
          slab_alloc()
              |
            __do_cache_alloc()//如果本地/共享对象缓冲池
            中存在空闲的对象，会直接分配，否则
               |
              ____cache_alloc()
                |
            cache_alloc_refill()//否则从其他slab节点（kmem_cache_node)和其共享对象缓冲池
            中迁移一部分slab空闲对象到当前slab分配器进行分配，
                |
            cache_grow_begin()
            如果还是失败，则重新建一个slab分配器
               |
           alloc_block()//使用该函数把新建的slab分配器中空闲对象迁移到当前slab中进行分配
```

6. 释放slab缓存对象

```
     kmem_cache_free()
        |
      __cache_free()
        |
      ___cache_free()
         |
      cache_flusharray()//回收部分空闲对象或者销毁slab分配器
//本地对象缓冲池中的空闲对象 >limit(空闲对象的最大值)----->迁移到共享对象缓冲池中 >limit ----->迁移到其他salb节点  >limit 销毁slab分配器（和分配相反）

```
7. slab的管理区（管理空闲对象）
* slab管理区是一个数组freelist, 根据slab分配器的空间大小，管理区有三种分配方式

```
__kmem_cache_create()函数中的部分代码：
/*
  freelist小于一个slab对象的大小，把slab最后一个对象的空间作为freelist
  slab分配器的空间布局
  ----------------------------------------------------------
  |colour | colour | slab | slab | salb| slab(用作freelist) |    
  ---------------------------------------------------------
*/
if (set_objfreelist_slab_cache(cachep, size, flags)) {
		flags |= CFLGS_OBJFREELIST_SLAB;
		goto done;
	}

  /*
   salb分配器的剩余空间小于freelist, 则另外分配管理区
  slab分配器的空间布局
  -----------------------------------------------       --------
  |colour | colour | slab | slab | salb| slab   |       |管理区| 
  -----------------------------------------------       --------
*/
	if (set_off_slab_cache(cachep, size, flags)) {
		flags |= CFLGS_OFF_SLAB;
		goto done;
	}
  
  /* 剩余空间大于freelist 
  slab分配器的空间布局
  ----------------------------------------------------------
  |colour | colour | slab | slab | salb| (用作freelist)    |    
  ---------------------------------------------------------
*/

	if (set_on_slab_cache(cachep, size, flags))
		goto done;


```
8. kmalloc()
* 内核的kmalloc()函数实际上就是slab的机制，分配多少2 ** order字节的空间


```
终端： cd /proc 
       sudo  cat  slabinfo
就可以看到系统中salb信息

slab分配器名称      数量
kmalloc-4k          3205   3248   4096    8    8 : tunables    0    0    0 : slabdata    406    406      0
kmalloc-2k          6107   7440   2048   16    8 : tunables    0    0    0 : slabdata    465    465      0
kmalloc-1k          7262   8608   1024   32    8 : tunables    0    0    0 : slabdata    269    269      0
kmalloc-512        31995  35520    512   32    4 : tunables    0    0    0 : slabdata   1110   1110      0
kmalloc-256        13895  14752    256   32    2 : tunables    0    0    0 : slabdata    461    461      0
kmalloc-192        15939  18795    192   21    1 : tunables    0    0    0 : slabdata    895    895      0
kmalloc-128         4042   4384    128   32    1 : tunables    0    0    0 : slabdata    137    137      0
kmalloc-96          7367   8022     96   42    1 : tunables    0    0    0 : slabdata    191    191      0
kmalloc-64         34130  42688     64   64    1 : tunables    0    0    0 : slabdata    667    667      0
kmalloc-32        141184 141184     32  128    1 : tunables    0    0    0 : slabdata   1103   1103      0
kmalloc-16         18176  18176     16  256    1 : tunables    0    0    0 : slabdata     71     71      0
kmalloc-8          14336  14336      8  512    1 : tunables    0    0    0 : slabdata     28     28      0

```

