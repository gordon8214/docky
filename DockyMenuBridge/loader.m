// Adapted from asmvik/yabai src/osax/loader.m, MIT license (LICENSE-yabai.txt).
#include <Cocoa/Cocoa.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>

#include <ptrauth.h>
kern_return_t (*_thread_convert_thread_state)(thread_act_t thread, int direction, thread_state_flavor_t flavor, thread_state_t in_state, mach_msg_type_number_t in_stateCnt, thread_state_t out_state, mach_msg_type_number_t *out_stateCnt);

static const char *payload_path;
static pid_t menu_pid;

//
// :Attribution
//
// The arm64e injection path is based on work by Jeremy Legendre (https://github.com/jslegendre)
//

static char shell_code[8192] =
"\xFF\xC3\x00\xD1"                 // sub        sp, sp, #0x30
"\xFD\x7B\x02\xA9"                 // stp        x29, x30, [sp, #0x20]
"\xFD\x83\x00\x91"                 // add        x29, sp, #0x20
"\xA0\xC3\x1F\xB8"                 // stur       w0, [x29, #-0x4]
"\xE1\x0B\x00\xF9"                 // str        x1, [sp, #0x10]
"\xE0\x23\x00\x91"                 // add        x0, sp, #0x8
"\x08\x00\x80\xD2"                 // mov        x8, #0
"\xE8\x07\x00\xF9"                 // str        x8, [sp, #0x8]
"\xE1\x03\x08\xAA"                 // mov        x1, x8
"\xE2\x01\x00\x10"                 // adr        x2, #0x3C
"\xE2\x23\xC1\xDA"                 // paciza     x2
"\xE3\x03\x08\xAA"                 // mov        x3, x8
"\x49\x01\x00\x10"                 // adr        x9, #0x28 ; pthread_create_from_mach_thread
"\x29\x01\x40\xF9"                 // ldr        x9, [x9]
"\x20\x01\x3F\xD6"                 // blr        x9
"\xA0\x4C\x8C\xD2"                 // movz       x0, #0x6265
"\x20\x2C\xAF\xF2"                 // movk       x0, #0x7961, lsl #16
"\x09\x00\x00\x10"                 // adr        x9, #0
"\x20\x01\x1F\xD6"                 // br         x9
"\xFD\x7B\x42\xA9"                 // ldp        x29, x30, [sp, #0x20]
"\xFF\xC3\x00\x91"                 // add        sp, sp, #0x30
"\xC0\x03\x5F\xD6"                 // ret
"\x00\x00\x00\x00\x00\x00\x00\x00" //
;

