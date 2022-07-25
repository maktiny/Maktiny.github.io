## Process Address 

#### 虚拟地址和物理地址的映射
![2022-05-07 10-26-19 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShly1h1zmx3o35yj30u50kr0ud.jpg)

1. 虚拟内存：虚拟内存是使用软件虚拟的，在 32 位操作系统中，每个进程都独占 4GB 的虚拟内存空间。
2. 64位系统中使用48位虚拟内存空间(256TB大小)， 物理内存空间有40位/43(锐龙处理器)位的空间

#### 进程线性地址空间
![2022-05-07 11-28-56 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShly1h1zojxfvwgj30ic0kfgo2.jpg)

* 堆：用于存放使用 malloc 函数申请的内存,当申请的空间过大，超过了堆的大小，使用mmap分配mmap映射区
* mmap区：用于存放使用 mmap 函数映射的内存区。
* 栈：用于存放函数局部变量和函数参数,栈的起始地址会跨越一个128M大小的空间(用来检测NULL指针)
* 内核态访问用户态地址空间信息要小心，可以加上__user注释，允许内核的一些处理函数检测使用是否合法。

1. 进程陷入内核态后，先把用户栈的地址保存在内核栈之中，然后设置堆栈指针寄存器的内容为内核栈的地址，这样就完成了用户栈向内核栈的转换；
2. 当进程从内核态恢复到用户态时，在内核态的最后将保存在内核栈里面的用户栈的地址恢复到堆栈指针寄存器即可
3. 进程地址空间的内存区域不会重叠，即使虚拟地址相同，但是经过进程的页表转换之后映射到物理内存的不同地方。
4. 每个进程都有一份独立的页表
```c

//每个虚拟内存区都使用vm_area_struct描述
struct vm_area_struct {
	/* The first cache line has the info for VMA tree walking. */

	unsigned long vm_start;		/* Our start address within vm_mm. */
	unsigned long vm_end;		/* The first byte after our end address
					   within vm_mm. */

	/* linked list of VM areas per task, sorted by address */
	struct vm_area_struct *vm_next, *vm_prev;

	struct rb_node vm_rb;

	/*
	 * Largest free memory gap in bytes to the left of this VMA.
	 * Either between this VMA and vma->vm_prev, or between one of the
	 * VMAs below us in the VMA rbtree and its ->vm_prev. This helps
	 * get_unmapped_area find a free area of the right size.
	 */
	unsigned long rb_subtree_gap;

	/* Second cache line starts here. */
       //反向指针，指向该虚拟内存所属的mm_struct
	struct mm_struct *vm_mm;	/* The address space we belong to. */

	/*
	 * Access permissions of this VMA.
	 * See vmf_insert_mixed_prot() for discussion.
	 */
	pgprot_t vm_page_prot;
	unsigned long vm_flags;		/* Flags, see mm.h. */

	/*
	 * For areas with an address space and backing store,
	 * linkage into the address_space->i_mmap interval tree.
	 */
	struct {
		struct rb_node rb;
		unsigned long rb_subtree_last;
	} shared;
	struct list_head anon_vma_chain; /* Serialized by mmap_lock &   //
					  * page_table_lock */
	struct anon_vma *anon_vma;	/* Serialized by page_table_lock */

	/* Function pointers to deal with this struct. */
	const struct vm_operations_struct *vm_ops;

	/* Information about our backing store: */
	unsigned long vm_pgoff;		/* Offset (within vm_file) in PAGE_SIZE //文件映射的偏移量
					   units */
	struct file * vm_file;		/* File we map to (can be NULL). *///虚拟内存中映射的文件
	
.................
}

struct mm_struct {
	struct {
		struct vm_area_struct *mmap;		/* list of VMAs */
		struct rb_root mm_rb;
		u64 vmacache_seqnum;                   /* per-thread vmacache */
#ifdef CONFIG_MMU
		unsigned long (*get_unmapped_area) (struct file *filp,
				unsigned long addr, unsigned long len,
				unsigned long pgoff, unsigned long flags);
#endif
		unsigned long mmap_base;	/* base of mmap area */
		unsigned long mmap_legacy_base;	/* base of mmap area in bottom-up allocations */
#ifdef CONFIG_HAVE_ARCH_COMPAT_MMAP_BASES
		/* Base addresses for compatible mmap() */
		unsigned long mmap_compat_base;
		unsigned long mmap_compat_legacy_base;
#endif
		unsigned long task_size;	/* size of task vm space */
		unsigned long highest_vm_end;	/* highest vma end address */
		pgd_t * pgd;

#ifdef CONFIG_MEMBARRIER
		/**
		 * @membarrier_state: Flags controlling membarrier behavior.
		 *
		 * This field is close to @pgd to hopefully fit in the same
		 * cache-line, which needs to be touched by switch_mm().
		 */
		atomic_t membarrier_state;
#endif

		/**
		 * @mm_users: The number of users including userspace.
		 *
		 * Use mmget()/mmget_not_zero()/mmput() to modify. When this
		 * drops to 0 (i.e. when the task exits and there are no other
		 * temporary reference holders), we also release a reference on
		 * @mm_count (which may then free the &struct mm_struct if
		 * @mm_count also drops to 0).
		 */
		atomic_t mm_users;

		/**
		 * @mm_count: The number of references to &struct mm_struct
		 * (@mm_users count as 1).
		 *
		 * Use mmgrab()/mmdrop() to modify. When this drops to 0, the
		 * &struct mm_struct is freed.
		 */
		atomic_t mm_count;//共享内存描述符的信号量

#ifdef CONFIG_MMU
		atomic_long_t pgtables_bytes;	/* PTE page table pages */
#endif
		int map_count;			/* number of VMAs */

		spinlock_t page_table_lock; /* Protects page tables and some
					     * counters
					     */
}

//struct file中的i_mapping指向address_space， address_space的host指向 struct inode

//address_space的i_mmap 指向vm_area_struct

//每个文件映射都有一个相关的address_space实例
struct address_space {
	struct inode		*host;
	struct xarray		i_pages;
	struct rw_semaphore	invalidate_lock;
	gfp_t			gfp_mask;
	atomic_t		i_mmap_writable;
#ifdef CONFIG_READ_ONLY_THP_FOR_FS
	/* number of thp, only for non-shmem files */
	atomic_t		nr_thps;
#endif
	struct rb_root_cached	i_mmap;
	struct rw_semaphore	i_mmap_rwsem;
	unsigned long		nrpages;
	pgoff_t			writeback_index;
	const struct address_space_operations *a_ops;
	unsigned long		flags;
	errseq_t		wb_err;
	spinlock_t		private_lock;
	struct list_head	private_list;
	void			*private_data;
} __attribute__((aligned(sizeof(long)))) __randomize_layout;
	

mm_alloc() 获得进程的内存描述符 mm_struct

// 进程描述符task_struct 中的mm 指向 mm_struct
// mm_struct的mmap指向虚拟地址空间描述符 vm_area_struct 单链表的头结点
// 也可使用mm_struct 的mm_rb（指向红黑树的根节点)遍历vm_area_struct（为了快速查找，mm_struct还维护vm_area_struct构成的红黑树）


void mmput(struct mm_struct *mm)
{
	might_sleep();

	if (atomic_dec_and_test(&mm->mm_users))
		__mmput(mm);
}
EXPORT_SYMBOL_GPL(mmput);

do_mmap() # 分配线性地址区间 vm_area_struct

do_munmap() # 释放线性地址空间
   |
   ------split_vma()  #把释放的线性地址空间从大的线性地址空间中扣出来
   |
   ------unmap_region( ) #遍历线性区链表，并释放页框
```
5. vm_area_struct的vm_flags表示VM的属性， vm_page_prot将vm的属性转换为处理器相关的页表属性
```c
pgprot_t vm_get_page_prot(unsigned long vm_flags)
{
	pgprot_t ret = __pgprot(pgprot_val(protection_map[vm_flags &
				(VM_READ|VM_WRITE|VM_EXEC|VM_SHARED)]) |
			pgprot_val(arch_vm_get_page_prot(vm_flags)));

	return arch_filter_pgprot(ret);
}
EXPORT_SYMBOL(vm_get_page_prot);

```
6. 通过给定的addr地址查找所属的VM，可能是最近邻的VM(不包含addr),也可能包含(vma->vm_start < addr < vma->vm_end)
```c
struct vm_area_struct *find_vma(struct mm_struct *mm, unsigned long addr)
{
	struct rb_node *rb_node;
	struct vm_area_struct *vma;

	mmap_assert_locked(mm);
	/* Check the cache first. */
	vma = vmacache_find(mm, addr);
	if (likely(vma))
		return vma;

	rb_node = mm->mm_rb.rb_node;

	while (rb_node) {
		struct vm_area_struct *tmp;

		tmp = rb_entry(rb_node, struct vm_area_struct, vm_rb);

		if (tmp->vm_end > addr) {
			vma = tmp;
			if (tmp->vm_start <= addr)
				break;
			rb_node = rb_node->rb_left;
		} else
			rb_node = rb_node->rb_right;
	}

	if (vma)
		vmacache_update(addr, vma);
	return vma;
}

```
7. insert_vm_struct()向VMA链表和红黑树中插入一个新的vm_area_struct
红黑树是一棵二叉排序树

