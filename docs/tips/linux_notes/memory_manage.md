
### 分配内存Page

1. 页面分配

```c
                               alloc_pages()
                                   |
                                __alloc_pages()
                                    |
            ----------------------------------
            |                                 |
    get_page_from_freelist() 失败------>    __alloc_pages_slowpath()//该函数进行内存页的规整，换出，释放等耗时的动作，
                                            ,如果还不行，则使用OOM，kill一些进程以满足页分配，如果还不行则分配失败
                                               
           |
        rmqueue()//当伙伴系统中大小为order的空闲链表分配完了，调用该函数从大的order中切出一块来分配。
           |
        __rmqueue()//如果没有适合的order的页提供分配，则从高的order拆分一块来分配，由函数实现
                               //expand(zone, page, order, current_order, migratetype);
            |
        __rmqueue_fallback()//当希望的迁移类型的页面分配完了，可以从其他迁移类型的页面链表中获取分配的页面
            |----------------------------|
      find_suitable_fallback( )       steal_suitable_fallback()

           |
boost_watermark()//设置ZONE_BOOSTED_WATERMARK标志位
回退到rmqueue()的时候，早点唤醒kswapd线程,便于及时满足分配大内存快的需求。
Huge pages 有 2MB 和 1GB 两种规格，2MB 大小（默认）适合用于 GB 级别的内存，而 1GB 大小适合用于 TB 级别的内存

```

2. 内核使用pglist_data来管理内存节点，每个内存节点被分成多个zone，页面分配按照zone的水位来管理，
* WMARK_MIN：内核预留的内存，通常情况下不用
* WMARK_LOW：当zone的内存低于改值时，使用慢路径__alloc_pages_slowpath()
* WMARK_HIGH: 内存充足。

```c
/*
 zonelist中是所有可用的zone链表，第一个节点最先选用，其他的是备选
 系统初始化的时候使用build_zonelist()函数建立zonelist

 _zonerefs[0] 表示ZONE_NORMAL, zone_idx = 1,优先选择的zone。
*/
struct zonelist {
	struct zoneref _zonerefs[MAX_ZONES_PER_ZONELIST + 1];
};

struct zoneref {
	struct zone *zone;	/* Pointer to actual zone */
	int zone_idx;		/* zone_idx(zoneref->zone) */ 
};


```

```c
struct page {
	unsigned long flags;		/* Atomic flags, some possibly
					 * updated asynchronously */
	/*
	 * Five words (20/40 bytes) are available in this union.
	 * WARNING: bit 0 of the first word is used for PageTail(). That
	 * means the other users of this union MUST NOT use the bit to
	 * avoid collision and false-positive PageTail().
	 */
	union {
		struct {	/* Page cache and anonymous pages */
			/**
			 * @lru: Pageout list, eg. active_list protected by
			 * lruvec->lru_lock.  Sometimes used as a generic list
			 * by the page owner.
			 */
			struct list_head lru;
			/* See page-flags.h for PAGE_MAPPING_FLAGS */
			struct address_space *mapping;//指向页面所表示的线性地址空间、
                                    //或者匿名页面的线性地址空间,mapping
                                    //的最低两位用于判断是否指向匿名线性区
  ----------------------------------------
    } _struct_page_alignment;

```

2. 释放页面
* 释放页面的核心函数是_free_one_page()，该函数还可把空闲页面合并，之后放置到
高一级的空闲链表中。

```c
free_page()--> __free_page()-->free_the_page()-->	__free_pages_ok()-->__free_one_page()



__free_one_page (fpi_flags=6, migratetype=<optimized out>, order=10, zone=<optimized out>, pfn=<optimized out>, page=0xffffea0000560000) at mm/page_alloc.c:1063
#1  __free_pages_ok (page=<optimized out>, order=<optimized out>, fpi_flags=fpi_flags@entry=6) at mm/page_alloc.c:1653
#2  0xffffffff812bfe8b in __free_pages_core (page=<optimized out>, order=<optimized out>) at mm/page_alloc.c:1685
#3  0xffffffff831fc611 in memblock_free_pages (page=<optimized out>, pfn=<optimized out>, order=<optimized out>) at mm/page_alloc.c:1745
#4  0xffffffff831fe6f5 in __free_pages_memory (end=<optimized out>, start=<optimized out>) at mm/memblock.c:2007

```



