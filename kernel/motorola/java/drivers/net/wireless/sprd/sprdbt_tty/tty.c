/*
 * tty.c - Unisoc marlin tty driver (BT over WCN bus) - sprdbt_tty.ko
 *
 * Source reconstruction for the Moto G20 (p352) project, from the stock
 * sprdbt_tty.ko of RTAS31.68-66-3 (full DWARF + disassembly; evidence in
 * analysis/sprdbt_tty_baseline/).  This is the OLD WCN client generation:
 * per-transport mchn_ops (SDIO+PCIE), a coherent-DMA RX pool, reset-notifier
 * integration and an active mdbg assert.  Do NOT substitute the newer
 * ud710_bsp unified architecture (kept as tty.c.ud710-reference).
 *
 * SPDX-License-Identifier: GPL-2.0
 */

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/slab.h>
#include <linux/types.h>
#include <linux/kdev_t.h>
#include <linux/tty.h>
#include <linux/vt_kern.h>
#include <linux/init.h>
#include <linux/console.h>
#include <linux/delay.h>
#include <linux/semaphore.h>
#include <linux/vmalloc.h>
#include <linux/atomic.h>
#ifdef CONFIG_OF
#include <linux/of_device.h>
#endif
#include <linux/compat.h>
#include <linux/tty_flip.h>
#include <linux/kthread.h>
#include <linux/interrupt.h>
#include <linux/workqueue.h>
#include <linux/dma-mapping.h>

#include <misc/marlin_platform.h>
#include <misc/wcn_bus.h>
#include <misc/wcn_bus.h>
extern void sdiohal_dump_aon_reg(void);

#include "tty.h"
#include "lpm.h"
#include "rfkill.h"
#include "dump.h"

#include "alignment/sitm.h"

static unsigned int log_level = MTTY_LOG_LEVEL_NONE;