8. 合并VMA：当一个新的VMA被添加到进程的地址空间时， 内核会对其进行判断能否合并vma_merge()

9. 创建映射

```c
      mmap()
       |
  ksys_mmap_pgoff()
       |
vm_mmap_pgoff()
      |
  do_map()
     |
     |---------get_unmapped_area()//在虚拟地址空间中找到一个适当的区域用于映射
     |
     |
     |-------mmap_region()
首先调用find_vma_links()查找是否已有vma线性区包含addr，如果有调用do_munmap()把这个vma干掉。

Linux不希望vma和vma之间存在空洞，只要新创建vma的flags属性和前面或者后面vma存在重叠，就尝试合并成一个新的vma，减少slab缓存消耗量，同时也减少了空洞浪费。

如果无法合并，那么只好新创建vma并对vma结构体初始化先关成员；根据vma是否有页锁定标志(VM_LOCKED)，决定是否立即分配物理页。

最后将新建的vma插入进程空间vma红黑树中，并返回addr
```
10. 删除映射
```c
             munmap() //系统调用
	          |
           __vm_munmap()
		      |
           __do_munmap()
		      |
		      |-------------find_vma_insertsection()//找到需要解除映射区域的vm_area_struct实例
		      | 
		      |-----------__split_vma()//如果找到的vm_area_struct的开始地址与解除映射的开始地址不同，需要把vm_area_struct切割开
                      |
		      |---------如果解除映射的区域的end > vm_area_struct的end,则记解除映射的后面也需要切割
		      |
		      |----------detach_vmas_to_be_unmapped()//把解除映射区域从rb和链表中解除
                      |
		      |--------unmap_region()//解除vm_area_struct与页表的映射，删除相应的TLB
		      |
		      |--------remove_vma_list()//删除vm_area_struct结构体，释放内存



```
##### 非线性映射
1. 使用mmap()创建的文件映射是连续的，映射文件的分页与内存区域的分页存在一个顺序的、一对一的对应关系。