### KSM机制
1. KSM 用于合并具有相同内容的物理主存页面以减少页面冗余。
在 Kernel 中有一个 KSM 守护进程 ksmd，它会定期扫描用户向
它注册的内存区域，寻找到相同的页面就会将其合并，并用一个
添加了写保护的页面来代替。当有进程尝试写入该页面时(写时复制)，Kernel
会自动为其分配一个新的页面，然后将新数据写入到这个新页面
2. KSM 仅仅会扫描那些向其注册的区域，就是向 KSM 模块注册了
如果条件允许可以被合并的区域，通过 madvise 系统调用可以做
到这点 int madvise(addr, length, MADV_MERGEABLE)。同时，
应用也可以通过调用 int madvise(addr, length, MADV_UNMERGEABLE) 
来取消这个注册，从而让页面恢复私有特性。但是该调用可能会造成内存
超额，造成 unmerge 失败，很大程度上会造成唤醒 Out-Of-Memory killer，
杀死当前进程。如果 KSM 没有在当前运行的 Kernel 启用，那么前面提到的 
madvise 调用就会失败，如果内核配置了 CONFIG_KSM=y，调用一般是会成功的
https://blog.csdn.net/tiantao2012/article/details/80484209

2. KSM允许合并同一进程和不同进程的匿名页面，

3. KSM使用两颗红黑树来管理扫描页面和合并页面，稳定红黑树，不稳定红黑树
已经合并的红黑树放到稳定红黑树中，扫描页面用rmap_item描述, 

4. 合并的两个页的rmap_item结构放到稳定红黑树节点的hlist中，共享页的数量限制在256
，超过256,就把hlist扩展成为一个list，每个元素都是稳定红黑树的节点


```c

SYSCALL_DEFINE3(madvise, unsigned long, start, size_t, len_in, int, behavior)
{
	return do_madvise(current->mm, start, len_in, behavior);
}

struct rmap_item {
	struct rmap_item *rmap_list;
	union {
		struct anon_vma *anon_vma;	/* when stable */
#ifdef CONFIG_NUMA
		int nid;		/* when node of unstable tree */
#endif
	};
	struct mm_struct *mm;
	unsigned long address;		/* + low bits used for flags below */
	unsigned int oldchecksum;	/* when unstable */
	union {
		struct rb_node node;	/* when node of unstable tree */
		struct {		/* when listed from stable tree */
			struct stable_node *head;
			struct hlist_node hlist;
		};
	};
};

/* The stable and unstable tree heads */
static struct rb_root one_stable_tree[1] = { RB_ROOT };
static struct rb_root one_unstable_tree[1] = { RB_ROOT };
static struct rb_root *root_stable_tree = one_stable_tree;
static struct rb_root *root_unstable_tree = one_unstable_tree;

struct stable_node {
	union {
		struct rb_node node;	/* when node of stable tree */
		struct {		/* when listed for migration */
			struct list_head *head;
			struct {
				struct hlist_node hlist_dup; //共享页的数量限制在256,
				struct list_head list;
			};
		};
	};
	struct hlist_head hlist;
	union {
		unsigned long kpfn;
		unsigned long chain_prune_time;
	};
	/*
	 * STABLE_NODE_CHAIN can be any negative number in
	 * rmap_hlist_len negative range, but better not -1 to be able
	 * to reliably detect underflows.
	 */
#define STABLE_NODE_CHAIN -1024
	int rmap_hlist_len;
#ifdef CONFIG_NUMA
	int nid;
#endif
};

```

5. KSM页面合并的过程

```c
                        ksm_init() 内核线程
                           |
                        ksm_scan_thread()
                           |
                        ksm_do_scan()
                           |
              ---------------------------------------
              |                                        |
scan_get_next_rmap_item()                     cmp_and_merge_page(page, rmap_item)
获取一个临时页，合并之用                      遍历稳定和不稳定红黑树，寻找相同页面合并
                                                            |
                                      ----------------------------------
                                     |                                   |
	                unstable_tree_search_insert()              stable_tree_search()
                                    |                                |       
                                    ---------------------------------
                                                  |
                                      try_to_merge_two_pages()
```

