### 文件预读
1. 预读算法维护两个窗口，当前窗口和预读窗口，预读窗口内的页(还在传输中的页)紧挨着当前窗口内的页
2. 当顺序读时，启动文件预读算法。
```c
struct file_ra_state {
	pgoff_t start; //当前窗口的第一页的索引
	unsigned int size;// 当前窗口的页数
	unsigned int async_size;
	unsigned int ra_pages;//预读窗口的最大页数，0表示禁止预读，default=32页
	unsigned int mmap_miss;
	loff_t prev_pos;
};


```


###

```c

 //kiocb 用来跟踪同步和异步IO操作的完成状态
struct kiocb {
	struct file		*ki_filp; // IO操作的文件对象

	/* The 'ki_filp' pointer is shared in a union for aio */
	randomized_struct_fields_start

	loff_t			ki_pos; //进行IO操作的文件的当前位置
	void (*ki_complete)(struct kiocb *iocb, long ret, long ret2);
	void			*private;
	int			ki_flags;
	u16			ki_hint;
	u16			ki_ioprio; /* See linux/ioprio.h */
	union {
		unsigned int		ki_cookie; /* for ->iopoll */
		struct wait_page_queue	*ki_waitq; /* for async buffered IO */
	};

	randomized_struct_fields_end
};
/*
 * "descriptor" for what we're up to with a read.
 * This allows us to use the same read code yet
 * have multiple different users of the data that
 * we read from a file.
 *
 * The simplest case just copies the data to user
 * mode.
 */

 //读操作的描述符
typedef struct {
	size_t written;//已经拷贝到用户态缓冲区的字节数
	size_t count;//待传送的字节数
	union {
		char __user *buf;//缓冲区
		void *data;
	} arg;
	int error;//读操作错误码
} read_descriptor_t;


```

### 内存映射

1. 内存映射类型：共享型，私有型
* 共享型：在线性区页上的所有操作都会修改磁盘上的文件，对映射了同一文件的其他进程是可见的。
* 私有型：为进程读文件创建的映射，写操作不会改变文件(写时复制)，为改变的页的内容会随着磁盘的内容而更新。



### 直接IO传送
1. 缓存IO传送经过中断和DMA进行,数据需要在内核缓冲和用户态进程页中互相拷贝。
2. 如果用户采用的是同步写机制（ synchronous writes ）, 那么数据会立即被写回到磁盘上，
应用程序会一直等到数据被写完为止；如果用户采用的是延迟写机制（ deferred writes ），
那么应用程序就完全不需要等到数据全部被写回到磁盘，数据只要被写到页缓存中去就可以了。
在延迟写机制的情况下，操作系统会定期地将放在页缓存中的数 据刷到磁盘上。与异步写机制
（ asynchronous writes ）不同的是，延迟写机制在数据完全写到磁盘上的时候不会通知应用
程序，而异步写机制在数据完全写到磁盘上的时候是会返回给应用程序的。所以延迟写机制本身
是存在数据丢失的风险的，而异步写机制则不会有这方面的担心
```
  
      磁盘 <----> 内核缓冲区 <----> 用户态地址空间  （两次拷贝）

```
![2022-05-07 11-38-44 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShly1h1zouao9iqj30m50ei763.jpg)
零拷贝技术 不单只有 sendfile，如 mmap、splice 和 直接I/O 等都是 零拷贝技
2. 直接IO不经过内核缓冲区，用户态进程直接写回磁盘，这种方式性能回更高。 
3. 直接IO使用 generic_file_direct_write()函数，该函数实际调用address_space结构体注册的direct_IO()函数
4. 对于某些应用程序来说，它会有它自己的数据缓存机制，比如，它会将数据缓存
在应用程序地址空间，这类应用程序完全不需要使用操作系统内核中的 高速缓冲存储器，
这类应用程序就被称作是自缓存应用程序（ self-caching applications ）。数据库管理系统是这类应用程序的一个代表


### 异步IO 

#### glibc(POSIX AIO)版本的异步IO

