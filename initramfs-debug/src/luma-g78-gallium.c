// SPDX-License-Identifier: Unlicense
// luma-g78-gallium IN OUT: copia libgallium cambiando l'unica voce panfrost G57 PAN_PROD_ID(9,0,3) in
// PAN_PROD_ID(9,2,2) (Mali-G78: stessi parametri, cfr. omarchy-mobile mesa 0004). Ripiego finché Luma
// non distribuisce Mesa con il G78. Statico, senza libc (aarch64).
#define SYS_openat 56
#define SYS_close 57
#define SYS_write 64
#define SYS_fstat 80
#define SYS_exit 93
#define SYS_mmap 222
typedef unsigned long u64; typedef unsigned int u32;
static long sc6(long n,long a,long b,long c,long d,long e,long f){
	register long x8 __asm__("x8")=n,x0 __asm__("x0")=a,x1 __asm__("x1")=b,x2 __asm__("x2")=c,x3 __asm__("x3")=d,x4 __asm__("x4")=e,x5 __asm__("x5")=f;
	__asm__ volatile("svc 0":"+r"(x0):"r"(x8),"r"(x1),"r"(x2),"r"(x3),"r"(x4),"r"(x5):"memory"); return x0; }
static void die(int c){ sc6(SYS_exit,c,0,0,0,0,0); for(;;){} }
static const u32 head[2]={0x090003,0}, tail[9]={0,16384,8192,2,4,8,32,32,8};
static int eq(const unsigned char*p,const u32*w,int n){ for(int i=0;i<n;i++){ u32 v=p[4*i]|p[4*i+1]<<8|p[4*i+2]<<16|(u32)p[4*i+3]<<24; if(v!=w[i]) return 0;} return 1; }
void _start_c(long*sp){
	char**argv=(char**)(sp+1); if(sp[0]!=3) die(2);
	long in=sc6(SYS_openat,-100,(long)argv[1],0,0,0,0); if(in<0) die(3);
	u64 st[16]; if(sc6(SYS_fstat,in,(long)st,0,0,0,0)<0) die(3); u64 sz=st[6];
	unsigned char*b=(unsigned char*)sc6(SYS_mmap,0,sz,3,2/*MAP_PRIVATE*/,in,0); if((long)b<0&&(long)b>-4096) die(4);
	long hit=-1; int n=0;
	for(u64 o=0;o+4*11+16<=sz;o+=4) if(eq(b+o,head,2)&&eq(b+o+24,tail,9)){ hit=o; n++; }
	if(n!=1) die(5);
	b[hit]=0x02; b[hit+1]=0x02; b[hit+2]=0x09; b[hit+3]=0x00;
	long out=sc6(SYS_openat,-100,(long)argv[2],1|0100|01000,0755,0,0); if(out<0) die(6);
	for(u64 w=0;w<sz;){ long r=sc6(SYS_write,out,(long)(b+w),sz-w,0,0,0); if(r<=0) die(7); w+=r; }
	sc6(SYS_close,out,0,0,0,0,0); die(0); }
__asm__(".globl _start\n_start:\n mov x0, sp\n bl _start_c\n");