### 匿名线性区anon_vma
1. 为了从物理页面的page数据结构中找到所映射的PTE页表项，所创立的结构体。 
```c
struct anon_vma {
	struct anon_vma *root;		/* Root of this anon_vma tree */
	struct rw_semaphore rwsem;	/* W: modification, R: walking the list */
	/*
	 * The refcount is taken on an anon_vma when there is no
	 * guarantee that the vma of page tables will exist for
	 * the duration of the operation. A caller that takes
	 * the reference is responsible for clearing up the
	 * anon_vma if they are the last user on release
	 */
	atomic_t refcount;

	/*
	 * Count of child anon_vmas and VMAs which points to this anon_vma.
	 *
	 * This counter is used for making decision about reusing anon_vma
	 * instead of forking new one. See comments in function anon_vma_clone.
	 */
	unsigned degree;

	struct anon_vma *parent;	/* Parent of this anon_vma */

	/*
	 * NOTE: the LSB of the rb_root.rb_node is set by
	 * mm_take_all_locks() _after_ taking the above lock. So the
	 * rb_root must only be read/written after taking the above lock
	 * to be sure to see a valid next pointer. The LSB bit itself
	 * is serialized by a system wide lock only visible to
   * mm_take_all_locks() (mm_all_locks_mutex).
	 */

	/* Interval tree of private "related" vmas */
	struct rb_root_cached rb_root;
};

struct anon_vma_chain {
	struct vm_area_struct *vma;
	struct anon_vma *anon_vma;
	struct list_head same_vma;   /* locked by mmap_lock & page_table_lock */
	struct rb_node rb;			/* locked by anon_vma->rwsem */
	unsigned long rb_subtree_last;
  #ifdef CONFIG_DEBUG_VM_RB
	unsigned long cached_vma_start, cached_vma_last;
#endif
};

```

2. 内核中的KSM页面，匿名页面，文件映射页面需要unmap,unmap的结构体rmap_walk_control

```c
struct rmap_walk_control {
	void *arg;
	/*
	 * Return false if page table scanning in rmap_walk should be stopped.
	 * Otherwise, return true.
	 */
	bool (*rmap_one)(struct page *page, struct vm_area_struct *vma, //判断断开映射的VMA是哪一个
					unsigned long addr, void *arg);
	int (*done)(struct page *page);
	struct anon_vma *(*anon_lock)(struct page *page);
	bool (*invalid_vma)(struct vm_area_struct *vma, void *arg);//跳过无效的VMA
};                                ——————————————函数遍历红黑树中的anon_vma_chain来获取VMA
                                  |
try_to_unmap()-->rmap_walk()-->rmap_walk_anon() unmap的流程。

```

### 页面回收(页面交换算法：LRU 和 第二次机会 )
1.内存节点(Node)：主要依据CPU访问代价的不同而划分。多CPU下环境下，
本地内存和远端内存就是不同的节点。即使在单CPU环境下，访问所有内存
的代价都是一样的，Linux内核依然存在内存节点的概念，只不过只有一个
内存节点而已。内核以struct  pglist_data_t来描述内存节点。

2. 内存分区(Zone)：Linux对内存节点再进行划分，分为不同的分区。
内核以struct zone来描述内存分区。通常一个节点分为DMA、Normal和High Memory内存区，  


#### LRU链表(双向链表)
1. 内存紧张的时候优先换出文件映射的文件缓存，因为只有脏页才会写会磁盘，
匿名映射缓存需要写入交换区之后才能换出，每个内存节点都有一整套LRU链表

2. 基于内存节点的页面回收机制可以解决：同一个内存节点不同zone中存在的页面的
不同老化速度问题，也就是同一个程序的页面老化速度不同。
3. 引入一个计数器，每个cpu周期计数器加一，当访问页的时候，将页的计数器设置为系统计数器的值，
缺页异常发生后，比较所有页的计数器即可判断那些页最近最少使用。