1. POSIX AIO 是在用户控件模拟异步 IO 的功能，不需要内核支持，
2. 而 linux AIO 则是 linux 内核原声支持的异步 IO 调用，行为更加低级
![关于 linux IO 模型及 AIO、POSIX AIO 的简介，请参看]：https://blog.csdn.net/brucexu1978/article/details/7085924

```  
struct aio_kiocb {
	union {
		struct file		*ki_filp;
		struct kiocb		rw;
		struct fsync_iocb	fsync;
		struct poll_iocb	poll;
	};

	struct kioctx		*ki_ctx;
	kiocb_cancel_fn		*ki_cancel;

	struct io_event		ki_res;

	struct list_head	ki_list;	/* the aio core uses this
						 * for cancellation */
	refcount_t		ki_refcnt;

	/*
	 * If the aio_resfd field of the userspace iocb is not zero,
	 * this is the underlying eventfd context to deliver events to.
	 */
	struct eventfd_ctx	*ki_eventfd;
};


```

#### linux 版本的异步IO
1. 使用io_submit()系统调用开始异步IO之前先初始化异步IO环境
2. linux kernel 5.14 中 io_submit()使用glibc的AIO借口aio_read()等函数实现

```

               io_submit()
                   |
               io_submit_one()
                   |
               __io_submit_one()


static int __io_submit_one(struct kioctx *ctx, const struct iocb *iocb,
			   struct iocb __user *user_iocb, struct aio_kiocb *req,
			   bool compat)
{
	req->ki_filp = fget(iocb->aio_fildes);
	if (unlikely(!req->ki_filp))
		return -EBADF;

	if (iocb->aio_flags & IOCB_FLAG_RESFD) {
		struct eventfd_ctx *eventfd;
		/*
		 * If the IOCB_FLAG_RESFD flag of aio_flags is set, get an
		 * instance of the file* now. The file descriptor must be
		 * an eventfd() fd, and will be signaled for each completed
		 * event using the eventfd_signal() function.
		 */
		eventfd = eventfd_ctx_fdget(iocb->aio_resfd);
		if (IS_ERR(eventfd))
			return PTR_ERR(eventfd);

		req->ki_eventfd = eventfd;
	}

	if (unlikely(put_user(KIOCB_KEY, &user_iocb->aio_key))) {
		pr_debug("EFAULT: aio_key\n");
		return -EFAULT;
	}

	req->ki_res.obj = (u64)(unsigned long)user_iocb;
	req->ki_res.data = iocb->aio_data;
	req->ki_res.res = 0;
	req->ki_res.res2 = 0;

	switch (iocb->aio_lio_opcode) {
	case IOCB_CMD_PREAD:
		return aio_read(&req->rw, iocb, false, compat);
	case IOCB_CMD_PWRITE:
		return aio_write(&req->rw, iocb, false, compat);
	case IOCB_CMD_PREADV:
		return aio_read(&req->rw, iocb, true, compat);
	case IOCB_CMD_PWRITEV:
		return aio_write(&req->rw, iocb, true, compat);
	case IOCB_CMD_FSYNC:
		return aio_fsync(&req->fsync, iocb, false);
	case IOCB_CMD_FDSYNC:
		return aio_fsync(&req->fsync, iocb, true);
	case IOCB_CMD_POLL:
		return aio_poll(req, iocb);
	default:
		pr_debug("invalid aio operation %d\n", iocb->aio_lio_opcode);
		return -EINVAL;
	}
}




//异步IO的linux系统调用。
COND_SYSCALL(io_setup);
COND_SYSCALL_COMPAT(io_setup);
COND_SYSCALL(io_destroy);
COND_SYSCALL(io_submit);
COND_SYSCALL_COMPAT(io_submit);
COND_SYSCALL(io_cancel);
COND_SYSCALL(io_getevents_time32);
COND_SYSCALL(io_getevents);
COND_SYSCALL(io_pgetevents_time32);
COND_SYSCALL(io_pgetevents);
COND_SYSCALL_COMPAT(io_pgetevents_time32);
COND_SYSCALL_COMPAT(io_pgetevents);
COND_SYSCALL(io_uring_setup);
COND_SYSCALL(io_uring_enter);
COND_SYSCALL(io_uring_register);

/***
调用io_submit后，对应于用户传递的每一个iocb结构，
会在内核态生成一个与之对应的kiocb结构，并且在
对应kioctx结构的ring_info中预留一个io_events的空间。
之后，请求的处理结果就被写到这个io_event中。

*/

//用户态的异步IO描述符
struct iocb {
	/* these are internal to the kernel/libc. */
	__u64	aio_data;	/* data to be returned in event's data */

#if defined(__BYTE_ORDER) ? __BYTE_ORDER == __LITTLE_ENDIAN : defined(__LITTLE_ENDIAN)
	__u32	aio_key;	/* the kernel sets aio_key to the req # */
	__kernel_rwf_t aio_rw_flags;	/* RWF_* flags */
#elif defined(__BYTE_ORDER) ? __BYTE_ORDER == __BIG_ENDIAN : defined(__BIG_ENDIAN)
	__kernel_rwf_t aio_rw_flags;	/* RWF_* flags */
	__u32	aio_key;	/* the kernel sets aio_key to the req # */
#else
#error edit for your odd byteorder.
#endif

	/* common fields */
	__u16	aio_lio_opcode;	/* see IOCB_CMD_ above */
	__s16	aio_reqprio;
	__u32	aio_fildes;

	__u64	aio_buf;
	__u64	aio_nbytes;
	__s64	aio_offset;

	/* extra parameters */
	__u64	aio_reserved2;	/* TODO: use this for a (struct sigevent *) */

	/* flags for the "struct iocb" */
	__u32	aio_flags;

	/*
	 * if the IOCB_FLAG_RESFD flag of "aio_flags" is set, this is an
	 * eventfd to signal AIO readiness to
	 */
	__u32	aio_resfd;
}; /* 64 bytes */





//句柄aio_context_t指向kioctx 异步IO上下文
//描述异步IO环境的数据结构kioctx
struct kioctx {
	struct percpu_ref	users;
	atomic_t		dead;

	struct percpu_ref	reqs;

	unsigned long		user_id;

	struct __percpu kioctx_cpu *cpu;

	/*
	 * For percpu reqs_available, number of slots we move to/from global
	 * counter at a time:
	 */
	unsigned		req_batch;
	/*
	 * This is what userspace passed to io_setup(), it's not used for
	 * anything but counting against the global max_reqs quota.
	 *
	 * The real limit is nr_events - 1, which will be larger (see
	 * aio_setup_ring())
	 */
	unsigned		max_reqs;

	/* Size of ringbuffer, in units of struct io_event */
	unsigned		nr_events;

	unsigned long		mmap_base;
	unsigned long		mmap_size;

// 环形缓冲区，内核用来写已完成的IO报告。
	struct page		**ring_pages;
	long			nr_pages;

	struct rcu_work		free_rwork;	/* see free_ioctx() */

	/*
	 * signals when all in-flight requests are done
	 */
	struct ctx_rq_wait	*rq_wait;

	struct {
		/*
		 * This counts the number of available slots in the ringbuffer,
		 * so we avoid overflowing it: it's decremented (if positive)
		 * when allocating a kiocb and incremented when the resulting
		 * io_event is pulled off the ringbuffer.
		 *
		 * We batch accesses to it with a percpu version.
		 */
		atomic_t	reqs_available;
	} ____cacheline_aligned_in_smp;

	struct {
		spinlock_t	ctx_lock;
		struct list_head active_reqs;	/* used for cancellation */
	} ____cacheline_aligned_in_smp;

	struct {
		struct mutex	ring_lock;
		wait_queue_head_t wait;
	} ____cacheline_aligned_in_smp;

	struct {
		unsigned	tail;
		unsigned	completed_events;
		spinlock_t	completion_lock;
	} ____cacheline_aligned_in_smp;

	struct page		*internal_pages[AIO_RING_PAGES];
	struct file		*aio_ring_file;

	unsigned		id;
};


```
