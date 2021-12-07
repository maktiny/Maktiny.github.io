## 定时测量

1. 实时时钟(RTC)：实时时钟独立于CPU,即使PC断电，RTC任然工作。
CMOS RAM和RTC被集成到一个小芯片上，由独立的电池供电。RTC在IRQ8
上发出周期性的中断。

2. 时间戳计数器(TSC):每个时钟周期加1，

```
/**
 * native_calibrate_tsc
 * Determine TSC frequency via CPUID, else return 0.
 */ //计算时钟频率
unsigned long native_calibrate_tsc(void)

```

3. 可编程间隔定时器(PIT):使用0x40~0x43IO端口的CMOS芯片实现，用来向IRQ0发时钟中断

```
#define CLOCK_TICK_RATE		PIT_TICK_RATE

/* The clock frequency of the i8253/i8254 PIT */
#define PIT_TICK_RATE 1193182ul //  8254/8253芯片内部的振荡器频率

//使用LATCH宏来对PIT进行编程
/* LATCH is used in the interval timer and ftape setup. */
#define LATCH ((CLOCK_TICK_RATE + HZ/2) / HZ)	/* For divider */

```

4. 高精度时间定时器(HPET)

```
* 它由一个主的计数器和比较器组成，计数器一般是64位的，比较器
* 至少有3个最多32个,通常比较器是32位或64位的。HPET通过内存映射IO来操作，
内存的基地址可以从ACPI中找到,HPET中只有一个通过定时器自加的计数器，通过不同的比较器来产生中断。
（可以理解为只有一个基准Timer，并且自加计数器的值，然后通过比较器来比较是否触发中断
HPET提供两种操作模式：单次触发（也叫非周期触发）和周期触发。

struct hpet {
	u64 hpet_cap;		/* capabilities */
	u64 res0;		/* reserved */
	u64 hpet_config;	/* configuration */
	u64 res1;		/* reserved */
	u64 hpet_isr;		/* interrupt status reg */
	u64 res2[25];		/* reserved */
	union {			/* main counter */
		u64 _hpet_mc64;
		u32 _hpet_mc32;
		unsigned long _hpet_mc;
	} _u0;
	u64 res3;		/* reserved */
	struct hpet_timer {
		u64 hpet_config;	/* configuration/cap */
		union {		/* timer compare register */
			u64 _hpet_hc64;
			u32 _hpet_hc32;
			unsigned long _hpet_compare;
		} _u1;
		u64 hpet_fsb[2];	/* FSB route */
	} hpet_timers[1];
};

```


#### jiffies

```
 32为系统中jiffies通常被换算成64位的计数器的地32位
 64位系统中jiffies直接声明成u64
#if (BITS_PER_LONG < 64)
u64 get_jiffies_64(void);
#else
static inline u64 get_jiffies_64(void)
{
	return (u64)jiffies;
}
#endif


//处理溢出
#define time_after64(a,b)	\
	(typecheck(__u64, a) &&	\
	 typecheck(__u64, b) && \
	 ((__s64)((b) - (a)) < 0))
#define time_before64(a,b)	time_after64(b,a)

#define time_after_eq64(a,b)	\
	(typecheck(__u64, a) && \
	 typecheck(__u64, b) && \
	 ((__s64)((a) - (b)) >= 0))
#define time_before_eq64(a,b)	time_after_eq64(b,a)

#define time_in_range64(a, b, c) \
	(time_after_eq64(a, b) && \
	 time_before_eq64(a, c))


```