```c

 //LRU链表类型(内核中共有5中LRU链表 )
#define LRU_ALL_FILE (BIT(LRU_INACTIVE_FILE) | BIT(LRU_ACTIVE_FILE)) //文件映射链表
#define LRU_ALL_ANON (BIT(LRU_INACTIVE_ANON) | BIT(LRU_ACTIVE_ANON)) //匿名页面链表
#define LRU_ALL	     ((1 << NR_LRU_LISTS) - 1)
 
LRU_UNEVICTABLE //不可回收链表
#define LRU_BASE 0
#define LRU_ACTIVE 1
#define LRU_FILE 2

enum lru_list {
	LRU_INACTIVE_ANON = LRU_BASE,
	LRU_ACTIVE_ANON = LRU_BASE + LRU_ACTIVE,
	LRU_INACTIVE_FILE = LRU_BASE + LRU_FILE,
	LRU_ACTIVE_FILE = LRU_BASE + LRU_FILE + LRU_ACTIVE,
	LRU_UNEVICTABLE,
	NR_LRU_LISTS
};

//页向量数据结构，用数组来保存一些特定的页，可以对这些页
进行相同的操作。
struct pagevec {
	unsigned char nr;
	bool percpu_pvec_drained;
	struct page *pages[PAGEVEC_SIZE];
};

///LRU链表集合描述符
struct lruvec {
	struct list_head		lists[NR_LRU_LISTS];
	/* per lruvec lru_lock for memcg */
	spinlock_t			lru_lock;
	/*
	 * These track the cost of reclaiming one LRU - file or anon -
	 * over the other. As the observed cost of reclaiming one LRU
	 * increases, the reclaim scan balance tips toward the other.
	 */
	unsigned long			anon_cost;
	unsigned long			file_cost;
	/* Non-resident age, driven by LRU movement */
	atomic_long_t			nonresident_age; //文件缓存不活跃LRU链表中移除，激活操作计数
	/* Refaults at the time of last reclaim cycle */
	unsigned long			refaults[ANON_AND_FILE];
	/* Various lruvec state flags (enum lruvec_flags) */
	unsigned long			flags;
#ifdef CONFIG_MEMCG
	struct pglist_data *pgdat;
#endif
};


//lru_cache_add()该函数把页缓存在页向量pagevec中，当pagevec数组满了之后才把整个页向量加入相应的lru链表中
//lru_cache_add_active()添加活跃的页。
------------------
        CPU0      
                  
                [inactive lru 缓存链表] [active lru缓存链表]

	CPU1              |                   |
------------------        |                   |
                          |                   |
                          |                   |  
-------------- 全局LRU链表--------------------------
                          |                   | 
	    [inactive lru 链表]      [active lru 链表]


void lru_cache_add(struct page *page)
{
	struct pagevec *pvec;

	VM_BUG_ON_PAGE(PageActive(page) && PageUnevictable(page), page);
	VM_BUG_ON_PAGE(PageLRU(page), page);

	get_page(page);
	local_lock(&lru_pvecs.lock);
	pvec = this_cpu_ptr(&lru_pvecs.lru_add);
	if (pagevec_add_and_need_flush(pvec, page))
		__pagevec_lru_add(pvec);
	local_unlock(&lru_pvecs.lock);
}
EXPORT_SYMBOL(lru_cache_add);



 * On NUMA machines, each NUMA node would have a pg_data_t to describe
 * it's memory layout. On UMA machines there is a single pglist_data which
 * describes the whole memory.
 *
 * Memory statistics and page replacement data structures are maintained on a
 * per-zone basis.
 */
```

#### 内存节点