2. 非线性映射文件分页的顺序与它们在连续内存中出现的顺序不同的映射

```c

            remap_file_pages()//非线性映射
	        |
	      do_map()//进行一些必要的标志检查之后调用do_map(),怎么实现的非线性映射，没搞清楚
```

##### 反向映射
1. 匿名页的反向映射
* 没有文件背景的页面，即匿名页（anonymous page），如堆，栈，数据段等，不是以文件形式存在，因此无法和磁盘文件交换，但可以通过硬盘上划分额外的swap交换分区或使用交换文件进行交换
* 匿名页的共享主要发生在父进程fork子进程的时候，父fork子进程时，会复制所有vma给子进程，并通过调用dup_mmap->anon_vma_fork建立子进程的rmap以及和长辈进程rmap关系结构
![2022-06-01 15-14-39 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShgy1h2srkefwdhj30n70cs0vn.jpg)
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

/*
 * The copy-on-write semantics of fork mean that an anon_vma
 * can become associated with multiple processes. Furthermore,
 * each child process will have its own anon_vma, where new
 * pages for that process are instantiated.
 *
 * This structure allows us to find the anon_vmas associated
 * with a VMA, or the VMAs associated with an anon_vma.
 * The "same_vma" list contains the anon_vma_chains linking
 * all the anon_vmas associated with this VMA.
 * The "rb" field indexes on an interval tree the anon_vma_chains
 * which link all the VMAs associated with this anon_vma.
 */
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
* 匿名页的反向映射的时候，每一个anon_vma对应一个anon_vma_chain，通过遍历红黑树查找anon_vma_chain,然后anon_vam_chain查找vma_area_struct，
然后通过vam_area_struct即可解除page的虚实地址的映射
```c

void try_to_unmap(struct page *page, enum ttu_flags flags)
{
	struct rmap_walk_control rwc = {//先注册unmap函数try_to_unmap_one(),然后调用相应的函数rmap_walk()遍历红黑树，查找到映射到同一个page的vma_area_struct
	                                //一一对应的解除映射
		.rmap_one = try_to_unmap_one,
		.arg = (void *)flags,
		.done = page_not_mapped,
		.anon_lock = page_lock_anon_vma_read,
	};

	if (flags & TTU_RMAP_LOCKED)
		rmap_walk_locked(page, &rwc);
	else
		rmap_walk(page, &rwc);
}


void rmap_walk(struct page *page, struct rmap_walk_control *rwc)
{
	if (unlikely(PageKsm(page)))
		rmap_walk_ksm(page, rwc);
	else if (PageAnon(page))
		rmap_walk_anon(page, rwc, false);
	else
		rmap_walk_file(page, rwc, false);
}

/* Like rmap_walk, but caller holds relevant rmap lock */
void rmap_walk_locked(struct page *page, struct rmap_walk_control *rwc)
{
	/* no ksm support for now */
	VM_BUG_ON_PAGE(PageKsm(page), page);
	if (PageAnon(page))
		rmap_walk_anon(page, rwc, true);
	else
		rmap_walk_file(page, rwc, true);
}


static void rmap_walk_anon(struct page *page, struct rmap_walk_control *rwc,
		bool locked)
{
	struct anon_vma *anon_vma;
	pgoff_t pgoff_start, pgoff_end;
	struct anon_vma_chain *avc;

	if (locked) {
		anon_vma = page_anon_vma(page);
		/* anon_vma disappear under us? */
		VM_BUG_ON_PAGE(!anon_vma, page);
	} else {
		anon_vma = rmap_walk_anon_lock(page, rwc);
	}
	if (!anon_vma)
		return;

	pgoff_start = page_to_pgoff(page);
	pgoff_end = pgoff_start + thp_nr_pages(page) - 1;
	anon_vma_interval_tree_foreach(avc, &anon_vma->rb_root,  //遍历红黑树获取avc
			pgoff_start, pgoff_end) {
		struct vm_area_struct *vma = avc->vma;
		unsigned long address = vma_address(page, vma);

		VM_BUG_ON_VMA(address == -EFAULT, vma);
		cond_resched();

		if (rwc->invalid_vma && rwc->invalid_vma(vma, rwc->arg))
			continue;

		if (!rwc->rmap_one(page, vma, address, rwc->arg))
			break;
		if (rwc->done && rwc->done(page))
			break;
	}

	if (!locked)
		anon_vma_unlock_read(anon_vma);
}
```
2. 文件映射页的反向映射
* 管理共享文件页的所以vma是通过address_space的区间树来管理，在mmap或者fork的时候将vma加入到这颗区间树
* 文件映射页的反向映射的时候遍历红黑树,然后调用try_to_unmap_one()
![2022-06-01 11-31-05 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShgy1h2slu0x035j30l90crn0q.jpg)

