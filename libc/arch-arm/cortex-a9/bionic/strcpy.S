/*
 * Copyright (C) 2010 The Android Open Source Project
 * Copyright (c) 2008 ARM Ltd
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. The name of the company may not be used to endorse or promote
 *    products derived from this software without specific prior written
 *    permission.
 *
 * THIS SOFTWARE IS PROVIDED BY ARM LTD ``AS IS'' AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL ARM LTD BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 * TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * Android adaptation and tweak by Jim Huang <jserv@0xlab.org>.
 */

#include <machine/cpu-features.h>
#include <machine/asm.h>

#if 0
ENTRY(strcpy)
	PLD(r1, #0)
	eor	r2, r0, r1
	mov	ip, r0
	tst	r2, #3
	bne	4f
	tst	r1, #3
	bne	3f
5:
	str	r5, [sp, #-4]!
	mov	r5, #0x01
	orr	r5, r5, r5, lsl #8
	orr	r5, r5, r5, lsl #16

	str	r4, [sp, #-4]!
	tst	r1, #4
	ldr	r3, [r1], #4
	beq	2f
	sub	r2, r3, r5
	bics	r2, r2, r3
	tst	r2, r5, lsl #7
	itt	eq
	streq	r3, [ip], #4
	ldreq	r3, [r1], #4
	bne	1f
       /* Inner loop.  We now know that r1 is 64-bit aligned, so we
	  can safely fetch up to two words.  This allows us to avoid
	  load stalls.  */
	.p2align 2
2:
	PLD(r1, #8)
	ldr	r4, [r1], #4
	sub	r2, r3, r5
	bics	r2, r2, r3
	tst	r2, r5, lsl #7
	sub	r2, r4, r5
	bne	1f
	str	r3, [ip], #4
	bics	r2, r2, r4
	tst	r2, r5, lsl #7
	itt	eq
	ldreq	r3, [r1], #4
	streq	r4, [ip], #4
	beq	2b
	mov	r3, r4
1:
#ifdef __ARMEB__
	rors	r3, r3, #24
#endif
	strb	r3, [ip], #1
	tst	r3, #0xff
#ifdef __ARMEL__
	ror	r3, r3, #8
#endif
	bne	1b
	ldr	r4, [sp], #4
	ldr	r5, [sp], #4
	bx	lr

       /* Strings have the same offset from word alignment, but it's
	  not zero.  */
3:
	tst	r1, #1
	beq	1f
	ldrb	r2, [r1], #1
	strb	r2, [ip], #1
	cmp	r2, #0
	it	eq
	bxeq	lr
1:
	tst	r1, #2
	beq	5b
	ldrh	r2, [r1], #2
#ifdef __ARMEB__
	tst	r2, #0xff00
	iteet	ne
	strneh	r2, [ip], #2
	lsreq	r2, r2, #8
	streqb	r2, [ip]
	tstne	r2, #0xff
#else
	tst	r2, #0xff
	itet	ne
	strneh	r2, [ip], #2
	streqb	r2, [ip]
	tstne	r2, #0xff00
#endif
	bne	5b
	bx	lr

       /* src and dst do not have a common word-alignement.  Fall back to
	  byte copying.  */
4:
	ldrb	r2, [r1], #1
	strb	r2, [ip], #1
	cmp	r2, #0
	bne	4b
	bx	lr
END(strcpy)

#else

ENTRY(strcpy)
    /* char*  strcpy(char *, const char *); */
strcpy_t:
    pld         [r1]
    eor         r12, r0, r1
    tst         r12, #0x03
    mov         r12, r0
    bne         .Lstrcpy_nalign
    tst         r1,  #0x03
    beq         .Lstrcpy_align

.Lstrcpy_make_align:
    ldrb        r3, [r1], #1
    strb        r3, [r12], #1
    cmp         r3, #0
    bxeq        lr
    tst         r1, #0x03
    bne         .Lstrcpy_make_align

.Lstrcpy_align:
    push        {r4, r5, r6, lr}
    mov         r4, #0
    mvn         r5, #0
.Lstrcpy_align_loop:
    ldmia       r1!, {r2, r3}
    pld         [r1, #8]
    uadd8       r6, r2, r5
    sel         r6, r4, r5
    uadd8       lr, r3, r5
    sel         lr, r6, r5
    cmp         lr, #0
    bne         .Lstrcpy_align_out
    stmia       r12!, {r2, r3}
    b           .Lstrcpy_align_loop
.Lstrcpy_align_out:
    cmp         r6, #0
    streq       r2, [r12], #4
    movne       r3, r2
    movne       lr, r6
.Lstrcpy_final_loop:
    tst         lr, #0xff
    strb        r3, [r12], #1
    lsr         lr, lr, #8
    lsr         r3, r3, #8
    beq         .Lstrcpy_final_loop
    pop         {r4, r5, r6, pc}

.Lstrcpy_nalign:
    push        {r4, r5, r6, lr}
    mov         r4, #0
    mvn         r5, #0
.Lstrcpy_nalign_loop:
    ldr         r2, [r1], #4
    ldr         r3, [r1], #4
    pld         [r1, #8]
    uadd8       r6, r2, r5
    sel         r6, r4, r5
    uadd8       lr, r3, r5
    sel         lr, r6, r5
    cmp         lr, #0
    bne         .Lstrcpy_nalign_out
    str         r2, [r12], #4
    str         r3, [r12], #4
    b           .Lstrcpy_nalign_loop
.Lstrcpy_nalign_out:
    cmp         r6, #0
    streq       r2, [r12], #4
    movne       r3, r2
    movne       lr, r6
.Lstrcpy_nfinal_loop:
    tst         lr, #0xff
    strb        r3, [r12], #1
    lsr         lr, lr, #8
    lsr         r3, r3, #8
    beq         .Lstrcpy_nfinal_loop
    pop         {r4, r5, r6, pc}

END(strcpy)

#endif