```c
 //内存节点描述符
typedef struct pglist_data {
	/*
	 * node_zones contains just the zones for THIS node. Not all of the
	 * zones may be populated, but it is the full list. It is referenced by
	 * this node's node_zonelists as well as other node's node_zonelists.
	 */
	struct zone node_zones[MAX_NR_ZONES];

	/*
	 * node_zonelists contains references to all zones in all nodes.
	 * Generally the first zones will be references to this node's
	 * node_zones.
	 */
	struct zonelist node_zonelists[MAX_ZONELISTS];
----------------------------------------------------
		/* Per-node vmstats */
	struct per_cpu_nodestat __percpu *per_cpu_nodestats;
	atomic_long_t		vm_stat[NR_VM_NODE_STAT_ITEMS];
} pg_data_t;



#ifndef CONFIG_FORCE_MAX_ZONEORDER
#define MAX_ORDER 11
#else
#define MAX_ORDER CONFIG_FORCE_MAX_ZONEORDER
#endif
#define MAX_ORDER_NR_PAGES (1 << (MAX_ORDER - 1))

struct zone {

...............................

           /*伙伴系统的数据结构*/ 
	 /* free areas of different sizes */
	struct free_area	free_area[MAX_ORDER];

..............................

}

//如果各种迁移类型的链表中没有一块较大连续的内存，页面迁移没有任何的好处，可以通过设置全局变量
//int page_group_by_mobility_disabled __read_mostly;关闭页面迁移
enum migratetype {
	MIGRATE_UNMOVABLE,
	MIGRATE_MOVABLE,
	MIGRATE_RECLAIMABLE,
	MIGRATE_PCPTYPES,	/* the number of types on the pcp lists */
	MIGRATE_HIGHATOMIC = MIGRATE_PCPTYPES,
#ifdef CONFIG_CMA
	/*
	 * MIGRATE_CMA migration type is designed to mimic the way
	 * ZONE_MOVABLE works.  Only movable pages can be allocated
	 * from MIGRATE_CMA pageblocks and page allocator never
	 * implicitly change migration type of MIGRATE_CMA pageblock.
	 *
	 * The way to use it is to change migratetype of a range of
	 * pageblocks to MIGRATE_CMA which can be done by
	 * __free_pageblock_cma() function.  What is important though
	 * is that a range of pageblocks must be aligned to
	 * MAX_ORDER_NR_PAGES should biggest page be bigger than
	 * a single pageblock.
	 */
	MIGRATE_CMA,
#endif
#ifdef CONFIG_MEMORY_ISOLATION
	MIGRATE_ISOLATE,	/* can't allocate from here */
#endif
	MIGRATE_TYPES
};

//数组的初始化在zone_init_free_lists()
struct free_area {
	struct list_head	free_list[MIGRATE_TYPES];
	unsigned long		nr_free;
};

//如果各种迁移类型的链表中没有一块较大连续的内存，页面迁移没有任何的好处，可以通过设置全局变量
//int page_group_by_mobility_disabled __read_mostly;关闭页面迁移

void __ref build_all_zonelists(pg_data_t *pgdat)
{
	unsigned long vm_total_pages;

	if (system_state == SYSTEM_BOOTING) {
		build_all_zonelists_init();
	} else {
		__build_all_zonelists(pgdat);
		/* cpuset refresh routine should be here */
	}
	/* Get the number of free pages beyond high watermark in all zones. */
	vm_total_pages = nr_free_zone_pages(gfp_zone(GFP_HIGHUSER_MOVABLE));
	/*
	 * Disable grouping by mobility if the number of pages in the
	 * system is too low to allow the mechanism to work. It would be
	 * more accurate, but expensive to check per-zone. This check is
	 * made on memory-hotadd so a system can start with mobility
	 * disabled and enable it later
	 */
	if (vm_total_pages < (pageblock_nr_pages * MIGRATE_TYPES))
		page_group_by_mobility_disabled = 1;
	else
		page_group_by_mobility_disabled = 0;

	pr_info("Built %u zonelists, mobility grouping %s.  Total pages: %ld\n",
		nr_online_nodes,
		page_group_by_mobility_disabled ? "off" : "on",
		vm_total_pages);
#ifdef CONFIG_NUMA
	pr_info("Policy zone: %s\n", zone_names[policy_zone]);
#endif
}

//当希望的迁移类型的页面分配完了，可以从其他迁移类型的页面链表中获取分配的页面
//当希望的迁移类型的页面分配完了，接下来可以使用那种类型的页面
/*
内核在初始化的时候，调用memmap_init_zone()函数把内存页都标记为可移动的，减少外部碎片
*/
static int fallbacks[MIGRATE_TYPES][3] = {
	[MIGRATE_UNMOVABLE]   = { MIGRATE_RECLAIMABLE, MIGRATE_MOVABLE,   MIGRATE_TYPES },
	[MIGRATE_MOVABLE]     = { MIGRATE_RECLAIMABLE, MIGRATE_UNMOVABLE, MIGRATE_TYPES },
	[MIGRATE_RECLAIMABLE] = { MIGRATE_UNMOVABLE,   MIGRATE_MOVABLE,   MIGRATE_TYPES },
#ifdef CONFIG_CMA
	[MIGRATE_CMA]         = { MIGRATE_TYPES }, /* Never used */
#endif
#ifdef CONFIG_MEMORY_ISOLATION
	[MIGRATE_ISOLATE]     = { MIGRATE_TYPES }, /* Never used */
#endif
};

```

#### 第二次机会
1. FIFO算法的改进，当页面被访问过之后，其访问位置1，FIFO队列尾部的页如果访问位是1,则把该页移到FIFO的头部，而不是直接换出

2. 触发页面回收的机制
* 直接页面回收机制：使用alloc_pages时候，内存不足，陷入到页面回收机制
* 周期性页面回收机制：kswapd内核线程
* slab shrinker机制：回收slab对象


