## 字符设备驱动程序
1. 设备号dev是一个范围，可以由宏解析出主设备号和次设备号。
2. 设备号在统一范围的所有设备文件由同一个设备驱动程序处理。

```
  /*设备驱动程序描述符*/
struct cdev {
	struct kobject kobj;
	struct module *owner;
	const struct file_operations *ops;
	struct list_head list;
	dev_t dev;
	unsigned int count;
} __randomize_layout;

 /*
 * 为了记录已经分配的设备号， 使用散列表chrdevs
 * 两个不同的设备号范围可以使用同一个主设备号，
 * 使用冲突链表char_device_struct结构记录冲突。
 **/
static struct char_device_struct {
	struct char_device_struct *next;
	unsigned int major;
	unsigned int baseminor;
	int minorct;
	char name[64];
	struct cdev *cdev;		/* will die */
} *chrdevs[CHRDEV_MAJOR_HASH_SIZE];


```
