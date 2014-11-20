
/* strcmp(char *s1, char *s2) */

    .code   32
    .align 8
    .global strcmp
    .type strcmp, %function
strcmp:

    mov         r12, r0
    pld         [r0]
    pld         [r1]
    b           .Lstrcmp_nalign
    eor         r0,  r12, r1
    tst         r0,  #0x03
    tst         r12, #0x03
    beq         .Lstrcmp_aligned

.Lstrcmp_make_align:
    ldrb        r2, [r12], #1
    ldrb        r3, [r1],  #1
    subs        r0, r2, r3
    bxne        lr
    cmp         r2, #0
    bxeq        lr
    tst         r1, #0x03
    bne         .Lstrcmp_make_align

.Lstrcmp_aligned:
    push        {r4 - r9, lr}
    ldmia       r12!, {r2, r4, r6, r8}
    ldmia       r1!,  {r3, r5, r7, r9}
    ldr         lr, =0x01010101
.Lstrcmp_align_loop:
    pld         [r12, #32]
    pld         [r1,  #32]
    sub         r0, r2, lr
    cmp         r2, r3
    biceq       r0, r0, r2
    tsteq       r0, lr, lsl #7
    bne         .Lstrcmp_align_out1
    sub         r0, r4, lr
    cmp         r4, r5
    biceq       r0, r0, r4
    tsteq       r0, lr, lsl #7
    bne         .Lstrcmp_align_out2
    sub         r0, r6, lr
    cmp         r6, r7
    biceq       r0, r0, r6
    tsteq       r0, lr, lsl #7
    bne         .Lstrcmp_align_out3
    sub         r0, r8, lr
    cmp         r8, r9
    biceq       r0, r0, r8
    tsteq       r0, lr, lsl #7
    bne         .Lstrcmp_align_out4
    ldmia       r12!, {r2, r4, r6, r8}
    ldmia       r1!,  {r3, r5, r7, r9}
    b           .Lstrcmp_align_loop

.Lstrcmp_align_out2:
    mov         r2, r4
    mov         r3, r5
    b           .Lstrcmp_align_out1
.Lstrcmp_align_out3:
    mov         r2, r6
    mov         r3, r7
    b           .Lstrcmp_align_out1
.Lstrcmp_align_out4:
    mov         r2, r8
    mov         r3, r9
.Lstrcmp_align_out1:
    pop         {r4 - r9, lr}

.Lstrcmp_check_result:
    mov         r0, r2, lsl #24
    mov         r2, r2, lsr #8
    cmp         r0, #0x01
    cmpcs       r0, r3, lsl #24
    lsreq       r3, r3, #8
    beq         .Lstrcmp_check_result
    and         r3, r3, #0xff
    rsb         r0, r3, r0, lsr #24
    bx          lr

.Lstrcmp_nalign:
    push        {lr}
    ldr         lr, =0x01010101
    ldr         r2, [r12], #4
    ldr         r3, [r1],  #4
.Lstrcmp_nalign_loop:
    sub         r0, r2, lr
    cmp         r2, r3
    biceq       r0, r0, r2
    tsteq       r0, lr, lsl #7
    bne         .Lstrcmp_nalign_out1
    ldr         r2, [r12], #4
    ldr         r3, [r1],  #4
    b           .Lstrcmp_nalign_loop

.Lstrcmp_nalign_out1:
    pop         {lr}
    b            .Lstrcmp_check_result