#### 交换区的数据结构
1. 如果想要新建交换分区，用户可以使用用户程序mkswap程序,创建号之后，使用sys_swapon系统调用向内核注册
如果没有指定优先级，内核初始化为当前最低优先级减一。
```c

//存储了系统中各个交换区的信息,可以使用优先级来管理各个交换区
struct swap_info_struct *swap_info[MAX_SWAPFILES];


//系统交换区信息
liyi@liyi ~ [1]> sudo cat /proc/swaps
Filename				Type		Size		Used		Priority
/dev/nvme0n1p1                          partition	15998972	0		-2



/
struct swap_cluster_info {
	spinlock_t lock;	/*
				 * Protect swap_cluster_info fields
				 * and swap_info_struct->swap_map
				 * elements correspond to the swap
				 * cluster
				 */
	unsigned int data:24;
	unsigned int flags:8;
};
#define CLUSTER_FLAG_FREE 1 /* This cluster is free */
#define CLUSTER_FLAG_NEXT_NULL 2 /* This cluster has no next cluster */
#define CLUSTER_FLAG_HUGE 4 /* This cluster is backing a transparent huge page */

/*
 * We assign a cluster to each CPU, so each CPU can allocate swap entry from
 * its own cluster and swapout sequentially. The purpose is to optimize swapout
 * throughput.
 */
 //内核为per-cpu分配交换区，next指向接下来可以使用的交换区
struct percpu_cluster {
	struct swap_cluster_info index; /* Current cluster index */
	unsigned int next; /* Likely next allocation offset */
};

struct swap_cluster_list {
	struct swap_cluster_info head;
	struct swap_cluster_info tail;
};

//交换区描述符，管理交换区
struct swap_info_struct {
	struct percpu_ref users;	/* indicate and keep swap device valid. */
	unsigned long	flags;		/* SWP_USED etc: see above */
	signed short	prio;		/* swap priority of this type */
	struct plist_node list;		/* entry in swap_active_head */
	signed char	type;		/* strange name for an index */
	unsigned int	max;		/* extent of the swap_map */
	unsigned char *swap_map;	/* vmalloc'ed array of usage counts */
	struct swap_cluster_info *cluster_info; /* cluster info. Only for SSD */
	struct swap_cluster_list free_clusters; /* free clusters list */
	unsigned int lowest_bit;	/* index of first free in swap_map */
	unsigned int highest_bit;	/* index of last free in swap_map */
	unsigned int pages;		/* total of usable pages of swap */
	unsigned int inuse_pages;	/* number of those currently in use */
	unsigned int cluster_next;	/* likely index for next allocation */
	unsigned int cluster_nr;	/* countdown to next cluster search */
	unsigned int __percpu *cluster_next_cpu; /*percpu index for next allocation */
	struct percpu_cluster __percpu *percpu_cluster; /* per cpu's swap location */
	struct rb_root swap_extent_root;/* root of the swap extent rbtree */
	struct block_device *bdev;	/* swap device or bdev of swap file */
	struct file *swap_file;		/* seldom referenced */
	unsigned int old_block_size;	/* seldom referenced */
	struct completion comp;		/* seldom referenced */
#ifdef CONFIG_FRONTSWAP
	unsigned long *frontswap_map;	/* frontswap in-use, one bit per page */
	atomic_t frontswap_pages;	/* frontswap pages in-use counter */
#endif
	spinlock_t lock;		/*
					 * protect map scan related fields like
					 * swap_map, lowest_bit, highest_bit,
					 * inuse_pages, cluster_next,
					 * cluster_nr, lowest_alloc,
					 * highest_alloc, free/discard cluster
					 * list. other fields are only changed
					 * at swapon/swapoff, so are protected
					 * by swap_lock. changing flags need
					 * hold this lock and swap_lock. If
					 * both locks need hold, hold swap_lock
					 * first.
					 */
	spinlock_t cont_lock;		/*
					 * protect swap count continuation page
					 * list.
					 */
	struct work_struct discard_work; /* discard worker */
	struct swap_cluster_list discard_clusters; /* discard clusters list */
	struct plist_node avail_lists[]; /*
					   * entries in swap_avail_heads, one
					   * entry per node.
					   * Must be last as the number of the
					   * array is nr_node_ids, which is not
					   * a fixed value so have to allocate
					   * dynamically.
					   * And it has to be an array so that
					   * plist_for_each_* can work.
					   */
};

//内核使用该结构标记需要换出的页
typedef struct {
	unsigned long val;
} swp_entry_t;

unsigned long val : 0-------59---------63
                       |            |
	           偏移            交换区标识符
```
2. 交换区是磁盘或者块设备，这些结构都是为了把交换区组织起来提供给内核使用。
3. 页面回收在内存中设置交换缓存，之后可以异步把交换缓存中的数据写入交换区中。
```c

static const struct address_space_operations swap_aops = {//交换缓存注册的接口函数，
	.writepage	= swap_writepage,
	.set_page_dirty	= swap_set_page_dirty,
#ifdef CONFIG_MIGRATION
	.migratepage	= migrate_page,
#endif
};

struct address_space *swapper_spaces[MAX_SWAPFILES] __read_mostly;//交换缓存结构
static unsigned int nr_swapper_spaces[MAX_SWAPFILES] __read_mostly;

```

1. 在使用文件作为交换区的时候，文件对应的磁盘可能是不连续的，使用swap_extent结构来处理不连续时候的交换区与磁盘之间的映射问题
```c

struct swap_extent {
	struct rb_node rb_node;
	pgoff_t start_page;
	pgoff_t nr_pages;
	sector_t start_block;
};


```

##### 页面交换时的控制参数 

