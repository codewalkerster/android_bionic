/*
 * Copyright (C) 2008 The Android Open Source Project
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in
 *    the documentation and/or other materials provided with the
 *    distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
 * OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
 * AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
 * OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include <machine/cpu-features.h>
#include <machine/asm.h>

#if defined(__ARM_NEON__) && !defined(ARCH_ARM_USE_NON_NEON_MEMCPY)

	.text
	.fpu	neon
	.arm
	.arch	armv7-a

#ifdef HAVE_32_BYTE_CACHE_LINE
/* a prefetch distance of 2 cache-lines */
#define CACHE_LINE_SIZE		32
#define PREFETCH_DISTANCE	(CACHE_LINE_SIZE*2)
#else
/* a prefetch distance of 8 cache-lines works best experimentally */
#define CACHE_LINE_SIZE		64
#define PREFETCH_OFFSET		8
#define PREFETCH_DISTANCE	(CACHE_LINE_SIZE*PREFETCH_OFFSET)
#endif
#define CROSS_BOUND		(64*1024/128)
#define CROSS_BOUND_SIZE	(64*1024)

#if defined(ARCH_ARM_USE_MEMCPY_ALIGNMENT)
#ifndef MEMCPY_ALIGN_BOUND
#define MEMCPY_ALIGN_BOUND	(32*1024)
#endif
#ifndef MEMCPY_ALIGNMENT
#define MEMCPY_ALIGNMENT	(64)
#endif
#endif

	dst	.req	r0
	src	.req	r1
	cnt	.req	r2
	tmp1	.req	r3
	tmp2	.req	ip
	csrc1	.req	r4
	csrc2	.req	r6
	csrc3	.req	r8
	cdst1	.req	r3
	cdst2	.req	r5
	cdst3	.req	r7
	coff	.req	r9
	ccnt1	.req	r10
	ccnt2	.req	r11

ENTRY(memcpy)
#if defined(ARCH_ARM_USE_MEMCPY_ALIGNMENT)
	cmp	cnt, #MEMCPY_ALIGN_BOUND
	blt	nmemcpy
	cmp	cnt, #CROSS_BOUND_SIZE
	beq	nmemcpy
	ands	tmp1, dst, #(MEMCPY_ALIGNMENT-1)
	bne	make_align
#endif
	b	nmemcpy
END(memcpy)

#if defined(ARCH_ARM_USE_MEMCPY_ALIGNMENT)
make_align:
	push	{dst, ccnt1, ccnt2, lr}
	/* backup cnt */
	mov	ccnt1, cnt
	mov	tmp2, #MEMCPY_ALIGNMENT
	/* cnt for alignment */
	sub	cnt, tmp2, tmp1
	/* backup aligned cnt */
	mov	ccnt2, cnt
	bl	nmemcpy
	/* make aligned address and cnt */
	add	dst, dst, ccnt2
	sub	cnt, ccnt1, ccnt2
	bl	nmemcpy
	mov	cnt, ccnt1
	pop	{dst, ccnt1, ccnt2, lr}
	bx	lr
#endif

nmemcpy:
	push		{dst}
