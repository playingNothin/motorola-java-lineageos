# Warning

These drivers **must be built as loadable modules** (=m).

If you compile them into the kernel image (=y), the phone will bootloop.
The probes try to power the CP2 chip during kernel init, before the chip
is ready. Recovery and fastboot become unreachable and you'll need a
test point or ResearchDownload to get back in.

This was tested. It bootloops. Don't do it.