```c
//用于控制页面回收的参数
struct scan_control {
	/* How many pages shrink_list() should reclaim */
	unsigned long nr_to_reclaim;

	/*
	 * Nodemask of nodes allowed by the caller. If NULL, all nodes
	 * are scanned.
	 */
	nodemask_t	*nodemask;

	/*
	 * The memory cgroup that hit its limit and as a result is the
	 * primary target of this reclaim invocation.
	 */
	struct mem_cgroup *target_mem_cgroup;

	/*
	 * Scan pressure balancing between anon and file LRUs
	 */
	unsigned long	anon_cost;
	unsigned long	file_cost;

	/* Can active pages be deactivated as part of reclaim? */
	---------------------------------------------
  struct {
		unsigned int dirty;
		unsigned int unqueued_dirty;
		unsigned int congested;
		unsigned int writeback;
		unsigned int immediate;
		unsigned int file_taken;
		unsigned int taken;
	} nr;

	/* for recording the reclaimed slab by now */
	struct reclaim_state reclaim_state;
};

```
#### kswapd内核线程(页面回收接口
1. 页面回收在两个地方触发：直接页面回收 try_to_free_pages() 和页交换进程kswap()，NUMA的每个内存节点有一个kswap实例，UMA只有一个kswap实例
2. 每个内存域两个LRU链表，active，in_active

```c
                         kswapd()                         do_try_to_free_pages()
                            |                                  |
                   balance_pgdat()                       shrink_zones()
                           |                                 |      
               kswapd_shrink_node()                          |  
                          |                                  |
              shrink_node(pgdat, sc)<-------------------------
                         |
            shrink_node_memcgs(pgdat, sc)
                        |
          -----------------------------
          |                            |
shrink_lruvec()               shrink_slab()
          |
   shrink_list()
          |
    --------------------------------------------
    |                                           |
shrink_active_list()                         shrink_inactive_list()
   l_hold---------                                           |
   l_active      |                                         shrink_page_list()//扫描回收page_list中的页表
   l_inactive    |                                        剩下的是不可回收的，move_pages_to_lru（）移回原来的LRU链表          
三个链表         |                                            |
                 |                                         add_to_swap()构造BIO,交换区等，把页交换到交换区                                                         
            isolate_lru_pages() 集中回收算法                   |
            把LRU链表中的项移到l_hold，                        |-----get_swap_page()//分配交换空间，在交换区中获取一个槽位
            减少加锁时间,遍历l_hold,分别放到                   |
l_active和l_inactive链表中，剩余的是可以回收的项               |------—__add_to_swap_page_cache()把页写入交换区缓存
然后把l_active,l_inactive中的项移动到相应的LRU链表



//内核提供接口，可以自己注册内存收缩器
//register_shrinker() unregister_shrinker()
//注册的内存收缩器被添加到一个全局链表中shrinker_list中

static LIST_HEAD(shrinker_list);

struct shrinker {
        //这两个函数指针是注册收缩器必须实现的内存回收函数
	unsigned long (*count_objects)(struct shrinker *,
				       struct shrink_control *sc);
	unsigned long (*scan_objects)(struct shrinker *,
				      struct shrink_control *sc);

	long batch;	/* reclaim batch size, 0 = default */
	int seeks;	/* seeks to recreate an obj */
	unsigned flags;

	/* These are for internal use */
	struct list_head list;
#ifdef CONFIG_MEMCG
	/* ID in shrinker_idr */
	int id;
#endif
	/* objs pending delete, per node */
	atomic_long_t *nr_deferred;
};
#define DEFAULT_SEEKS 2 /* A good number if you don't know better. */

```

#### refault Distance算法（防止页面抖动）



#### 页面迁移
1. 页面迁移机制包含两种页面
* 传统的LRU页面，匿名页面和文件映射页面
* 非LRU页面， zsmalloc和virtio-blloon页面
2. 用户进程地址空间的页面可以迁移，内核本身使用的页面不能迁移。
```c
                                  migrate_pages()系统调用
                                         |
                                  kernel_migrate_pages()获取内存节点，迁移的时候进程使用计数usage加一
                                         |
                                  do_migrate_pages()
                                  迁移的时候lru_cache_disable()
                                          |
                                  migrate_to_node()
                                          |
          int migrate_pages(struct list_head *from, new_page_t get_new_page,
		free_page_t put_new_page, unsigned long private,
		enum migrate_mode mode, int reason, unsigned int *ret_succeeded)
                                         |
                                   unmap_and_move()//
                                         |

                                        __unmap_and_move()
                                                |
                                --------------------------
                                |                         |
                      move_to_new_page()       remove_migration_ptes()//迁移页表项


```

#### 内存规整(内存规整基于页面迁移实现)

1. 两个扫描者，一个由zone 从前向后扫描可迁移的页面，一个由zone从后向前扫描空闲的页面，当
两者相遇或者已经满足分配大块内存并且已经满足最低水位要求退出扫描。

2. 直接内存规整 __alloc_pages_direct_coompact()

3. 内核以页块来管理页的迁移属性 页块大小是HUGETLB_PAGE_ORDER=9 或者为10