```c

static void rmap_walk_file(struct page *page, struct rmap_walk_control *rwc,
		bool locked)
{
	struct address_space *mapping = page_mapping(page);
	pgoff_t pgoff_start, pgoff_end;
	struct vm_area_struct *vma;

	/*
	 * The page lock not only makes sure that page->mapping cannot
	 * suddenly be NULLified by truncation, it makes sure that the
	 * structure at mapping cannot be freed and reused yet,
	 * so we can safely take mapping->i_mmap_rwsem.
	 */
	VM_BUG_ON_PAGE(!PageLocked(page), page);

	if (!mapping)
		return;

	pgoff_start = page_to_pgoff(page);
	pgoff_end = pgoff_start + thp_nr_pages(page) - 1;
	if (!locked)
		i_mmap_lock_read(mapping);
	vma_interval_tree_foreach(vma, &mapping->i_mmap,
			pgoff_start, pgoff_end) {
		unsigned long address = vma_address(page, vma);

		VM_BUG_ON_VMA(address == -EFAULT, vma);
		cond_resched();

		if (rwc->invalid_vma && rwc->invalid_vma(vma, rwc->arg))
			continue;

		if (!rwc->rmap_one(page, vma, address, rwc->arg))
			goto done;
		if (rwc->done && rwc->done(page))
			goto done;
	}

done:
	if (!locked)
		i_mmap_unlock_read(mapping);
}
```