#define BT_VER(fmt, ...)						\
	do {								\
		if (log_level == MTTY_LOG_LEVEL_VER)			\
			pr_info(fmt, ##__VA_ARGS__);			\
	} while (0)

static struct semaphore sem_id;

struct rx_data {
	unsigned int channel;
	struct mbuf_t *head;
	struct mbuf_t *tail;
	unsigned int num;
	struct list_head entry;
};

/* [PROVEN] private coherent-DMA descriptor (DWARF: size 24) */
struct dma_buf {
	unsigned long vir;
	unsigned long phy;
	int size;
};

struct mtty_device {
	struct mtty_init_data *pdata;
	struct tty_port *port;
	struct tty_struct *tty;
	struct tty_driver *driver;
	struct platform_device *pdev;
	atomic_t state;
	struct mutex rw_mutex;
	struct list_head rx_head;
	struct work_struct bt_rx_work;
	struct workqueue_struct *bt_rx_workqueue;
};

static struct mtty_device *mtty_dev;
static unsigned int que_task = 1;
static int que_sche = 1;
static bool is_user_debug = false;
bt_host_data_dump *data_dump = NULL;

static bool is_dumped = false;

/* [PROVEN] globals of the stock module */
static struct device *ttyBT_dev;
static struct dma_buf *dm_rx_t;
static unsigned long *dm_rx_ptr;
static unsigned long *dm_rx_phy;
int wcn_hw_type;

static ssize_t chipid_show(struct device *dev,
	struct device_attribute *attr, char *buf)
{
	int i = 0, id;
	const char *id_str = NULL;

	id = wcn_get_chip_type();
	id_str = wcn_get_chip_name();
	pr_info("%s: chipid: %d, chipid_str: %s", __func__, id, id_str);

	i = scnprintf(buf, PAGE_SIZE, "%d/", id);
	pr_info("%s: buf: %s, i = %d", __func__, buf, i);
	strcat(buf, id_str);
	i += scnprintf(buf + i, PAGE_SIZE - i, "%s", buf + i);
	pr_info("%s: buf: %s, i = %d", __func__, buf, i);
	return i;
}

static ssize_t dumpmem_store(struct device *dev,
	struct device_attribute *attr, const char *buf, size_t count)
{
	if (buf[0] == 2) {
		pr_info("Set is_user_debug true!\n");
		is_user_debug = true;
		return 0;
	}

	if (is_dumped == false) {
		pr_info("mtty BT start dump cp mem !\n");
		/* [PROVEN] active mdbg assert in the stock binary */
		mdbg_assert_interface("BT command timeout assert !!!");
		bt_host_data_printf();
		if (data_dump != NULL) {
			vfree(data_dump);
			data_dump = NULL;
		}
	} else {
		pr_info("mtty BT has dumped cp mem, pls restart phone!\n");
	}
	is_dumped = true;

	return 0;
}

static DEVICE_ATTR_RO(chipid);
static DEVICE_ATTR_WO(dumpmem);

static struct attribute *bluetooth_attrs[] = {
	&dev_attr_chipid.attr,
	&dev_attr_dumpmem.attr,
	NULL,
};

static struct attribute_group bluetooth_group = {
	.name = NULL,
	.attrs = bluetooth_attrs,
};

static void hex_dump(unsigned char *bin, size_t binsz)
{
	char *str, hex_str[] = "0123456789ABCDEF";
	size_t i;

	str = (char *)vmalloc(binsz * 3);
	if (!str)
		return;

	for (i = 0; i < binsz; i++) {
		str[(i * 3) + 0] = hex_str[(bin[i] >> 4) & 0x0F];
		str[(i * 3) + 1] = hex_str[(bin[i]) & 0x0F];
		str[(i * 3) + 2] = ' ';
	}
	str[(binsz * 3) - 1] = 0x00;
	pr_info("%s\n", str);
	vfree(str);
}

static void hex_dump_block(unsigned char *bin, size_t binsz)
{
#define HEX_DUMP_BLOCK_SIZE 20
	int loop = binsz / HEX_DUMP_BLOCK_SIZE;
	int tail = binsz % HEX_DUMP_BLOCK_SIZE;
	int i;

	if (!loop) {
		hex_dump(bin, binsz);
		return;
	}

	for (i = 0; i < loop; i++)
		hex_dump(bin + i * HEX_DUMP_BLOCK_SIZE, HEX_DUMP_BLOCK_SIZE);

	if (tail)
		hex_dump(bin + i * HEX_DUMP_BLOCK_SIZE, tail);
}

/*
 * [PROVEN] coherent-DMA allocation for the RX pool.  The stock binary
 * resolves dma_alloc_from_dev_coherent / dummy_dma_ops through the standard
 * arm64 dma_alloc_coherent inline.
 */
int mtty_dmalloc(struct device *dev, struct dma_buf *dma, int size)
{
	dma_addr_t phy = 0;
	void *vir = NULL;
	int rc;

	if (!dev)
		dev = ttyBT_dev;
	if (!dev) {
		pr_err("%s(NULL)\n", __func__);
		return -1;
	}

	rc = dma_set_mask(dev, DMA_BIT_MASK(64));
	if (rc) {
		pr_info("dma_set_mask err\n");
		pr_err("dma_set_mask err ret %d\n", rc);
	}
	rc = dma_set_coherent_mask(dev, DMA_BIT_MASK(64));
	if (rc) {
		pr_err("dma_set_coherent_mask err\n");
		pr_err("dma_set_coherent_mask err ret %d\n", rc);
	}

	vir = dma_alloc_coherent(dev, size, &phy, GFP_KERNEL);
	if (!vir) {
		pr_err("dma_alloc_coherent err\n");
		return -1;
	}
	memset(vir, 0, size);
	dma->vir = (unsigned long)vir;
	dma->phy = (unsigned long)phy;
	dma->size = size;
	pr_info("dma_alloc_coherent(%d) 0x%lx 0x%lx\n", size, dma->vir,
		dma->phy);
	return 0;
}

/*
 * [PROVEN] allocate the RX coherent-DMA pool (dm_rx_t/dm_rx_ptr/dm_rx_phy);
 * called from mtty_open; id = pool count.
 */
int mtty_dma_buf_alloc(int id, int size, int flag)
{
	int i;

	if (wcn_hw_type != HW_TYPE_SDIO)
		return -1;

	dm_rx_t = kzalloc(id * sizeof(struct dma_buf), GFP_KERNEL);
	if (!dm_rx_t)
		return -ENOMEM;
	dm_rx_ptr = kzalloc(id * sizeof(unsigned long), GFP_KERNEL);
	if (!dm_rx_ptr) {
		kfree(dm_rx_t);
		return -ENOMEM;
	}
	dm_rx_phy = kzalloc(id * sizeof(unsigned long), GFP_KERNEL);
	if (!dm_rx_phy) {
		kfree(dm_rx_ptr);
		kfree(dm_rx_t);
		return -ENOMEM;
	}

	for (i = 0; i < id; i++) {
		if (mtty_dmalloc(ttyBT_dev, &dm_rx_t[i], size)) {
			pr_err("%s:line:%d dma_alloc_coherent err dev %p count %d phy %p\n",
			       __func__, __LINE__, ttyBT_dev, size,
			       &dm_rx_t[i].phy);
			_dev_info(ttyBT_dev, "dma_set_mask err\n");
			return -ENOMEM;
		}
		dm_rx_ptr[i] = dm_rx_t[i].vir;
		dm_rx_phy[i] = dm_rx_t[i].phy;
		memset((void *)dm_rx_ptr[i], 0, size);
	}
	return 0;
}

/* [PROVEN] release the RX coherent-DMA pool; called from mtty_close. */
int mtty_dma_buf_free(int id)
{
	int i;

	if (id < 1)
		return -EINVAL;

	for (i = 0; i < id; i++) {
		if (!dm_rx_t || !dm_rx_ptr) {
			pr_err("%s: dm_rx_t or is dm_rx_ptr NULL \n", __func__);
			return -1;
		}
		if (dm_rx_t[i].vir) {
			dma_free_coherent(ttyBT_dev, dm_rx_t[i].size,
					  (void *)dm_rx_t[i].vir,
					  (dma_addr_t)dm_rx_t[i].phy);
			pr_err("%s: free  dm_rx_ptr[%d] success \n", __func__,
			       i);
			dm_rx_t[i].vir = 0;
		}
	}
	kfree(dm_rx_ptr);
	kfree(dm_rx_phy);
	kfree(dm_rx_t);
	dm_rx_ptr = NULL;
	dm_rx_phy = NULL;
	dm_rx_t = NULL;
	return 0;
}

static void mtty_rx_work_queue(struct work_struct *work)
{
	int i, ret = 0;
	struct mtty_device *mtty;
	struct rx_data *rx = NULL;

	que_task = que_task + 1;
	if (que_task > 65530)
		que_task = 0;
	pr_info("mtty que_task= %d\n", que_task);
	que_sche = que_sche - 1;

	mtty = container_of(work, struct mtty_device, bt_rx_work);
	if (unlikely(!mtty)) {
		pr_err("mtty_rx_task mtty is NULL\n");
		return;
	}

	if (atomic_read(&mtty->state) == MTTY_STATE_OPEN) {
		do {
			mutex_lock(&mtty->rw_mutex);
			if (list_empty_careful(&mtty->rx_head)) {
				pr_err("mtty over load queue done\n");
				mutex_unlock(&mtty->rw_mutex);
				break;
			}
			rx = list_first_entry_or_null(&mtty->rx_head,
					struct rx_data, entry);
			if (!rx) {
				pr_err("mtty over load queue abort\n");
				mutex_unlock(&mtty->rw_mutex);
				break;
			}
			list_del(&rx->entry);
			mutex_unlock(&mtty->rw_mutex);

			pr_err("mtty over load working at channel: %d, len: %d\n",
					rx->channel, rx->head->len);
			for (i = 0; i < rx->head->len; i++) {
				ret = tty_insert_flip_char(mtty->port,
						*(rx->head->buf + i), TTY_NORMAL);
				if (ret != 1) {
					i--;
					continue;
				}
				tty_flip_buffer_push(mtty->port);
			}
			pr_err("mtty over load cut channel: %d\n", rx->channel);
			kfree(rx->head->buf);
			kfree(rx);

		} while (1);
	} else {
		pr_info("mtty status isn't open, status:%d\n",
				atomic_read(&mtty->state));
	}
}

/* SDIO RX: [PROVEN] flow matches the public unified rx callback */
static int mtty_sdio_rx_cb(int chn, struct mbuf_t *head,
			   struct mbuf_t *tail, int num)
{
	int ret = 0, block_size;
	struct rx_data *rx;

	bt_wakeup_host();
	block_size = ((head->buf[2] & 0x7F) << 9) + (head->buf[1] << 1) +
		     (head->buf[0] >> 7);

	if (log_level == MTTY_LOG_LEVEL_VER) {
		BT_VER("%s dump head: %d, channel: %d, num: %d\n", __func__,
		       BT_SDIO_HEAD_LEN, chn, num);
		hex_dump_block((unsigned char *)head->buf, BT_SDIO_HEAD_LEN);
		BT_VER("%s dump block %d\n", __func__, block_size);
		hex_dump_block((unsigned char *)head->buf + BT_SDIO_HEAD_LEN,
			       block_size);
	}

	if (is_user_debug)
		bt_host_data_save((unsigned char *)head->buf + BT_SDIO_HEAD_LEN,
				  block_size, BT_DATA_IN);

	if (atomic_read(&mtty_dev->state) == MTTY_STATE_CLOSE) {
		pr_err("%s mtty bt is closed abnormally\n", __func__);
		sprdwcn_bus_push_list(chn, head, tail, num);
		return -1;
	}

	if (mtty_dev != NULL) {
		if (!work_pending(&mtty_dev->bt_rx_work)) {
			BT_VER("%s tty_insert_flip_string", __func__);
			ret = tty_insert_flip_string(mtty_dev->port,
					(unsigned char *)head->buf +
					BT_SDIO_HEAD_LEN, block_size);
			BT_VER("%s ret: %d, len: %d\n", __func__, ret,
			       block_size);
			if (ret)
				tty_flip_buffer_push(mtty_dev->port);
			if (ret == block_size) {
				BT_VER("%s send success", __func__);
				sprdwcn_bus_push_list(chn, head, tail, num);
				return 0;
			}
		}

		rx = kmalloc(sizeof(struct rx_data), GFP_KERNEL);
		if (rx == NULL) {
			pr_err("%s rx == NULL\n", __func__);
			sprdwcn_bus_push_list(chn, head, tail, num);
			return -ENOMEM;
		}

		rx->head = head;
		rx->tail = tail;
		rx->channel = chn;
		rx->num = num;
		rx->head->len = block_size - ret;
		rx->head->buf = kmalloc(rx->head->len, GFP_KERNEL);
		if (rx->head->buf == NULL) {
			pr_err("mtty low memory!\n");
			kfree(rx);
			sprdwcn_bus_push_list(chn, head, tail, num);
			return -ENOMEM;
		}

		memcpy(rx->head->buf,
		       (unsigned char *)head->buf + BT_SDIO_HEAD_LEN + ret,
		       rx->head->len);
		sprdwcn_bus_push_list(chn, head, tail, num);
		mutex_lock(&mtty_dev->rw_mutex);
		pr_err("mtty over load push %d -> %d, channel: %d len: %d\n",
		       block_size, ret, rx->channel, rx->head->len);
		list_add_tail(&rx->entry, &mtty_dev->rx_head);
		mutex_unlock(&mtty_dev->rw_mutex);
		if (!work_pending(&mtty_dev->bt_rx_work)) {
			pr_err("work_pending\n");
			queue_work(mtty_dev->bt_rx_workqueue,
				   &mtty_dev->bt_rx_work);
		}
		return 0;
	}
	pr_err("mtty_rx_cb mtty_dev is NULL!!!\n");

	return -1;
}

/* PCIE RX: [LIKELY] pcie counterpart of the sdio rx path (dead on this hw) */
static int mtty_pcie_rx_cb(int chn, struct mbuf_t *head,
			   struct mbuf_t *tail, int num)
{
	pr_err("%s() rx == NULL\n", __func__);
	return mtty_sdio_rx_cb(chn, head, tail, num);
}

/* SDIO TX completion: free module-owned payloads, give back list [PROVEN] */
static int mtty_sdio_tx_cb(int chn, struct mbuf_t *head,
			   struct mbuf_t *tail, int num)
{
	int i;
	struct mbuf_t *pos = NULL;

	BT_VER("%s channel: %d, head: %p, tail: %p num: %d\n", __func__, chn,
	       head, tail, num);
	pos = head;
	for (i = 0; i < num; i++, pos = pos->next) {
		kfree(pos->buf);
		pos->buf = NULL;
	}
	if (sprdwcn_bus_list_free(chn, head, tail, num) == 0) {
		BT_VER("%s sprdwcn_bus_list_free() success\n", __func__);
		up(&sem_id);
	} else {
		pr_err("%s sprdwcn_bus_list_free() fail\n", __func__);
	}

	return 0;
}

/* PCIE TX completion: [LIKELY] pcie counterpart (dead on this hw) */
static int mtty_pcie_tx_cb(int chn, struct mbuf_t *head,
			   struct mbuf_t *tail, int num)
{
	return mtty_sdio_tx_cb(chn, head, tail, num);
}

static int mtty_open(struct tty_struct *tty, struct file *filp)
{
	struct mtty_device *mtty = NULL;
	struct tty_driver *driver = NULL;

	data_dump = (bt_host_data_dump *)vmalloc(sizeof(bt_host_data_dump));
	memset(data_dump, 0, sizeof(bt_host_data_dump));
	if (tty == NULL) {
		pr_err("mtty open input tty is NULL!\n");
		return -ENOMEM;
	}
	driver = tty->driver;
	mtty = (struct mtty_device *)driver->driver_state;

	if (mtty == NULL) {
		pr_err("mtty open input mtty NULL!\n");
		return -ENOMEM;
	}

	mtty->tty = tty;
	tty->driver_data = (void *)mtty;

	/* [PROVEN] RX coherent-DMA pool spans the open/close cycle */
	mtty_dma_buf_alloc(BT_RX_POOL_SIZE, MTTY_DMA_BUF_SIZE, 0);

	atomic_set(&mtty->state, MTTY_STATE_OPEN);
	que_task = 0;
	que_sche = 0;
	sitm_ini();
	pr_info("mtty_open device success!\n");

	return 0;
}

static void mtty_close(struct tty_struct *tty, struct file *filp)
{
	struct mtty_device *mtty = NULL;

	if (tty == NULL) {
		pr_err("mtty close input tty is NULL!\n");
		return;
	}
	mtty = (struct mtty_device *)tty->driver_data;
	if (mtty == NULL) {
		pr_err("mtty close s tty is NULL!\n");
		return;
	}

	atomic_set(&mtty->state, MTTY_STATE_CLOSE);
	sitm_cleanup();

	/* [PROVEN] pool released on close */
	mtty_dma_buf_free(BT_RX_POOL_SIZE);

	if (data_dump != NULL) {
		vfree(data_dump);
		data_dump = NULL;
	}
	pr_info("mtty_close device success !\n");
}

/*
 * [PROVEN] the whole TX implementation lives in sdio_data_transmit (the
 * sitm transmit hook), including the per-transport dispatch; stock has no
 * separate mtty_sdio_write/mtty_pcie_write symbols.
 */
static int sdio_data_transmit(uint8_t *data, size_t count)
{
	int num = 1, ret;
	struct mbuf_t *tx_head = NULL, *tx_tail = NULL;
	unsigned char *block = NULL;

	if (is_user_debug)
		bt_host_data_save(data, count, BT_DATA_OUT);
	if (log_level == MTTY_LOG_LEVEL_VER) {
		BT_VER("%s dump size: %d\n", __func__, count);
		hex_dump_block((unsigned char *)data, count);
	}

	block = kmalloc(count + BT_SDIO_HEAD_LEN, GFP_KERNEL);

	if (!block) {
		pr_err("%s kmalloc failed\n", __func__);
		return -ENOMEM;
	}
	memset(block, 0, count + BT_SDIO_HEAD_LEN);
	memcpy(block + BT_SDIO_HEAD_LEN, data, count);
	down(&sem_id);
	switch (wcn_hw_type) {
	case HW_TYPE_SDIO:
		ret = sprdwcn_bus_list_alloc(BT_TX_CHANNEL, &tx_head,
					     &tx_tail, &num);
		if (ret) {
					pr_err("%s sprdwcn_bus_list_alloc failed: %d\n", __func__,
		       ret);
		pr_err("%s:%d sprdwcn_bus_list_alloc fail\n", __func__,
		       __LINE__);
			up(&sem_id);
			kfree(block);
			block = NULL;
			return -ENOMEM;
		}
		tx_head->buf = block;
		tx_head->len = count;
		tx_head->next = NULL;

		ret = sprdwcn_bus_push_list(BT_TX_CHANNEL, tx_head, tx_tail,
					    num);
		if (ret) {
			pr_err("%s sprdwcn_bus_push_list failed: %d\n", __func__, ret);
			kfree(tx_head->buf);
			tx_head->buf = NULL;
			sprdwcn_bus_list_free(BT_TX_CHANNEL, tx_head, tx_tail,
					      num);
			return -EBUSY;
		}
		break;
	case HW_TYPE_PCIE:
		/* [LIKELY] pcie counterpart (dead on this hardware) */
		pr_err("%s:PCIE device link error\n", __func__);
		kfree(block);
		up(&sem_id);
		break;
	default:
		pr_err("%s invalid hw type\n", __func__);
		kfree(block);
		up(&sem_id);
		return -EINVAL;
	}

	BT_VER("%s ---\n", __func__);
	return count;
}



static int mtty_write_plus(struct tty_struct *tty,
			   const unsigned char *buf, int count)
{
	return sitm_write(buf, count, sdio_data_transmit);
}

static void mtty_flush_chars(struct tty_struct *tty)
{
}

static int mtty_write_room(struct tty_struct *tty)
{
	return INT_MAX;
}

static const struct tty_operations mtty_ops = {
	.open = mtty_open,
	.close = mtty_close,
	.write = mtty_write_plus,
	.flush_chars = mtty_flush_chars,
	.write_room = mtty_write_room,
};

static struct tty_port *mtty_port_init(void)
{
	struct tty_port *port = NULL;

	port = kzalloc(sizeof(struct tty_port), GFP_KERNEL);
	if (port == NULL)
		return NULL;
	tty_port_init(port);

	return port;
}

static int mtty_tty_driver_init(struct mtty_device *device)
{
	struct tty_driver *driver;
	int ret = 0;

	device->port = mtty_port_init();
	if (!device->port)
		return -ENOMEM;

	driver = tty_alloc_driver(MTTY_DEV_MAX_NR, 0);
	if (!driver)
		return -ENOMEM;

	driver->owner = THIS_MODULE;
	driver->driver_name = device->pdata->name;
	driver->name = device->pdata->name;
	driver->major = 0;
	driver->minor_start = 0;
	driver->type = TTY_DRIVER_TYPE_SYSTEM;
	driver->subtype = SYSTEM_TYPE_TTY;
	driver->init_termios = tty_std_termios;
	driver->driver_state = (void *)device;
	device->driver = driver;
	device->driver->flags = TTY_DRIVER_REAL_RAW;
	tty_set_operations(driver, &mtty_ops);
	tty_port_link_device(device->port, driver, 0);
	ret = tty_register_driver(driver);
	if (ret) {
		put_tty_driver(driver);
		tty_port_destroy(device->port);
		return ret;
	}
	return ret;
}

static void mtty_tty_driver_exit(struct mtty_device *device)
{
	struct tty_driver *driver = device->driver;

	tty_unregister_driver(driver);
	put_tty_driver(driver);
	tty_port_destroy(device->port);
}

static int mtty_parse_dt(struct mtty_init_data **init, struct device *dev)
{
#ifdef CONFIG_OF
	struct device_node *np = dev->of_node;
	struct mtty_init_data *pdata = NULL;
	int ret;

	pdata = kzalloc(sizeof(struct mtty_init_data), GFP_KERNEL);
	if (!pdata)
		return -ENOMEM;

	ret = of_property_read_string(np, "sprd,name",
				      (const char **)&pdata->name);
	if (ret)
		goto error;
	*init = pdata;

	return 0;
error:
	kfree(pdata);
	*init = NULL;
	return ret;
#else
	return -ENODEV;
#endif
}

static void mtty_destroy_pdata(struct mtty_init_data **init)
{
#ifdef CONFIG_OF
	struct mtty_init_data *pdata = *init;

	kfree(pdata);

	*init = NULL;
#endif
}

/*
 * [PROVEN] per-transport mchn ops; values decoded from the stock .data:
 *  sdio rx: hif SDIO, ch 17, inout 0, pool 1;  sdio tx: ch 3, inout 1, pool 64
 *  pcie rx: ch 2,  inout 0, pool 1;            pcie tx: ch 1, inout 1, pool 64
 */
struct mchn_ops_t bt_sdio_rx_ops = {
	.channel = BT_RX_CHANNEL,
	.hif_type = HW_TYPE_SDIO,
	.inout = BT_RX_INOUT,
	.pool_size = BT_RX_POOL_SIZE,
	.pop_link = mtty_sdio_rx_cb,
};

struct mchn_ops_t bt_sdio_tx_ops = {
	.channel = BT_TX_CHANNEL,
	.hif_type = HW_TYPE_SDIO,
	.inout = BT_TX_INOUT,
	.pool_size = BT_TX_POOL_SIZE,
	.pop_link = mtty_sdio_tx_cb,
};

struct mchn_ops_t bt_pcie_rx_ops = {
	.channel = 2,
	.hif_type = HW_TYPE_PCIE,
	.inout = BT_RX_INOUT,
	.pool_size = BT_RX_POOL_SIZE,
	.pop_link = mtty_pcie_rx_cb,
};

struct mchn_ops_t bt_pcie_tx_ops = {
	.channel = 1,
	.hif_type = HW_TYPE_PCIE,
	.inout = BT_TX_INOUT,
	.pool_size = BT_TX_POOL_SIZE,
	.pop_link = mtty_pcie_tx_cb,
};

/*
 * [PROVEN] reset-notifier callback: on WCN reset the stock logs, marks the
 * tty closed and pushes the flip buffer so readers wake up.
 */
static int bluetooth_reset(struct notifier_block *this,
			   unsigned long ev, void *p)
{
	pr_info("%s: reset callback coming\n", __func__);
	if (mtty_dev && atomic_read(&mtty_dev->state) == MTTY_STATE_OPEN) {
		atomic_set(&mtty_dev->state, MTTY_STATE_CLOSE);
		pr_err("%s() mtty bt is closed abnormally\n", __func__);
		if (mtty_dev->port)
			tty_flip_buffer_push(mtty_dev->port);
	}
	return NOTIFY_DONE;
}

static struct notifier_block bluetooth_reset_block = {
	.notifier_call = bluetooth_reset,
};

/*
 * [PROVEN] probe flow: DT parse (sprd,name), mtty_device/port/driver setup
 * (2 tty lines, REAL_RAW), SPRDBT_RX_QUEUE workqueue, sysfs group, rfkill +
 * bluesleep, reset-notifier registration, hw-type detection and
 * per-transport chn_init of the SDIO ops pair.
 */
static int mtty_probe(struct platform_device *pdev)
{
	struct mtty_init_data *pdata =
		(struct mtty_init_data *)pdev->dev.platform_data;
	struct mtty_device *mtty;
	int rval = 0;

	/*
	 * Built-in (=y) builds probe at device_initcall time, before the
	 * wcn platform is up: sprdwcn_bus_get_hwintf_type() would return
	 * HW_TYPE_INVALIED and the probe would bail with -EIO *after*
	 * having registered the tty driver, leaving /dev/ttyBT0 usable
	 * with a never-initialized sem_id — down() on its zeroed wait
	 * list then panics the kernel (observed 2026-09-29, __down ->
	 * __list_add_valid NULL oops from the BT HAL). Defer instead:
	 * the retry lands after the marlin probe with the hw type known.
	 * Modules loaded from userspace are always past this point.
	 */
	if (!wcn_btwf_device_ready()) {
		pr_info("mtty_probe: wcn platform not ready, deferring\n");
		return -EPROBE_DEFER;
	}

	/*
	 * Initialize the TX semaphore before any early return: the tty
	 * driver below must never be usable with a zeroed wait list.
	 */
	sema_init(&sem_id, BT_TX_POOL_SIZE - 1);

	if (!pdata && pdev->dev.of_node) {
		rval = mtty_parse_dt(&pdata, &pdev->dev);
		if (rval) {
			pr_err("failed to parse mtty device tree, ret=%d\n",
			       rval);
			return rval;
		}
	}

	mtty = kzalloc(sizeof(struct mtty_device), GFP_KERNEL);
	if (mtty == NULL) {
		mtty_destroy_pdata(&pdata);
		pr_err("mtty Failed to allocate device!\n");
		return -ENOMEM;
	}

	mtty->pdata = pdata;
	ttyBT_dev = &pdev->dev;
	rval = mtty_tty_driver_init(mtty);
	if (rval) {
		kfree(mtty->port);
		kfree(mtty);
		mtty_destroy_pdata(&pdata);
		dev_err(&pdev->dev, "regitster notifier failed (%d)\n", rval);
		return rval;
	}

	platform_set_drvdata(pdev, mtty);

	atomic_set(&mtty->state, MTTY_STATE_CLOSE);
	mutex_init(&mtty->rw_mutex);
	INIT_LIST_HEAD(&mtty->rx_head);
	mtty->bt_rx_workqueue =
		alloc_workqueue("SPRDBT_RX_QUEUE", WQ_UNBOUND | WQ_HIGHPRI, 1);
	if (!mtty->bt_rx_workqueue) {
		mtty_tty_driver_exit(mtty);
		kfree(mtty->port);
		kfree(mtty);
		mtty_destroy_pdata(&pdata);
		pr_err("%s SPRDBT_RX_QUEUE create failed", __func__);
		return -ENOMEM;
	}
	INIT_WORK(&mtty->bt_rx_work, mtty_rx_work_queue);

	mtty_dev = mtty;

	if (sysfs_create_group(&pdev->dev.kobj, &bluetooth_group)) {
		pr_err("%s failed to create bluetooth tty attributes.\n",
		       __func__);
	}

	rfkill_bluetooth_init(pdev);
	bluesleep_init();

	atomic_notifier_chain_register(&wcn_reset_notifier_list,
				       &bluetooth_reset_block);

	/* [PROVEN] detect the transport; register only the SDIO pair */
	wcn_hw_type = sprdwcn_bus_get_hwintf_type();
	_dev_info(&pdev->dev, "mtty_probe get hw type:%d\n", wcn_hw_type);
	
	if (wcn_hw_type == HW_TYPE_INVALIED) {
		pr_err("%s wcn invalid hw type", __func__);
		return -EIO;
	}
	if (wcn_hw_type == HW_TYPE_SDIO) {
		sprdwcn_bus_chn_init(&bt_sdio_rx_ops);
		sprdwcn_bus_chn_init(&bt_sdio_tx_ops);
	}

	return 0;
}

static int mtty_remove(struct platform_device *pdev)
{
	struct mtty_device *mtty = platform_get_drvdata(pdev);

	mtty_tty_driver_exit(mtty);
	sprdwcn_bus_chn_deinit(&bt_sdio_rx_ops);
	sprdwcn_bus_chn_deinit(&bt_sdio_tx_ops);
	kfree(mtty->port);
	mtty_destroy_pdata(&mtty->pdata);
	flush_workqueue(mtty->bt_rx_workqueue);
	destroy_workqueue(mtty->bt_rx_workqueue);
	kfree(mtty);
	platform_set_drvdata(pdev, NULL);
	sysfs_remove_group(&pdev->dev.kobj, &bluetooth_group);
	bluesleep_exit();

	return 0;
}

static const struct of_device_id mtty_match_table[] = {
	{ .compatible = "sprd,mtty", },
	{ },
};

static struct platform_driver mtty_driver = {
	.driver = {
		.owner = THIS_MODULE,
		.name = "mtty",
		.of_match_table = mtty_match_table,
	},
	.probe = mtty_probe,
	.remove = mtty_remove,
};

module_platform_driver(mtty_driver);

MODULE_AUTHOR("Unisoc wcn bt");
MODULE_DESCRIPTION("Unisoc marlin tty driver");
