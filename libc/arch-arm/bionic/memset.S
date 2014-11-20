/* Copyright (c) 2010-2011, Linaro Limited
   All rights reserved.

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

      * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.

      * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.

      * Neither the name of Linaro Limited nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
   HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

   Written by Dave Gilbert <david.gilbert@linaro.org>
   Adapted to Bionic by Bernhard Rosenkraenzer <Bernhard.Rosenkranzer@linaro.org>

   This memset routine is optimised on a Cortex-A9 and should work on
   all ARMv7 processors. */

#include <machine/cpu-features.h>
#include <machine/asm.h>

	.syntax unified
	.arch armv7-a


@ 2011-08-30 david.gilbert@linaro.org
@    Extracted from local git 2f11b436

@ this lets us check a flag in a 00/ff byte easily in either endianness
#ifdef __ARMEB__
#define CHARTSTMASK(c) 1<<(31-(c*8))
#else
#define CHARTSTMASK(c) 1<<(c*8)
#endif
	.text
	.thumb

@ ---------------------------------------------------------------------------
    .code   32
	.p2align 4,,15

ENTRY(bzero)
    mov     r2, r1
    mov     r1, #0
END(bzero)

ENTRY(memset)
    and     r1, r1, #0xff
    cmp     r2, #0
    bxeq    lr
    orr     r1, r1, r1, lsl #8
    tst     r0, #7
    mov     r3, r0
    orr     r1, r1, r1, lsl #16
    beq     .Lmemset_align8
.Lmemset_make_align:
    strb    r1, [r3], #1
    subs    r2, r2, #1
    bxeq    lr
    tst     r3, #7
    bne     .Lmemset_make_align

.Lmemset_align8:
    cmp     r2, #16
    mov     r12, r1
    blt     .Lmemset_less16
    push    {r4, lr}
    mov     r4, r1
    mov     lr, r1
.Lmemset_loop32:
    subs    r2, r2, #32
    stmhsia r3!, {r1, r4, r12, lr}
    stmhsia r3!, {r1, r4, r12, lr}
    bhs     .Lmemset_loop32
    adds    r2, r2, #32
    popeq   {r4, pc}
    tst     r2, #16
    stmneia r3!, {r1, r4, r12, lr}
    pop     {r4, lr}
    subs    r2, #16
    bxeq    lr
.Lmemset_less16:
    movs    r2, r2, lsl #29
    stmcsia r3!, {r1, r12}
    strmi   r1, [r3], #4
    movs    r2, r2, lsl #2
    strhcs  r1, [r3], #2
    strbmi  r1, [r3], #1
    bx      lr

		/*
		 * Optimized memset() for ARM.
         *
         * memset() returns its first argument.
		 */

#if defined(__ARM_NEON__)
    .fpu    neon
#endif

ENTRY(bzero)
        mov     r2, r1
        mov     r1, #0
        // Fall through to memset...
END(bzero)

ENTRY(memset)
#if defined(__ARM_NEON__)

#ifdef  NEON_MEMSET_DIVIDER
        cmp         r2, #NEON_MEMSET_DIVIDER
        bhi         11f
#endif
        .save       {r0}
        stmfd       sp!, {r0}

        vdup.8      q0, r1

#ifndef NEON_UNALIGNED_ACCESS
        /* do we have at least 16-bytes to write (needed for alignment below) */
        cmp         r2, #16
        blo         3f

        /* align destination to 16 bytes for the write-buffer */
        rsb         r3, r0, #0
        ands        r3, r3, #0xF
        beq         2f

        /* write up to 15-bytes (count in r3) */
        sub         r2, r2, r3
        movs        ip, r3, lsl #31
        strmib      r1, [r0], #1
        strcsb      r1, [r0], #1
        strcsb      r1, [r0], #1
        movs        ip, r3, lsl #29
        bge         1f

        // writes 4 bytes, 32-bits aligned
        vst1.32     {d0[0]}, [r0, :32]!