### malloc是C语言的库函数，实现是使用brk()系统调用实现的
1. brk在检查地址没有超出限制之后，按页对其，也就是说brk能分配的空间是页的整数倍。
2. 如果需要收缩空间，调用__do_munmap()
1. 如果需要增加空间，使用mm_populate()来分配物理内存 
2. mm_populate使用__get_user_pages()把内存锁住，不被释放

### ELF文件
1. 一般一个 ELF 文件由以下三部分组成：
* ELF 头（ELF header）：描述应用程序的类型、CPU架构、入口地址、程序头表偏移和节头表偏移等等；
* 程序头表（Program header table）：列举了所有有效的段（segments）和他们的属性，程序头表需要加载器将文件中的段加载到虚拟内存段中；
* 节头表（Section header table）：包含对节（sections）的描述。
![2022-05-07 14-31-02 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShly1h1ztt9svywj30ex0m7q5r.jpg)

2. 所以，程序加载器可以通过 ELF 头中获取到程序头表的偏移量，然后通过程序头表的偏移量读取到程序头表的数据，再通过程序头表来获取到所有段的信息。
3. 加载ELF文件的主要使用load_elf_binary()实现


```c

0  load_elf_binary (bprm=0xffff88800561de00) at fs/binfmt_elf.c:824
#1  0xffffffff8132f148 in search_binary_handler (bprm=0xffff88800561de00)
    at fs/exec.c:1725
#2  exec_binprm (bprm=0xffff88800561de00) at fs/exec.c:1766
#3  bprm_execve (flags=<optimized out>, filename=<optimized out>, 
    fd=<optimized out>, bprm=0xffff88800561de00) at fs/exec.c:1835
#4  bprm_execve (bprm=0xffff88800561de00, fd=<optimized out>, 
    filename=<optimized out>, flags=<optimized out>) at fs/exec.c:1797
#5  0xffffffff8132f97d in do_execveat_common (fd=fd@entry=-100, 
    filename=0xffff888003eb2000, flags=0, argv=..., envp=...)
    at fs/exec.c:1924
#6  0xffffffff8132fc17 in do_execve (__envp=0x55dc1a8e1010, 
    __argv=0x7ffcfd5498e0, filename=<optimized out>) at fs/exec.c:1992
#7  __do_sys_execve (envp=0x55dc1a8e1010, argv=0x7ffcfd5498e0, 
    filename=<optimized out>) at fs/exec.c:2068
#8  __se_sys_execve (envp=<optimized out>, argv=<optimized out>, 
    filename=<optimized out>) at fs/exec.c:2063
#9  __x64_sys_execve (regs=<optimized out>) at fs/exec.c:2063
```


```c
 //linux内核中ELF文件程序头表的结构体
typedef struct elf64_phdr {
    Elf64_Word p_type;     // 段的类型
    Elf64_Word p_flags;    // 可读写标志
    Elf64_Off p_offset;    // 段在ELF文件中的偏移量
    Elf64_Addr p_vaddr;    // 段的虚拟内存地址
    Elf64_Addr p_paddr;    // 段的物理内存地址
    Elf64_Xword p_filesz;  // 段占用文件的大小
    Elf64_Xword p_memsz;   // 段占用内存的大小
    Elf64_Xword p_align;   // 内存对齐
} Elf64_Phdr;
```

