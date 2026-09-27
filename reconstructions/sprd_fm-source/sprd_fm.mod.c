#include <linux/module.h>
#include <linux/vermagic.h>
#include <linux/compiler.h>

MODULE_INFO(vermagic, VERMAGIC_STRING);
MODULE_INFO(name, KBUILD_MODNAME);

__visible struct module __this_module
__attribute__((section(".gnu.linkonce.this_module"))) = {
	.name = KBUILD_MODNAME,
	.init = init_module,
#ifdef CONFIG_MODULE_UNLOAD
	.exit = cleanup_module,
#endif
	.arch = MODULE_ARCH_INIT,
};

#ifdef CONFIG_RETPOLINE
MODULE_INFO(retpoline, "Y");
#endif

static const struct modversion_info ____versions[]
__used
__attribute__((section("__versions"))) = {
	{ 0x6f115951, __VMLINUX_SYMBOL_STR(module_layout) },
	{ 0x999e8297, __VMLINUX_SYMBOL_STR(vfree) },
	{ 0xe2d5255a, __VMLINUX_SYMBOL_STR(strcmp) },
	{ 0x1b17e06c, __VMLINUX_SYMBOL_STR(kstrtoll) },
	{ 0xe914e41e, __VMLINUX_SYMBOL_STR(strcpy) },
	{ 0x51f12a73, __VMLINUX_SYMBOL_STR(fput) },
	{ 0x4a520869, __VMLINUX_SYMBOL_STR(kernel_read) },
	{ 0xd6ee688f, __VMLINUX_SYMBOL_STR(vmalloc) },
	{ 0x283c8416, __VMLINUX_SYMBOL_STR(vfs_llseek) },
	{ 0x7d5a21d8, __VMLINUX_SYMBOL_STR(filp_open) },
	{ 0x1b5d2297, __VMLINUX_SYMBOL_STR(misc_deregister) },
	{ 0xaeb7d129, __VMLINUX_SYMBOL_STR(dev_err) },
	{ 0x37869d47, __VMLINUX_SYMBOL_STR(misc_register) },
	{ 0x2eb634f7, __VMLINUX_SYMBOL_STR(of_find_property) },
	{ 0x9abed13e, __VMLINUX_SYMBOL_STR(devm_gpio_request) },
	{ 0xcad42800, __VMLINUX_SYMBOL_STR(of_get_named_gpio_flags) },
	{ 0x1858526, __VMLINUX_SYMBOL_STR(wakeup_source_drop) },
	{ 0x5e322189, __VMLINUX_SYMBOL_STR(wakeup_source_remove) },
	{ 0x12bfbdb0, __VMLINUX_SYMBOL_STR(platform_driver_unregister) },
	{ 0xfe990052, __VMLINUX_SYMBOL_STR(gpio_free) },
	{ 0x67424239, __VMLINUX_SYMBOL_STR(wakeup_source_add) },
	{ 0xd1db6923, __VMLINUX_SYMBOL_STR(wakeup_source_prepare) },
	{ 0x580b5f0a, __VMLINUX_SYMBOL_STR(__platform_driver_register) },
	{ 0x24bb05fc, __VMLINUX_SYMBOL_STR(_dev_info) },
	{ 0x82072614, __VMLINUX_SYMBOL_STR(tasklet_kill) },
	{ 0x3336736f, __VMLINUX_SYMBOL_STR(complete) },
	{ 0xe1537255, __VMLINUX_SYMBOL_STR(__list_del_entry_valid) },
	{ 0x9545af6d, __VMLINUX_SYMBOL_STR(tasklet_init) },
	{ 0xe2eb0ddf, __VMLINUX_SYMBOL_STR(__mutex_init) },
	{ 0x3bc1edd7, __VMLINUX_SYMBOL_STR(dma_release_from_dev_coherent) },
	{ 0xf6353e89, __VMLINUX_SYMBOL_STR(dummy_dma_ops) },
	{ 0x4c670f99, __VMLINUX_SYMBOL_STR(dma_alloc_from_dev_coherent) },
	{ 0xf28a1fa8, __VMLINUX_SYMBOL_STR(gpiod_direction_output_raw) },
	{ 0xfffe1e0e, __VMLINUX_SYMBOL_STR(gpio_to_desc) },
	{ 0xc2b00af2, __VMLINUX_SYMBOL_STR(__init_waitqueue_head) },
	{ 0xdcb764ad, __VMLINUX_SYMBOL_STR(memset) },
	{ 0x84bc974b, __VMLINUX_SYMBOL_STR(__arch_copy_from_user) },
	{ 0xde1f4a65, __VMLINUX_SYMBOL_STR(stop_marlin) },
	{ 0x3c578bac, __VMLINUX_SYMBOL_STR(__wake_up) },
	{ 0xbe69f92a, __VMLINUX_SYMBOL_STR(wait_for_completion_timeout) },
	{ 0x4829a47e, __VMLINUX_SYMBOL_STR(memcpy) },
	{ 0x4aacd53e, __VMLINUX_SYMBOL_STR(mutex_unlock) },
	{ 0x19c3dffe, __VMLINUX_SYMBOL_STR(__pm_relax) },
	{ 0xd2b09ce5, __VMLINUX_SYMBOL_STR(__kmalloc) },
	{ 0x5e38de65, __VMLINUX_SYMBOL_STR(mutex_lock) },
	{ 0x68e1cc07, __VMLINUX_SYMBOL_STR(__pm_stay_awake) },
	{ 0xf0fdf6cb, __VMLINUX_SYMBOL_STR(__stack_chk_fail) },
	{ 0x977ffa72, __VMLINUX_SYMBOL_STR(start_marlin) },
	{ 0x8f678b07, __VMLINUX_SYMBOL_STR(__stack_chk_guard) },
	{ 0x37a0cba, __VMLINUX_SYMBOL_STR(kfree) },
	{ 0x48bcb4d1, __VMLINUX_SYMBOL_STR(get_wcn_bus_ops) },
	{ 0xfaef0ed, __VMLINUX_SYMBOL_STR(__tasklet_schedule) },
	{ 0xd3259d65, __VMLINUX_SYMBOL_STR(test_and_set_bit) },
	{ 0xabbbd444, __VMLINUX_SYMBOL_STR(_raw_spin_unlock_bh) },
	{ 0x68f31cbd, __VMLINUX_SYMBOL_STR(__list_add_valid) },
	{ 0xf6f0ffed, __VMLINUX_SYMBOL_STR(_raw_spin_lock_bh) },
	{ 0x6b3539ec, __VMLINUX_SYMBOL_STR(kmem_cache_alloc_trace) },
	{ 0x600fb6e5, __VMLINUX_SYMBOL_STR(kmalloc_caches) },
	{ 0x4af1c848, __VMLINUX_SYMBOL_STR(pm_wakeup_ws_event) },
	{ 0x37befc70, __VMLINUX_SYMBOL_STR(jiffies_to_msecs) },
	{ 0x405c1144, __VMLINUX_SYMBOL_STR(get_seconds) },
	{ 0xb35dea8f, __VMLINUX_SYMBOL_STR(__arch_copy_to_user) },
	{ 0x98cf60b3, __VMLINUX_SYMBOL_STR(strlen) },
	{ 0x985558a1, __VMLINUX_SYMBOL_STR(printk) },
};

static const char __module_depends[]
__used
__attribute__((section(".modinfo"))) =
"depends=";

MODULE_ALIAS("of:N*T*Csprd,marlin3_fm");
MODULE_ALIAS("of:N*T*Csprd,marlin3_fmC*");
MODULE_ALIAS("of:N*T*Csprd,marlin3-fm");
MODULE_ALIAS("of:N*T*Csprd,marlin3-fmC*");

MODULE_INFO(srcversion, "52579565DD1CE5E56A831FD");
