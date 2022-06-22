## slab分配器
1. 伙伴系统分配以页为单位，如果需要更小的内存分配使用slab,slab最终使用伙伴系统来
分配物理页面，只不过slab分配器在物理页面上实现自己的机制，实现更细粒度管理内存。
slab分配器在创建的不分配物理内存，只有在分配slab对象的时候，没有空闲对象的时候才分配物理内存
2. slab机制创建了多层缓冲池：共享对象缓冲池和每个CPU对象缓冲池(per-cpu)
3. 每个slab分配器只负责一种 类型的对象，比如anon_vma对象
4. slab分配对象有三层结构
* 仍然处于CPU高速缓存中的per_cpu对象
* 现存slab中未使用的对象
* 使用伙伴系统新分配的slab分配器中未使用的对象


4. linux内核实现三种slab分配器机制
* slab机制：一般的操作系统
* slub机制：使用在大型系统中，性能比slab更好
* slob机制：slob机制适合嵌入式系统


```c
//创建slab描述符
struct kmem_cache *
kmem_cache_create(const char *name, unsigned int size, unsigned int align,
		slab_flags_t flags, void (*ctor)(void *))

//释放slab缓存池
void kmem_cache_destroy(struct kmem_cache *s)

//分配缓存对象
void *kmem_cache_alloc(struct kmem_cache *s, gfp_t gfpflags)

//释放缓存对象
void kmem_cache_free(struct kmem_cache *s, void *x)


  //slab描述符

struct kmem_cache {
	struct array_cache __percpu *cpu_cache;

/* 1) Cache tunables. Protected by slab_mutex */
	unsigned int batchcount;
	unsigned int limit;
	unsigned int shared;

	unsigned int size;
	struct reciprocal_value reciprocal_buffer_size;
/* 2) touched by every alloc & free from the backend */

	slab_flags_t flags;		/* constant flags */
	unsigned int num;		/* # of objs per slab */

/* 3) cache_grow/shrink */
	/* order of pgs per slab (2^n) */
	unsigned int gfporder;

	/* force GFP flags, e.g. GFP_DMA */
	gfp_t allocflags;

	size_t colour;			/* cache colouring range */
	unsigned int colour_off;	/* colour offset */
	struct kmem_cache *freelist_cache;
	unsigned int freelist_size;

	/* constructor func */
	void (*ctor)(void *obj);

/* 4) cache creation/removal */
	const char *name;
	struct list_head list;
	int refcount;
	int object_size;
	int align;
........................................
	/*
	 * If debugging is enabled, then the allocator can add additional
	 * fields and/or padding to every object. 'size' contains the total
	 * object size including these internal fields, while 'obj_offset'
	 * and 'object_size' contain the offset to the user object and its
	 * size.
	 */
	int obj_offset;
#endif /* CONFIG_DEBUG_SLAB */

#ifdef CONFIG_KASAN
	struct kasan_cache kasan_info;
#endif

#ifdef CONFIG_SLAB_FREELIST_RANDOM
	unsigned int *random_seq;
#endif

	unsigned int useroffset;	/* Usercopy region offset */
	unsigned int usersize;		/* Usercopy region size */

	struct kmem_cache_node *node[MAX_NUMNODES];
};



struct kmem_cache_node {
	spinlock_t list_lock;

#ifdef CONFIG_SLAB              //slab的三个链表
	struct list_head slabs_partial;	/* partial list first, better asm code */
	struct list_head slabs_full;
	struct list_head slabs_free;
	unsigned long total_slabs;	/* length of all slab lists */
	unsigned long free_slabs;	/* length of free slab list only */
	unsigned long free_objects;
	unsigned int free_limit;
	unsigned int colour_next;	/* Per-node cache coloring */
	struct array_cache *shared;	/* shared per node */
	struct alien_cache **alien;	/* on other nodes */
	unsigned long next_reap;	/* updated without locking */
	int free_touched;		/* updated without locking */
#endif

#ifdef CONFIG_SLUB
	unsigned long nr_partial;
	struct list_head partial;
#ifdef CONFIG_SLUB_DEBUG
	atomic_long_t nr_slabs;
	atomic_long_t total_objects;
	struct list_head full;
#endif
#endif

};

//缓冲池结构体(本地对象缓冲池)
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
4. 创建slab描述符
 ```c
    kmem_cache_create()
                |
             kmem_cache_create_usercopy()
                |
            __kmem_cache_alias()//判断是否可以复用现成的slab缓存池------>create_cache()
                |                                                            |
                |                                                       __kmem_cache_creae()//创建一个slab描述符
            返回slab描述符                                                   |
                                                                            list_add()//添加到slab_cache链表中
                                                                                | 返回slab描述符
calculate_slab_order()函数用来计算slab分配器需要的页面数
```

5. 分配slab对象
```c
   slab分配器创建slab对象的时候使用伙伴系统的借口分配物理页
   cache_alloc_refill()--->cache_grow_begin()--->kmem_getpages()--->__alloc_pages_node()分配物理页

   kmem_cache_alloc()
              |
          slab_alloc()
              |
            __do_cache_alloc()//如果本地/共享对象缓冲池
            中存在空闲的对象，会直接分配，否则
               |
              ____cache_alloc()//如果per-cpu的array_cache的entry[]数组中有未使用的对象，直接分配
                |
            cache_alloc_refill()//否则找到array_cache->batchcount个对象重新填充per-cpu缓存
	    //（kmem_cache_node中:先扫描空闲链表-->部分空闲链表)和其共享对象缓冲池
            //中迁移一部分slab空闲对象到当前slab描述符进行分配，
                |
            cache_grow_begin()
            如果还是失败，则创建slab分配器
               |
           alloc_block()//使用该函数把新创建的slab分配器中的空闲对象迁移到本地对象缓冲池中进行分配
