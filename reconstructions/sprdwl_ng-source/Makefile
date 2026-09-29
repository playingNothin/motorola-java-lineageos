# sprdwl_ng - Moto G20 (java) sc2355 WLAN driver, reconstruction v8
# Integrated into the kernel tree 2026-09-26; built as a module so the
# WiFi HAL keeps its finit_module/delete_module lifecycle.
ccflags-y += -DSC2355_FTR -DSC2355_TX_FILTER -DSC2355_QOS_MAP
ccflags-y += -DIBSS_SUPPORT -DIBSS_RSN_SUPPORT
ccflags-y += -DNAN_SUPPORT
ccflags-y += -DRTT_SUPPORT
ccflags-y += -DSC2355_RX_NO_LOOP
ccflags-y += -DACS_SUPPORT -DSC2355_HW_CSUM
ccflags-y += -DWMMAC_WFA_CERTIFICATION
ccflags-y += -DCOMPAT_SAMPILE_CODE
ccflags-y += -DRND_MAC_SUPPORT
ccflags-y += -DSOFTAP_HOOK
ccflags-y += -DATCMD_ASSERT
ccflags-y += -DTCPACK_DELAY_SUPPORT
ccflags-y += -DSPLIT_STACK
ccflags-y += -I$(src)
ccflags-y += -I$(srctree)/drivers/staging/android/ion
ccflags-y += -I$(srctree)/drivers/staging/android/ion/sprd
ccflags-y += -I$(srctree)/drivers/staging/android/ion/sprd/inc
ccflags-y += -I$(srctree)/net/mac80211
# reconstruction carries pre-existing fortify/implicit warnings the SPRD
# internal toolchain tolerated; keep them non-fatal (kernel uses -Werror)
subdir-ccflags-y += -Wno-error
subdir-ccflags-y += -Wno-error=fortify-source
subdir-ccflags-y += -Wno-implicit-function-declaration

obj-$(CONFIG_SPRDWL_NG) += sprdwl_ng.o
sprdwl_ng-y := api_version.o cfg80211.o cmdevt.o core_sc2355.o debug.o \
	defrag.o ibss.o if_sc2355.o main.o mm.o msg.o nan.o npi.o qos.o \
	reorder.o rf_marlin3.o rnd_mac_addr.o rtt.o rx_msg_sc2355.o \
	softap_hook.o tcp_ack.o tracer.o tx_msg_sc2355.o txrx.o vendor.o \
	work.o