/* start preloading as early as possible */
	pld		[src, #(CACHE_LINE_SIZE*0)]
	cmp		cnt, #4
	blt		.memcpy_lt4
	cmp		cnt, #16
	blt		.memcpy_lt16
	cmp		cnt, #32
	blt		.memcpy_16
	pld		[src, #(CACHE_LINE_SIZE*1)]
	cmp		cnt, #128
	blt		.memcpy_32
	pld		[src, #(CACHE_LINE_SIZE*2)]
	pld		[src, #(CACHE_LINE_SIZE*3)]
	mov		tmp2, cnt, lsr #7
	cmp		tmp2, #PREFETCH_OFFSET
	ble		.memcpy_copy_128_loop_nopld
	sub		tmp2, #PREFETCH_OFFSET
	pld		[src, #(CACHE_LINE_SIZE*4)]
	pld		[src, #(CACHE_LINE_SIZE*5)]
	pld		[src, #(CACHE_LINE_SIZE*6)]
	pld		[src, #(CACHE_LINE_SIZE*7)]
	pld		[src, #PREFETCH_DISTANCE]
	/* check cross copy boundary */
	subs		tmp1, src, dst
	bls		.check_cross_copy_boundary
	cmp		tmp1, #128
	bls		.memcpy_copy_128_loop
.check_cross_copy_boundary:
	add		tmp1, tmp2, #PREFETCH_OFFSET
	cmp		tmp1, #CROSS_BOUND
	beq		.memcpy_copy_128_cross

.memcpy_copy_128_loop:
	vld1.64		{d0-d1}, [src]!
	vst1.64		{d0-d1}, [dst]!
	vld1.64		{d0-d1}, [src]!
	vst1.64		{d0-d1}, [dst]!
	vld1.64		{d0-d1}, [src]!
	vst1.64		{d0-d1}, [dst]!
	vld1.64		{d0-d1}, [src]!
	vst1.64		{d0-d1}, [dst]!
	pld		[src, #PREFETCH_DISTANCE]
	vld1.64		{d0-d1}, [src]!
	vst1.64		{d0-d1}, [dst]!
	vld1.64		{d0-d1}, [src]!
	vst1.64		{d0-d1}, [dst]!
	vld1.64		{d0-d1}, [src]!
	vst1.64		{d0-d1}, [dst]!
	vld1.64		{d0-d1}, [src]!
	vst1.64		{d0-d1}, [dst]!
	pld		[src, #PREFETCH_DISTANCE]
	subs		tmp2, tmp2, #1
	bne		.memcpy_copy_128_loop
	mov		tmp2, #PREFETCH_OFFSET
	b		.memcpy_copy_128_loop_nopld

.memcpy_copy_128_cross:
	push		{r4-r9}
	add		csrc1, src, #16
	add		cdst1, dst, #16
	add		csrc2, src, #32
	add		cdst2, dst, #32
	add		csrc3, src, #48
	add		cdst3, dst, #48
	mov		coff, #64
.memcpy_copy_128_cross_loop:
	vld1.64		{d0-d1}, [src], coff
	vst1.64		{d0-d1}, [dst], coff
	vld1.64		{d0-d1}, [csrc1], coff
	vst1.64		{d0-d1}, [cdst1], coff
	vld1.64		{d0-d1}, [csrc3], coff
	vst1.64		{d0-d1}, [cdst3], coff
	vld1.64		{d0-d1}, [csrc2], coff
	vst1.64		{d0-d1}, [cdst2], coff
	pld		[r1, #PREFETCH_DISTANCE]
	vld1.64		{d0-d1}, [src], coff
	vst1.64		{d0-d1}, [dst], coff
	vld1.64		{d0-d1}, [csrc1], coff
	vst1.64		{d0-d1}, [cdst1], coff
	vld1.64		{d0-d1}, [csrc3], coff
	vst1.64		{d0-d1}, [cdst3], coff
	vld1.64		{d0-d1}, [csrc2], coff
	vst1.64		{d0-d1}, [cdst2], coff
	pld		[r1, #PREFETCH_DISTANCE]
	subs		tmp2, tmp2, #1
	bne		.memcpy_copy_128_cross_loop
	mov		tmp2, #PREFETCH_OFFSET
	pop		{r4-r9}

.memcpy_copy_128_loop_nopld:
	vld1.64		{d0-d1}, [src]!
	vst1.64		{d0-d1}, [dst]!
	vld1.64		{d0-d1}, [src]!
	vst1.64		{d0-d1}, [dst]!
	vld1.64		{d0-d1}, [src]!
	vst1.64		{d0-d1}, [dst]!
	vld1.64		{d0-d1}, [src]!
	vst1.64		{d0-d1}, [dst]!
	vld1.64		{d0-d1}, [src]!
	vst1.64		{d0-d1}, [dst]!
	vld1.64		{d0-d1}, [src]!
	vst1.64		{d0-d1}, [dst]!
	vld1.64		{d0-d1}, [src]!
	vst1.64		{d0-d1}, [dst]!
	vld1.64		{d0-d1}, [src]!
	vst1.64		{d0-d1}, [dst]!
	subs		tmp2, tmp2, #1
	bne		.memcpy_copy_128_loop_nopld
	ands		cnt, cnt, #0x7f
	beq		.memcpy_end
	cmp		cnt, #32
	blt		.memcpy_16
.memcpy_32:
	mov		tmp2, cnt, lsr #5
.memcpy_copy_32_loop:
	vld1.64		{d0-d1}, [src]!
	vst1.64		{d0-d1}, [dst]!
	vld1.64		{d0-d1}, [src]!
	vst1.64		{d0-d1}, [dst]!
	subs		tmp2, tmp2, #1
	bne		.memcpy_copy_32_loop
	ands		cnt, cnt, #0x1f
	beq		.memcpy_end
.memcpy_16:
	subs            cnt, cnt, #16
	blt		.memcpy_lt16
	vld1.64		{d0-d1}, [src]!
	vst1.64		{d0-d1}, [dst]!
	beq		.memcpy_end
.memcpy_lt16:
	movs		tmp2, cnt, lsl #29
	bcc		.memcpy_skip8
	ldr		tmp1, [src], #4
	str		tmp1, [dst], #4
	ldr		tmp2, [src], #4
	str		tmp2, [dst], #4
.memcpy_skip8:
	bpl		.memcpy_lt4
	ldr		tmp1, [src], #4
	str		tmp1, [dst], #4
.memcpy_lt4:
	movs		cnt, cnt, lsl #31
	bcc		.memcpy_lt2
	ldrh		tmp1, [src], #2
	strh		tmp1, [dst], #2
.memcpy_lt2:
	bpl		.memcpy_end
	ldrb		tmp2, [src], #1
	strb		tmp2, [dst], #1
.memcpy_end:
	pop		{dst}
	bx		lr

#else   /* __ARM_ARCH__ < 7 */


		/*
		 * Optimized memcpy() for ARM.
         *
		 * note that memcpy() always returns the destination pointer,
		 * so we have to preserve R0.
		 */

ENTRY(memcpy)
		/* The stack must always be 64-bits aligned to be compliant with the
		 * ARM ABI. Since we have to save R0, we might as well save R4
		 * which we can use for better pipelining of the reads below
		 */
        .save       {r0, r4, lr}
        stmfd       sp!, {r0, r4, lr}
        /* Making room for r5-r11 which will be spilled later */
        .pad        #28
        sub         sp, sp, #28

        // preload the destination because we'll align it to a cache line
        // with small writes. Also start the source "pump".
        PLD         (r0, #0)
        PLD         (r1, #0)
        PLD         (r1, #32)

		/* it simplifies things to take care of len<4 early */
		cmp			r2, #4
		blo			copy_last_3_and_return

		/* compute the offset to align the source
		 * offset = (4-(src&3))&3 = -src & 3
		 */
		rsb			r3, r1, #0
		ands		r3, r3, #3
		beq			src_aligned

		/* align source to 32 bits. We need to insert 2 instructions between
		 * a ldr[b|h] and str[b|h] because byte and half-word instructions
		 * stall 2 cycles.
		 */
		movs		r12, r3, lsl #31
		sub			r2, r2, r3		/* we know that r3 <= r2 because r2 >= 4 */
		ldrmib		r3, [r1], #1
		ldrcsb		r4, [r1], #1
		ldrcsb		r12,[r1], #1
        strmib		r3, [r0], #1
		strcsb		r4, [r0], #1
		strcsb		r12,[r0], #1

src_aligned:

		/* see if src and dst are aligned together (congruent) */
		eor			r12, r0, r1
		tst			r12, #3
		bne			non_congruent

        /* Use post-incriment mode for stm to spill r5-r11 to reserved stack
         * frame. Don't update sp.
         */
        stmea		sp, {r5-r11}

		/* align the destination to a cache-line */
		rsb         r3, r0, #0
		ands		r3, r3, #0x1C
		beq         congruent_aligned32
		cmp         r3, r2
		andhi		r3, r2, #0x1C

		/* conditionnaly copies 0 to 7 words (length in r3) */
		movs		r12, r3, lsl #28
		ldmcsia		r1!, {r4, r5, r6, r7}	/* 16 bytes */
		ldmmiia		r1!, {r8, r9}			/*  8 bytes */
		stmcsia		r0!, {r4, r5, r6, r7}
		stmmiia		r0!, {r8, r9}
		tst         r3, #0x4
		ldrne		r10,[r1], #4			/*  4 bytes */
		strne		r10,[r0], #4
		sub         r2, r2, r3

congruent_aligned32:
		/*
		 * here source is aligned to 32 bytes.
		 */

cached_aligned32:
        subs        r2, r2, #32
        blo         less_than_32_left

        /*
         * We preload a cache-line up to 64 bytes ahead. On the 926, this will
         * stall only until the requested world is fetched, but the linefill
         * continues in the the background.
         * While the linefill is going, we write our previous cache-line
         * into the write-buffer (which should have some free space).
         * When the linefill is done, the writebuffer will
         * start dumping its content into memory
         *
         * While all this is going, we then load a full cache line into
         * 8 registers, this cache line should be in the cache by now
         * (or partly in the cache).
         *
         * This code should work well regardless of the source/dest alignment.
         *
         */

        // Align the preload register to a cache-line because the cpu does
        // "critical word first" (the first word requested is loaded first).
        bic         r12, r1, #0x1F
        add         r12, r12, #64

1:      ldmia       r1!, { r4-r11 }
        PLD         (r12, #64)
        subs        r2, r2, #32

        // NOTE: if r12 is more than 64 ahead of r1, the following ldrhi
        // for ARM9 preload will not be safely guarded by the preceding subs.
        // When it is safely guarded the only possibility to have SIGSEGV here
        // is because the caller overstates the length.
        ldrhi       r3, [r12], #32      /* cheap ARM9 preload */
        stmia       r0!, { r4-r11 }
		bhs         1b

        add         r2, r2, #32




less_than_32_left:
		/*
		 * less than 32 bytes left at this point (length in r2)
		 */

		/* skip all this if there is nothing to do, which should
		 * be a common case (if not executed the code below takes
		 * about 16 cycles)
		 */
		tst			r2, #0x1F
		beq			1f

		/* conditionnaly copies 0 to 31 bytes */
		movs		r12, r2, lsl #28
		ldmcsia		r1!, {r4, r5, r6, r7}	/* 16 bytes */
		ldmmiia		r1!, {r8, r9}			/*  8 bytes */
		stmcsia		r0!, {r4, r5, r6, r7}
		stmmiia		r0!, {r8, r9}
		movs		r12, r2, lsl #30
		ldrcs		r3, [r1], #4			/*  4 bytes */
		ldrmih		r4, [r1], #2			/*  2 bytes */
		strcs		r3, [r0], #4
		strmih		r4, [r0], #2
		tst         r2, #0x1
		ldrneb		r3, [r1]				/*  last byte  */
		strneb		r3, [r0]

		/* we're done! restore everything and return */
1:		ldmfd		sp!, {r5-r11}
		ldmfd		sp!, {r0, r4, lr}
		bx			lr

		/********************************************************************/

non_congruent:
		/*
		 * here source is aligned to 4 bytes
		 * but destination is not.
		 *
		 * in the code below r2 is the number of bytes read
		 * (the number of bytes written is always smaller, because we have
		 * partial words in the shift queue)
		 */
		cmp			r2, #4
		blo			copy_last_3_and_return

        /* Use post-incriment mode for stm to spill r5-r11 to reserved stack
         * frame. Don't update sp.
         */
        stmea		sp, {r5-r11}

		/* compute shifts needed to align src to dest */
		rsb			r5, r0, #0
		and			r5, r5, #3			/* r5 = # bytes in partial words */
		mov			r12, r5, lsl #3		/* r12 = right */
		rsb			lr, r12, #32		/* lr = left  */

		/* read the first word */
		ldr			r3, [r1], #4
		sub			r2, r2, #4

		/* write a partial word (0 to 3 bytes), such that destination
		 * becomes aligned to 32 bits (r5 = nb of words to copy for alignment)
		 */
		movs		r5, r5, lsl #31
		strmib		r3, [r0], #1
		movmi		r3, r3, lsr #8
		strcsb		r3, [r0], #1
		movcs		r3, r3, lsr #8
		strcsb		r3, [r0], #1
		movcs		r3, r3, lsr #8

		cmp			r2, #4
		blo			partial_word_tail

		/* Align destination to 32 bytes (cache line boundary) */
1:		tst			r0, #0x1c
		beq			2f
		ldr			r5, [r1], #4
		sub         r2, r2, #4
		orr			r4, r3, r5,		lsl lr
		mov			r3, r5,			lsr r12
		str			r4, [r0], #4
        cmp         r2, #4
		bhs			1b
		blo			partial_word_tail

		/* copy 32 bytes at a time */
2:		subs		r2, r2, #32
		blo			less_than_thirtytwo

		/* Use immediate mode for the shifts, because there is an extra cycle
		 * for register shifts, which could account for up to 50% of
		 * performance hit.
		 */

        cmp			r12, #24
		beq			loop24
		cmp			r12, #8
		beq			loop8

loop16:
        ldr         r12, [r1], #4
1:      mov         r4, r12
		ldmia		r1!, {   r5,r6,r7,  r8,r9,r10,r11}
        PLD         (r1, #64)
        subs        r2, r2, #32
        ldrhs       r12, [r1], #4
		orr			r3, r3, r4,		lsl #16
		mov			r4, r4,			lsr #16
		orr			r4, r4, r5,		lsl #16
		mov			r5, r5,			lsr #16
		orr			r5, r5, r6,		lsl #16
		mov			r6, r6,			lsr #16
		orr			r6, r6, r7,		lsl #16
		mov			r7, r7,			lsr #16
		orr			r7, r7, r8,		lsl #16
		mov			r8, r8,			lsr #16
		orr			r8, r8, r9,		lsl #16
		mov			r9, r9,			lsr #16
		orr			r9, r9, r10,	lsl #16
		mov			r10, r10,		lsr #16
		orr			r10, r10, r11,	lsl #16
		stmia		r0!, {r3,r4,r5,r6, r7,r8,r9,r10}
		mov			r3, r11,		lsr #16
		bhs			1b
		b			less_than_thirtytwo

loop8:
        ldr         r12, [r1], #4
1:      mov         r4, r12
		ldmia		r1!, {   r5,r6,r7,  r8,r9,r10,r11}
        PLD         (r1, #64)
		subs		r2, r2, #32
        ldrhs       r12, [r1], #4
		orr			r3, r3, r4,		lsl #24
		mov			r4, r4,			lsr #8
		orr			r4, r4, r5,		lsl #24
		mov			r5, r5,			lsr #8
		orr			r5, r5, r6,		lsl #24
		mov			r6, r6,			lsr #8
		orr			r6, r6, r7,		lsl #24
		mov			r7, r7,			lsr #8
		orr			r7, r7, r8,		lsl #24
		mov			r8, r8,			lsr #8
		orr			r8, r8, r9,		lsl #24
		mov			r9, r9,			lsr #8
		orr			r9, r9, r10,	lsl #24
		mov			r10, r10,		lsr #8
		orr			r10, r10, r11,	lsl #24
		stmia		r0!, {r3,r4,r5,r6, r7,r8,r9,r10}
		mov			r3, r11,		lsr #8
		bhs			1b
		b			less_than_thirtytwo

loop24:
        ldr         r12, [r1], #4
1:      mov         r4, r12
		ldmia		r1!, {   r5,r6,r7,  r8,r9,r10,r11}
        PLD         (r1, #64)
		subs		r2, r2, #32
        ldrhs       r12, [r1], #4
		orr			r3, r3, r4,		lsl #8
		mov			r4, r4,			lsr #24
		orr			r4, r4, r5,		lsl #8
		mov			r5, r5,			lsr #24
		orr			r5, r5, r6,		lsl #8
		mov			r6, r6,			lsr #24
		orr			r6, r6, r7,		lsl #8
		mov			r7, r7,			lsr #24
		orr			r7, r7, r8,		lsl #8
		mov			r8, r8,			lsr #24
		orr			r8, r8, r9,		lsl #8
		mov			r9, r9,			lsr #24
		orr			r9, r9, r10,	lsl #8
		mov			r10, r10,		lsr #24
		orr			r10, r10, r11,	lsl #8
		stmia		r0!, {r3,r4,r5,r6, r7,r8,r9,r10}
		mov			r3, r11,		lsr #24
		bhs			1b


less_than_thirtytwo:
		/* copy the last 0 to 31 bytes of the source */
		rsb			r12, lr, #32		/* we corrupted r12, recompute it  */
		add			r2, r2, #32
		cmp			r2, #4
		blo			partial_word_tail

1:		ldr			r5, [r1], #4
		sub         r2, r2, #4
		orr			r4, r3, r5,		lsl lr
		mov			r3,	r5,			lsr r12
		str			r4, [r0], #4
        cmp         r2, #4
		bhs			1b

partial_word_tail:
		/* we have a partial word in the input buffer */
		movs		r5, lr, lsl #(31-3)
		strmib		r3, [r0], #1
		movmi		r3, r3, lsr #8
		strcsb		r3, [r0], #1
		movcs		r3, r3, lsr #8
		strcsb		r3, [r0], #1

		/* Refill spilled registers from the stack. Don't update sp. */
		ldmfd		sp, {r5-r11}

copy_last_3_and_return:
		movs		r2, r2, lsl #31	/* copy remaining 0, 1, 2 or 3 bytes */
		ldrmib		r2, [r1], #1
		ldrcsb		r3, [r1], #1
		ldrcsb		r12,[r1]
		strmib		r2, [r0], #1
		strcsb		r3, [r0], #1
		strcsb		r12,[r0]

        /* we're done! restore sp and spilled registers and return */
        add         sp,  sp, #28
		ldmfd		sp!, {r0, r4, lr}
		bx			lr
END(memcpy)


#endif    /* __ARM_ARCH__ < 7 */
