.text
.p2align 2
_stub:
 pacibsp
 sub sp, sp, #0x30
 stp x29, x30, [sp, #0x20]
 adr x9, dlopen_ptr
 ldr x9, [x9]
 adr x0, path
 mov x1, #1
 blr x9
 adr x9, result_ptr
 ldr x9, [x9]
 str x0, [x9]
 adr x9, dlerror_ptr
 ldr x9, [x9]
 blr x9
 adr x9, result_ptr
 ldr x9, [x9]
 str x0, [x9, #8]
 add x9, x9, #16
 mov x10, #0
 cbz x0, done
copy:
 ldrb w11, [x0, x10]
 strb w11, [x9, x10]
 add x10, x10, #1
 cbz w11, done
 cmp x10, #1023
 b.lo copy
done:
 ldp x29, x30, [sp, #0x20]
 add sp, sp, #0x30
 retab
.p2align 3
dlopen_ptr: .quad 0
dlerror_ptr: .quad 0
result_ptr: .quad 0
path: .space 4096