int main(int argc, char **argv)
{
    if (argc != 4 || strlen(argv[1]) >= 4096 || argv[1][0] != '/') {
        fprintf(stderr, "usage: DockyMenuLoader /absolute/payload.dylib pid bundle-id\n");
        return 64;
    }
    menu_pid = (pid_t)strtol(argv[2], NULL, 10);
    NSRunningApplication *owner = [NSRunningApplication runningApplicationWithProcessIdentifier:menu_pid];
    if (!owner || ![owner.bundleIdentifier isEqualToString:@(argv[3])]) {
        fprintf(stderr, "Menu-extra owner changed before injection\n");
        return 75;
    }
    payload_path = argv[1];
    int result = 1;
    mach_port_t task = 0;
    thread_act_t thread = 0;
    mach_vm_address_t code = 0;
    mach_vm_address_t stack = 0;
    vm_size_t stack_size = 16 * 1024;
    BOOL bootstrapStarted = NO;
    uint64_t stack_contents = 0x00000000CAFEBABE;
    pid_t pid = menu_pid;
    if (pid <= 0) {
        fprintf(stderr, "Invalid menu-extra owner\n");
        return 75;
    }

    if (task_for_pid(mach_task_self(), pid, &task) != KERN_SUCCESS) {
        fprintf(stderr, "could not retrieve task port for pid: %d\n", pid);
        return 1;
    }

    if (mach_vm_allocate(task, &stack, stack_size, VM_FLAGS_ANYWHERE) != KERN_SUCCESS) {
        fprintf(stderr, "could not allocate stack segment\n");
        goto cleanup;
    }

    if (mach_vm_write(task, stack, (vm_address_t) &stack_contents, sizeof(uint64_t)) != KERN_SUCCESS) {
        fprintf(stderr, "could not copy dummy return address into stack segment\n");
        goto cleanup;
    }

    if (vm_protect(task, stack, stack_size, 1, VM_PROT_READ | VM_PROT_WRITE) != KERN_SUCCESS) {
        fprintf(stderr, "could not change protection for stack segment\n");
        goto cleanup;
    }

    if (mach_vm_allocate(task, &code, sizeof(shell_code), VM_FLAGS_ANYWHERE) != KERN_SUCCESS) {
        fprintf(stderr, "could not allocate code segment\n");
        goto cleanup;
    }

    uint64_t pcfmt_address = (uint64_t) ptrauth_strip(dlsym(RTLD_DEFAULT, "pthread_create_from_mach_thread"), ptrauth_key_function_pointer);
    uint64_t dlopen_address = (uint64_t) ptrauth_strip(dlsym(RTLD_DEFAULT, "dlopen"), ptrauth_key_function_pointer);

    uint64_t dlerror_address = (uint64_t)ptrauth_strip(dlsym(RTLD_DEFAULT, "dlerror"), ptrauth_key_function_pointer);
    uint64_t result_address = stack + 0x100;
    // Compiled from dlopen-stub.s. The protocol test checks these bytes and offsets.
    // Copy dlerror before the detached pthread destroys its thread-local storage.
    const unsigned char child[] = {127,35,3,213,255,195,0,209,253,123,2,169,105,3,0,16,41,1,64,249,224,3,0,16,33,0,128,210,32,1,63,214,73,3,0,16,41,1,64,249,32,1,0,249,169,2,0,16,41,1,64,249,32,1,63,214,137,2,0,16,41,1,64,249,32,5,0,249,41,65,0,145,10,0,128,210,224,0,0,180,11,104,106,56,43,105,42,56,74,5,0,145,107,0,0,52,95,253,15,241,99,255,255,84,253,123,66,169,255,195,0,145,255,15,95,214,31,32,3,213};
    memcpy(shell_code + 96, child, sizeof(child));
    memcpy(shell_code + 88, &pcfmt_address, 8);
    memcpy(shell_code + 216, &dlopen_address, 8);
    memcpy(shell_code + 224, &dlerror_address, 8);
    memcpy(shell_code + 232, &result_address, 8);
    memcpy(shell_code + 240, payload_path, strlen(payload_path)+1);

    if (mach_vm_write(task, code, (vm_address_t) shell_code, sizeof(shell_code)) != KERN_SUCCESS) {
        fprintf(stderr, "could not copy shellcode into code segment\n");
        goto cleanup;
    }

    if (vm_protect(task, code, sizeof(shell_code), 0, VM_PROT_EXECUTE | VM_PROT_READ) != KERN_SUCCESS) {
        fprintf(stderr, "could not change protection for code segment\n");
        goto cleanup;
    }

    void *handle = dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_GLOBAL | RTLD_LAZY);
    if (handle) {
        _thread_convert_thread_state = dlsym(handle, "thread_convert_thread_state");
        dlclose(handle);
    }

    if (!_thread_convert_thread_state) {
        fprintf(stderr, "could not load symbol: thread_convert_thread_state\n");
        goto cleanup;
    }

    arm_thread_state64_t thread_state = {}, machine_thread_state = {};
    thread_state_flavor_t thread_flavor = ARM_THREAD_STATE64;
    mach_msg_type_number_t thread_flavor_count = ARM_THREAD_STATE64_COUNT, machine_thread_flavor_count = ARM_THREAD_STATE64_COUNT;

    __darwin_arm_thread_state64_set_pc_fptr(thread_state, ptrauth_sign_unauthenticated((void *) code, ptrauth_key_asia, 0));
    __darwin_arm_thread_state64_set_sp(thread_state, stack + (stack_size / 2));

    kern_return_t error = thread_create(task, &thread);
    if (error != KERN_SUCCESS) {
        fprintf(stderr, "could not create remote thread: %s\n", mach_error_string(error));
        goto cleanup;
    }

    error = _thread_convert_thread_state(thread, 2, thread_flavor, (thread_state_t) &thread_state, thread_flavor_count, (thread_state_t) &machine_thread_state, &machine_thread_flavor_count);
    if (error != KERN_SUCCESS) {
        fprintf(stderr, "could not convert thread state: %s\n", mach_error_string(error));
        goto cleanup;
    }

    NSOperatingSystemVersion os_version = [[NSProcessInfo processInfo] operatingSystemVersion];
    if ((os_version.majorVersion == 14 && os_version.minorVersion >= 4) ||
        (os_version.majorVersion >= 15)) {
        thread_terminate(thread);
        mach_port_deallocate(mach_task_self(), thread);
        thread = MACH_PORT_NULL;
        error = thread_create_running(task, thread_flavor, (thread_state_t)&machine_thread_state, machine_thread_flavor_count, &thread);
        if (error != KERN_SUCCESS) {
            fprintf(stderr, "could not spawn remote thread: %s\n", mach_error_string(error));
            goto cleanup;
        }
    } else {
        error = thread_set_state(thread, thread_flavor, (thread_state_t)&machine_thread_state, machine_thread_flavor_count);
        if (error != KERN_SUCCESS) {
            fprintf(stderr, "could not set thread state: %s\n", mach_error_string(error));
            goto cleanup;
        }

        error = thread_resume(thread);
        if (error != KERN_SUCCESS) {
            fprintf(stderr, "could not resume remote thread: %s\n", mach_error_string(error));
            goto cleanup;
        }
    }

    bootstrapStarted = YES;
    usleep(10000);

    for (int i = 0; i < 10; ++i) {
        kern_return_t error = thread_get_state(thread, thread_flavor, (thread_state_t)&thread_state, &thread_flavor_count);

        if (error != KERN_SUCCESS) {
            result = 1;
            goto cleanup;
        }

        if (thread_state.__x[0] == 0x79616265) {
            for (int attempt = 0; attempt < 100; attempt++) {
                char outcome[1040] = {0};
                mach_vm_size_t copied = 0;
                if (mach_vm_read_overwrite(task, stack + 0x100, sizeof(outcome),
                    (mach_vm_address_t)outcome, &copied) != KERN_SUCCESS) break;
                if (*(uint64_t *)outcome) { result = 0; break; }
                if (outcome[16]) { fprintf(stderr, "Menu bridge load failed: %s\n", outcome + 16); break; }
                usleep(10000);
            }
            goto cleanup;
        }

        usleep(20000);
    }

cleanup:
    if (thread) {
        kern_return_t cleanupError = thread_terminate(thread);
        if (cleanupError != KERN_SUCCESS) {
            fprintf(stderr, "failed to terminate remote thread: %s\n", mach_error_string(cleanupError));
        }
        mach_port_deallocate(mach_task_self(), thread);
    }
    if (stack && !bootstrapStarted) mach_vm_deallocate(task, stack, stack_size);
    // Once the bootstrap has run, a detached pthread may still execute this
    // page and result storage. Keep both until the owner exits; setup failures can release them.
    if (code && !bootstrapStarted) mach_vm_deallocate(task, code, sizeof(shell_code));
    if (task) mach_port_deallocate(mach_task_self(), task);
    return result;
}