## 缺页异常
```c
static __always_inline void
handle_page_fault(struct pt_regs *regs, unsigned long error_code,
			      unsigned long address)
{
	trace_page_fault_entries(regs, error_code, address);

	if (unlikely(kmmio_fault(regs, address)))
		return;

	/* Was the fault on kernel-controlled part of the address space? */
	if (unlikely(fault_in_kernel_space(address))) {
		do_kern_addr_fault(regs, error_code, address);
	} else {
		do_user_addr_fault(regs, error_code, address);
		/*
		 * User address page fault handling might have reenabled
		 * interrupts. Fixing up all potential exit points of
		 * do_user_addr_fault() and its leaf functions is just not
		 * doable w/o creating an unholy mess or turning the code
		 * upside down.
		 */
		local_irq_disable();
	}
}


handle_page_fault()  #处理缺页异常
       |
       |
 ---------------------------------------------
|                                             |
do_kern_addr_fault()                          do_user_addr_fault()   #处理用户态的缺页异常
    |
    ----spurious_kernel_fault()
    lazy TLB引起的异常,请求调页
 
    |
    ---kprobe_page_fault()

    |
    ---bad_area_nosemaphore()
    由内核bug,硬件故障引起的缺页异常


```

## 请求调页
```c
                                             handle_pte_fault()
                                                    |
                                                    |
                                                    |
     /*page不在内存,在交换区，换入*/       /*do_wp_page()写时复制*/
			do_swap_page(vmf);                      |
                                              -----wp_page_copy() 
                                              
 
```
## 创建进程的地址空间
```c
clone() ,fork(), vfork()的系统调用都是
调用系统函数——kernel_clone()
   fork()         vfork()     clone()
    |              |            |
    -----------------------------
    |
   kernel_clone()
        |
        ----copy_process() #创建(复制)子进程
        |       |
        |       -----dup_task_struct() #分配一个task_struct数据结构
        |       ---sched_fork()调度相关的初始化
        |       ---copy_mm()  #把父进程的地址空间复制给子进程
        |             |
        |            ---dup_mm()
        |                 |
        |                 ---dum_mmap() //复制父进程的页表到子进程
        |                      |
        |                      ----vm_area_dup()//为子进程创建一个VMA
        |                      ----__vm_link_rb()//把创建的VMA插入到子进程的mm中
        |                      ----copy_page_range()//复制父进程的页表项
        |
        |---------copy_thread()//函数复制父进程的struct pt_regs(段寄存器的值)栈框到子进程的栈框，
        |        在该函数设置childregs->ax = 0,fork()通过设置返回寄存器ax的这种方式，实现子进程返回0，父进程返回子进程PID。
        |----  wake_up_new_task()//唤醒进程，加入到调度队列

```
1. fork复制的开销就是：复制父进程的页表以及给子进程创建一个进程描述符,写时复制
2. vfork使用说明
* 由vfork创造出来的子进程还会导致父进程挂起，除非子进程exit或者execve才会唤起父进程
* 由vfok创建出来的子进程共享了父进程的所有内存，包括栈地址，直至子进程使用execve启动新的应用程序为止
* 由vfork创建出来得子进程不应该使用return返回调用者，或者使用exit()退出，但是它可以使用_exit()函数来退出
3. fork与vfork的区别
* fork会复制父进程的页表，而vfork不会复制，让子进程共享父进程的页表
* fork使用了写时复制技术，而vfork没有，即它任何时候都不会复制父进程地址空间
* fork父子进程执行次序不确定，一般先是子进程执行；vfork保证子进程现在执行。
* vfork()保证子进程先运行，在她调用exec或_exit之后父进程才可能被调度运行。如果在 调用这两个函数之前子进程依赖于父进程的进一步动作，则会导致死锁。

4. clone
* clone函数功能强大，带了众多参数，因此由他创建的进程要比前面2种方法要复杂，而fork与vfork都是无参数的，即共享那些资源早已规定。
* clone可以让你有选择性的继承父进程的资源，你可以选择想vfork一样和父进程共享一个虚存空间，从而使创造的是线程，你也可以不和父进程共享，你甚至可以选择创造出来的进程和父进程不再是父子关系，而是兄弟关系。

## cpu负载均衡调度算法：调度域
1. 负载均衡是通过软中断来实现的。
```c
scheduler_tick()
    |
    -------trigger_load_balance  # 设置标志位，触发负载均衡

open_softirq()
  |
run_rebalance_doamins()
  |
rebalance_domains()    # 确定调用——load_balance()的频率
    |
    -------load_balance()
              |
              ---------detach_tasks()  #把需要迁移的进程从本地runqueue剥离
              |
              --------attach_tasks() # 注册到目的CPU的runqueue
              |
              ---------——sched_move_tasks() #修改迁移进程所属的cgroup,然后进行进程调度，使原来task_runing的进程在目的CPU运行起来

              #负载均衡完成

```