```

6. 释放slab缓存对象

```c
     kmem_cache_free()
        |
      __cache_free()
        |
      ___cache_free()
         |
      cache_flusharray()//回收部分空闲对象或者销毁slab分配器
//本地对象缓冲池中的空闲对象 >limit(空闲对象的最大值)----->迁移到共享对象缓冲池中 >limit ----->迁移到salb节点的三个链表中 >limit 销毁slab分配器（和分配相反）

```
7. slab的管理区（管理空闲对象）
* slab管理区是一个数组freelist, 根据slab分配器的空间大小，管理区有三种分配方式

```c
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
```c


static __always_inline void *kmalloc(size_t size, gfp_t flags)
{
	if (__builtin_constant_p(size)) {
#ifndef CONFIG_SLOB
		unsigned int index;
#endif
		if (size > KMALLOC_MAX_CACHE_SIZE)
			return kmalloc_large(size, flags);
#ifndef CONFIG_SLOB
		index = kmalloc_index(size);//可以找到使用哪个 slab 描述符

		if (!index)
			return ZERO_SIZE_PTR;

		return kmem_cache_alloc_trace(
				kmalloc_caches[kmalloc_type(flags)][index],
				flags, size);
#endif
	}
	return __kmalloc(size, flags);
}



void *__kmalloc(size_t size, gfp_t flags)
{
	struct kmem_cache *s;
	void *ret;

	if (unlikely(size > KMALLOC_MAX_CACHE_SIZE))
		return kmalloc_large(size, flags);

	s = kmalloc_slab(size, flags);//使用slab机制

	if (unlikely(ZERO_OR_NULL_PTR(s)))
		return s;

	ret = slab_alloc(s, flags, _RET_IP_, size);

	trace_kmalloc(_RET_IP_, ret, size, s->size, flags);

	ret = kasan_kmalloc(s, ret, size, flags);

	return ret;
}
EXPORT_SYMBOL(__kmalloc);

```

```c
例如要分配 30 字节的小块内存，可以用 kmalloc(30, GFP_KERNEL) 来实现，之后系统会从 kmalloc-32 slab 描述符中分配一个对象

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
### vmalloc()
1. kmalloc()分配的是(内核空间)物理地址连续的内存，能分配的空间较小，使用的是slab机制,与kfree配套使用,kmalloc使用slab机制实现(kmalloc_slab())
2. vmalloc()分配(内核空间)虚拟地址空间连续的内存,能分配的空间较大，要比kmalloc()慢
3. malloc是c语言的函数，只能分配用户空间的内存。
4. vmalloc的结构
![vmalloc的分配过程和数据结构](https://blog.csdn.net/oqqYuJi12345678/article/details/122790045)

```c
//内核在处理vmalloc的映射区的时候，使用vm_struct数据结构，记住与vm_area_struct区别开来
//使用vmalloc分配的区域都用vm_struc描述,每两个vmalloc分配的区间之间留有一页大小的间隙(警戒页)
struct vm_struct {
	struct vm_struct	*next;
	void			*addr;
	unsigned long		size;
	unsigned long		flags;
	struct page		**pages;//指向一个page的指针数组，表示映射到虚拟地址空间的一个物理page
#ifdef CONFIG_HAVE_ARCH_HUGE_VMALLOC
	unsigned int		page_order;
#endif
	unsigned int		nr_pages;
	phys_addr_t		phys_addr;
	const void		*caller;
};

//所有vmalloc分配的区间都由vmlist管理
static struct vm_struct *vmlist __initdata;
//创建虚拟区之前，需要构建vmap_area,
struct vmap_area {
	unsigned long va_start;
	unsigned long va_end;

	struct rb_node rb_node;         /* address sorted rbtree */
	struct list_head list;          /* address sorted list */

	/*
	 * The following two variables can be packed, because
	 * a vmap_area object can be either:
	 *    1) in "free" tree (root is vmap_area_root)
	 *    2) or "busy" tree (root is free_vmap_area_root)
	 */
	union {
		unsigned long subtree_max_size; /* in "free" tree */
		struct vm_struct *vm;           /* in "busy" tree */
	};
};

/*

__vmalloc()的核心实现是__vmalloc_node_range()
VMALLOC_START,可分配的起始地址：就是内核模块的结束地址 

VMALLOC_END：可分配的结束地址：
**/
void *__vmalloc_node(unsigned long size, unsigned long align,
			    gfp_t gfp_mask, int node, const void *caller)
{
	return __vmalloc_node_range(size, align, VMALLOC_START, VMALLOC_END,
				gfp_mask, PAGE_KERNEL, 0, node, caller);
}
/*
 * This is only for performance analysis of vmalloc and stress purpose.
 * It is required by vmalloc test module, therefore do not use it other
 * than that.
 */
#ifdef CONFIG_TEST_VMALLOC_MODULE
EXPORT_SYMBOL_GPL(__vmalloc_node);
#endif

void *__vmalloc(unsigned long size, gfp_t gfp_mask)
{
	return __vmalloc_node(size, 1, gfp_mask, NUMA_NO_NODE,
				__builtin_return_address(0));
}
EXPORT_SYMBOL(__vmalloc);


```






















