// SPDX-License-Identifier: Unlicense
// luma-reboot <motivo>: reboot(RESTART2, motivo), es. "bootloader". Statico, senza libc (aarch64).
#define SYS_sync 81
#define SYS_reboot 142
static long sc4(long n, long a, long b, long c, long d) {
	register long x8 __asm__("x8") = n, x0 __asm__("x0") = a, x1 __asm__("x1") = b, x2 __asm__("x2") = c, x3 __asm__("x3") = d;
	__asm__ volatile("svc 0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3) : "memory");
	return x0;
}
void _start_c(long *sp) {
	char **argv = (char **)(sp + 1);
	const char *why = (sp[0] > 1) ? argv[1] : "bootloader";
	sc4(SYS_sync, 0, 0, 0, 0);
	sc4(SYS_reboot, 0xfee1dead, 672274793, 0xA1B2C3D4 /* RESTART2 */, (long)why);
	sc4(93 /* exit */, 1, 0, 0, 0);
	for (;;) {}
}
__asm__(".globl _start\n_start:\n mov x0, sp\n bl _start_c\n");
