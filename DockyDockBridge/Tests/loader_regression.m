// Fault-inject setup calls; every Mach operation is mocked, never sent to Dock.
#import <Cocoa/Cocoa.h>
#import <mach/mach.h>
#import <mach/mach_vm.h>
#import <dlfcn.h>
static int stage, failAt, allocations, threadPorts, liveThreads, taskPorts;
static BOOL step(void) { return ++stage == failAt; }
static kern_return_t testTask(mach_port_name_t parent, int pid, mach_port_name_t *task) {
    (void)parent; (void)pid;
    if (step()) return KERN_FAILURE;
    *task = 501; taskPorts++; return KERN_SUCCESS;
}
static kern_return_t testAllocate(vm_map_t task, mach_vm_address_t *address, mach_vm_size_t size, int flags) {
    (void)task; (void)size; (void)flags;
    if (step()) return KERN_FAILURE;
    *address = 0x1000 + allocations++ * 0x1000; return KERN_SUCCESS;
}
static kern_return_t testWrite(vm_map_t task, mach_vm_address_t address, vm_offset_t data, mach_msg_type_number_t size) {
    (void)task; (void)address; (void)data; (void)size;
    return step() ? KERN_FAILURE : KERN_SUCCESS;
}
static kern_return_t testProtect(vm_map_t task, vm_address_t address, vm_size_t size, boolean_t maximum, vm_prot_t protection) {
    (void)task; (void)address; (void)size; (void)maximum; (void)protection;
    return step() ? KERN_FAILURE : KERN_SUCCESS;
}
static kern_return_t testCreate(task_t task, thread_act_t *thread) {
    (void)task;
    if (step()) return KERN_FAILURE;
    *thread = 502; threadPorts++; liveThreads++; return KERN_SUCCESS;
}
static kern_return_t testRunning(task_t task, thread_state_flavor_t flavor, thread_state_t state,
                                mach_msg_type_number_t count, thread_act_t *thread) {
    (void)task; (void)flavor; (void)state; (void)count; (void)thread;
    step(); return KERN_FAILURE;
}
static kern_return_t testConvert(thread_act_t thread, int direction, thread_state_flavor_t flavor,
                                thread_state_t in, mach_msg_type_number_t count, thread_state_t out,
                                mach_msg_type_number_t *outCount) {
    (void)thread; (void)direction; (void)flavor; (void)in; (void)count; (void)out; (void)outCount;
    return step() ? KERN_FAILURE : KERN_SUCCESS;
}
static void *testSymbol(void *handle, const char *name) {
    return !strcmp(name, "thread_convert_thread_state") ? (void *)testConvert : dlsym(handle, name);
}
static kern_return_t testTerminate(thread_act_t thread) { (void)thread; liveThreads--; return KERN_SUCCESS; }
static kern_return_t testFree(vm_map_t task, mach_vm_address_t address, mach_vm_size_t size) {
    (void)task; (void)address; (void)size; allocations--; return KERN_SUCCESS;
}
static kern_return_t testPort(mach_port_t task, mach_port_name_t port) {
    (void)task;
    if (port == 501) taskPorts--; else if (port == 502) threadPorts--;
    return KERN_SUCCESS;
}
#define task_for_pid testTask
#define mach_vm_allocate testAllocate
#define mach_vm_write testWrite
#define vm_protect testProtect
#define thread_create testCreate
#define thread_create_running testRunning
#define thread_terminate testTerminate
#define mach_vm_deallocate testFree
#define mach_port_deallocate testPort
#define dlsym testSymbol
#define main loaderEntry
#include "../loader.m"
#undef main
int main(void) {
    @autoreleasepool {
        const int setupStages = 10;
        for (failAt = 1; failAt <= setupStages; failAt++) {
            stage = allocations = threadPorts = liveThreads = taskPorts = 0;
            char *arguments[] = {"DockyDockLoader", "/tmp/mock-payload.dylib", NULL};
            int result = loaderEntry(2, arguments);
            if (result != 1 || stage != failAt || allocations || threadPorts || liveThreads || taskPorts) {
                fprintf(stderr, "Loader setup failure %d leaked resources (stage=%d, maps=%d, threads=%d, ports=%d/%d)\n",
                        failAt, stage, allocations, liveThreads, threadPorts, taskPorts);
                return 1;
            }
        }
        puts("Dock loader setup-failure cleanup regressions passed");
    }
    return 0;
}