1:      bcc         2f

        // writes 8 bytes, 64-bits aligned
        vst1.8      {d0}, [r0, :64]!
2:
#endif
        /* make sure we have at least 32 bytes to write */
        subs        r2, r2, #32
        blo         2f
        vmov        q1, q0

1:      /* The main loop writes 32 bytes at a time */
        subs        r2, r2, #32
#ifndef NEON_UNALIGNED_ACCESS
        vst1.8      {d0 - d3}, [r0, :128]!
#else
        vst1.8      {d0 - d3}, [r0]!
#endif
        bhs         1b

2:      /* less than 32 left */
        add         r2, r2, #32
        tst         r2, #0x10
        beq         3f

        // writes 16 bytes, 128-bits aligned
#ifndef NEON_UNALIGNED_ACCESS
        vst1.8      {d0, d1}, [r0, :128]!
#else
        vst1.8      {d0, d1}, [r0]!
#endif
3:      /* write up to 15-bytes (count in r2) */
        movs        ip, r2, lsl #29
        bcc         1f
        vst1.8      {d0}, [r0]!
1:      bge         2f
        vst1.32     {d0[0]}, [r0]!
2:      movs        ip, r2, lsl #31
        strmib      r1, [r0], #1
        strcsb      r1, [r0], #1
        strcsb      r1, [r0], #1
        ldmfd       sp!, {r0}
        bx          lr
11:
#endif

        /*
         * Optimized memset() for ARM.
         *
         * memset() returns its first argument.
         */

		/* compute the offset to align the destination
		 * offset = (4-(src&3))&3 = -src & 3
		 */

        .save       {r0, r4-r7, lr}
		stmfd		sp!, {r0, r4-r7, lr}
		rsb			r3, r0, #0
		ands		r3, r3, #3
        cmp         r3, r2
        movhi       r3, r2

        /* splat r1 */
        mov         r1, r1, lsl #24
        orr         r1, r1, r1, lsr #8
        orr         r1, r1, r1, lsr #16

		movs		r12, r3, lsl #31
		strcsb		r1, [r0], #1    /* can't use strh (alignment unknown) */
		strcsb		r1, [r0], #1
		strmib		r1, [r0], #1
		subs		r2, r2, r3
        ldmlsfd     sp!, {r0, r4-r7, lr}   /* return */
        bxls        lr

		/* align the destination to a cache-line */
        mov         r12, r1
        mov         lr, r1
        mov         r4, r1
        mov         r5, r1
        mov         r6, r1
        mov         r7, r1

		rsb         r3, r0, #0
		ands		r3, r3, #0x1C
		beq         3f
		cmp         r3, r2
		andhi		r3, r2, #0x1C
		sub         r2, r2, r3

		/* conditionally writes 0 to 7 words (length in r3) */
		movs		r3, r3, lsl #28
		stmcsia		r0!, {r1, lr}
		stmcsia		r0!, {r1, lr}
		stmmiia		r0!, {r1, lr}
		movs		r3, r3, lsl #2
        strcs       r1, [r0], #4

3:
        subs        r2, r2, #32
        mov         r3, r1
        bmi         2f
1:      subs        r2, r2, #32
        stmia		r0!, {r1,r3,r4,r5,r6,r7,r12,lr}
        bhs         1b
2:      add         r2, r2, #32

		/* conditionally stores 0 to 31 bytes */
		movs		r2, r2, lsl #28
		stmcsia		r0!, {r1,r3,r12,lr}
		stmmiia		r0!, {r1, lr}
		movs		r2, r2, lsl #2
        strcs       r1, [r0], #4
		strmih		r1, [r0], #2
		movs		r2, r2, lsl #2
		strcsb		r1, [r0]
        ldmfd		sp!, {r0, r4-r7, lr}
        bx          lr
END(memset)