```c
                                __alloc_pages_direct_coompact()
                                              |
                                    try_to_compact_pages()//遍历内存节点中的zone,在每个zone中调用compact_zone_order()
                                             |
                                      compact_zone_order()//初始化compact_control,调用compact_zone()
                                              |
                                        compact_zone() ->compaction_suitable()->__compaction_suitable()->zone_watermark_ok()//判断是否需要内存规整
                                              |
                                    ----------------------------
                                    |      |                      |
  isolate_migratepages()// 扫描和分离页面  |      migrate_pages(&cc->migratepages, compaction_alloc,compaction_free, (unsigned long)cc, cc->mode,MR_COMPACTION, NULL);
             |                             |                                                |                  |   
             |                             |                                                |                  |
             |                   release_freepages()                             函数指针get_new_page       函数指针put_new_page     
             |                            |                                       指向compaction_alloc函数
             |                   把空闲链表中的page释放到伙伴系统中 
  isolate_migratepages_block()//对页块中的页进行分离
             
    //规整控制描述符
struct compact_control {
	struct list_head freepages;	/* List of free pages to migrate to */
	struct list_head migratepages;	/* List of pages being migrated */
	unsigned int nr_freepages;	/* Number of isolated free pages */
	unsigned int nr_migratepages;	/* Number of pages to migrate */
	unsigned long free_pfn;		/* isolate_freepages search base */
	/*
	 * Acts as an in/out parameter to page isolation for migration.
	 * isolate_migratepages uses it as a search base.
	 * isolate_migratepages_block will update the value to the next pfn
	 * after the last isolated one.
	 */
	unsigned long migrate_pfn;
	unsigned long fast_start_pfn;	/* a pfn to start linear scan from */
	struct zone *zone;
	unsigned long total_migrate_scanned;
	unsigned long total_free_scanned;
	unsigned short fast_search_fail;/* failures to use free list searches */
	short search_order;		/* order to start a fast search at */
	const gfp_t gfp_mask;		/* gfp mask of a direct compactor */
	int order;			/* order a direct compactor needs */
	int migratetype;		/* migratetype of direct compactor */
	const unsigned int alloc_flags;	/* alloc flags of a direct compactor */
	const int highest_zoneidx;	/* zone index of a direct compactor */
	enum migrate_mode mode;		/* Async or sync migration mode */ 内存规整模式
	bool ignore_skip_hint;		/* Scan blocks even if marked skip */
	bool no_set_skip_hint;		/* Don't mark blocks for skipping */
	bool ignore_block_suitable;	/* Scan blocks considered unsuitable */
	bool direct_compaction;		/* False from kcompactd or /proc/... */
	bool proactive_compaction;	/* kcompactd proactive compaction */
	bool whole_zone;		/* Whole zone should/has been scanned */
	bool contended;			/* Signal lock or sched contention */
	bool rescan;			/* Rescanning the same pageblock */
	bool alloc_contig;		/* alloc_contig_range allocation */
};

enum migrate_mode {
	MIGRATE_ASYNC, //异步模式
	MIGRATE_SYNC_LIGHT,//同步模式，允许调用者阻塞
	MIGRATE_SYNC,//同步模式，页面迁移时会被阻塞
	MIGRATE_SYNC_NO_COPY,//同步模式，但是页面迁移时，CPU不会复制页面，是由DMA完成
};

```

#### 内存碎片化管理

1. __zone_watermark_ok()函数判断是否有足够的页面提供分配
2. 注意，如果页面分配的类型不满足，其他类型有足够的分配空间，则可以借用。
调用steal_suitable_fallback()实现，由于不是请求的页面类型，说明内核由页外碎片
steal_suitable_fallback()设置ZONE_BOOSTED_WATERMARK标志位，提前唤醒kswapd内核线程。

```c
static int fallbacks[MIGRATE_TYPES][3] = {
	[MIGRATE_UNMOVABLE]   = { MIGRATE_RECLAIMABLE, MIGRATE_MOVABLE,   MIGRATE_TYPES },
	[MIGRATE_MOVABLE]     = { MIGRATE_RECLAIMABLE, MIGRATE_UNMOVABLE, MIGRATE_TYPES },
	[MIGRATE_RECLAIMABLE] = { MIGRATE_UNMOVABLE,   MIGRATE_MOVABLE,   MIGRATE_TYPES },
#ifdef CONFIG_CMA
	[MIGRATE_CMA]         = { MIGRATE_TYPES }, /* Never used */
#endif
#ifdef CONFIG_MEMORY_ISOLATION
	[MIGRATE_ISOLATE]     = { MIGRATE_TYPES }, /* Never used */
#endif
};


```

