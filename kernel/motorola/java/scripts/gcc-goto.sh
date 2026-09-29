#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Test for gcc 'asm goto' support
# Copyright (C) 2010, Jason Baron <jbaron@redhat.com>
#
# STOCK PARITY (Moto G20 / java): the vendor kernel was built with this
# test failing (no CC_HAVE_ASM_GOTO -> no HAVE_JUMP_LABEL), which changes
# struct static_key / struct jump_entry and therefore every modversions
# CRC. The stock socko modules (mali_gondul, camera, sensors, ...) only
# load against that layout. Keep this test failing so our kernel keeps
# the stock symbol CRCs.

exit 1

cat << "END" | $@ -x c - -c -o /dev/null >/dev/null 2>&1 && echo "y"
int main(void)
{
#if defined(__arm__) || defined(__aarch64__)
	/*
	 * Not related to asm goto, but used by jump label
	 * and broken on some ARM GCC versions (see GCC Bug 48637).
	 */
	static struct { int dummy; int state; } tp;
	asm (".long %c0" :: "i" (&tp.state));
#endif

entry:
	asm goto ("" :::: entry);
	return 0;
}
END
