// SPDX-License-Identifier: Unlicense
// luma-devmem ADDR [VALUE]: legge/scrive 32 bit in /dev/mem. Statico, senza libc (aarch64).
#define SYS_openat 56
#define SYS_close 57
#define SYS_write 64
#define SYS_exit 93
#define SYS_mmap 222
static long sc6(long n,long a,long b,long c,long d,long e,long f){
	register long x8 __asm__("x8")=n,x0 __asm__("x0")=a,x1 __asm__("x1")=b,x2 __asm__("x2")=c,x3 __asm__("x3")=d,x4 __asm__("x4")=e,x5 __asm__("x5")=f;
	__asm__ volatile("svc 0":"+r"(x0):"r"(x8),"r"(x1),"r"(x2),"r"(x3),"r"(x4),"r"(x5):"memory"); return x0; }
static unsigned long hex(const char*s){unsigned long v=0; if(s[0]=='0'&&(s[1]=='x'||s[1]=='X'))s+=2;
	for(;*s;s++){int c=*s; v=v*16+(c<='9'?c-'0':(c|32)-'a'+10);} return v;}
static void out(unsigned v){char b[11]="0x00000000\n";for(int i=0;i<8;i++){int n=(v>>(28-4*i))&15;b[2+i]=n<10?'0'+n:'a'+n-10;}sc6(SYS_write,1,(long)b,11,0,0,0);}
void _start_c(long*sp){
	char**argv=(char**)(sp+1); if(sp[0]<2) sc6(SYS_exit,2,0,0,0,0,0);
	unsigned long a=hex(argv[1]), pg=a&~0xfffUL;
	long fd=sc6(SYS_openat,-100,(long)"/dev/mem",2|0x101000/*O_RDWR|O_SYNC*/,0,0,0); if(fd<0) sc6(SYS_exit,3,0,0,0,0,0);
	long m=sc6(SYS_mmap,0,4096,3,1,fd,pg); if(m<0&&m>-4096) sc6(SYS_exit,4,0,0,0,0,0);
	volatile unsigned *r=(volatile unsigned*)(m+(a-pg));
	if(sp[0]>2) *r=(unsigned)hex(argv[2]);
	out(*r); sc6(SYS_exit,0,0,0,0,0,0); for(;;){} }
__asm__(".globl _start\n_start:\n mov x0, sp\n bl _start_c\n");
