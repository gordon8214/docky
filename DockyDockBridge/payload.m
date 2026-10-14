// Dock-side reservation publisher. No application windows are moved or resized.
#import <AppKit/AppKit.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach/mach_vm.h>
#import <pthread.h>
#import <dlfcn.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/stat.h>
#import <sys/proc_info.h>
#import <libproc.h>
#import <fcntl.h>
#import <unistd.h>
#import <math.h>
#import <arpa/inet.h>

struct DockGeometry { float x, y, width, height; int32_t reason, orientation; };
typedef int (*SetRect)(int, CGRect, int, int);
typedef int (*Broadcast)(uint32_t, void *, uint32_t);
typedef void (*DockInfo)(id, SEL, uint32_t, double, double, uint32_t);
static SetRect originalSet;
static Broadcast originalBroadcast;
static DockInfo originalInfo;
static int (*mainConnection)(void);
static int (*getRect)(int,CGRect*,int*,int*);
static CGRect desiredRect, appleRect;
static int desiredReason, desiredOrientation, appleReason, appleOrientation;
static uint32_t desiredDisplay;
static uint64_t revision;
static pid_t ownerPID;
static NSString *session;
static BOOL active;
static id coordinator;
static uint32_t appleDisplay, appleInfoOrientation;
static double appleInset, appleMaximum;
static struct proc_bsdinfo ownerIdentity;
static NSString *statePath;
static NSString *bridgeError;
static NSString *hookClassName;
static Class hookClass;
static NSUInteger hookCalls;
static NSMutableDictionary<NSNumber *, NSArray<NSNumber *> *> *appleDisplayInfo;
static NSString * const missingCoordinator = @"Apple Dock's existing WindowManager coordinator was not found";

static id instanceInRange(Class target, uintptr_t begin, uintptr_t end, double deadline) {
    uintptr_t *maskSymbol = dlsym(RTLD_DEFAULT, "objc_debug_isa_class_mask");
    uintptr_t mask = maskSymbol ? *maskSymbol : UINTPTR_MAX;
    uintptr_t targetISA = (uintptr_t)(__bridge void *)target & mask;
    for (uintptr_t address = begin; address + sizeof(uintptr_t) <= end; address += sizeof(uintptr_t)) {
        if ((address & 4095) == 0 && NSProcessInfo.processInfo.systemUptime > deadline) return nil;
        uintptr_t candidate = 0, isa = 0;
        memcpy(&candidate, (void *)address, sizeof(candidate));
        if (candidate < 4096 || (candidate & 7)) continue;
        mach_vm_size_t copied = 0;
        if (mach_vm_read_overwrite(mach_task_self(), candidate, sizeof(isa), (mach_vm_address_t)&isa, &copied)
            != KERN_SUCCESS || copied != sizeof(isa) || (isa & mask) != targetISA) continue;
        // A readable pointer with this registered ISA is an existing instance;
        // verify it with the runtime before retaining or reading named ivars.
        id object = (__bridge id)(void *)candidate;
        if (object_getClass(object) == target) return object;
    }
    return nil;
}
static id existingDockAgent(void) {
    Class target = NSClassFromString(@"DockCore.DockAgent");
    if (!target) return nil;
    if ([NSApp.delegate isKindOfClass:target]) return NSApp.delegate;
    // Dock 27 runs a Carbon loop, so NSApp.delegate is nil. Its Swift agent
    // remains rooted in executable globals or the main-loop stack. Read only
    // those ranges, using checked Mach reads for candidate object pointers.
    // No heap enumeration, arbitrary selector calls, or code patching is used.
    double deadline = NSProcessInfo.processInfo.systemUptime + 0.5;
    const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(0);
    if (header && header->magic == MH_MAGIC_64) {
        const struct load_command *command = (const void *)(header + 1);
        intptr_t slide = _dyld_get_image_vmaddr_slide(0);
        for (uint32_t index = 0; index < header->ncmds; index++) {
            if (command->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *segment = (const void *)command;
                if ((segment->initprot & (VM_PROT_READ | VM_PROT_WRITE)) == (VM_PROT_READ | VM_PROT_WRITE)) {
                    uintptr_t begin = (uintptr_t)(segment->vmaddr + slide);
                    id object = instanceInRange(target, begin, begin + segment->vmsize, deadline);
                    if (object) return object;
                }
            }
            command = (const void *)((const char *)command + command->cmdsize);
        }
    }
    uintptr_t stackTop = (uintptr_t)pthread_get_stackaddr_np(pthread_self());
    uintptr_t stackCurrent = (uintptr_t)&stackTop;
    return stackCurrent < stackTop ? instanceInRange(target, stackCurrent & ~7UL, stackTop, deadline) : nil;
}

static NSDictionary *visibilityState(void) {
    int descriptor = open(statePath.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
    if (descriptor < 0) return nil;
    struct stat info;
    if (fstat(descriptor, &info) || !S_ISREG(info.st_mode) || info.st_uid != getuid()
        || (info.st_mode & 077) || info.st_size > 65536) { close(descriptor); return nil; }
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)info.st_size];
    ssize_t count = read(descriptor, data.mutableBytes, data.length); close(descriptor);
    if (count != (ssize_t)data.length) return nil;
    id value = [NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:nil];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}
static BOOL ownerLives(void) {
    struct proc_bsdinfo current = {};
    return ownerPID > 0 && proc_pidinfo(ownerPID, PROC_PIDTBSDINFO, 0, &current, sizeof(current)) == sizeof(current)
        && current.pbi_uid == getuid() && current.pbi_start_tvsec == ownerIdentity.pbi_start_tvsec
        && current.pbi_start_tvusec == ownerIdentity.pbi_start_tvusec;
}
static void notifyGeometry(CGRect rect, int reason, int orientation) {
    struct DockGeometry notification = {rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, reason, orientation};
    originalBroadcast(1201, &notification, sizeof(notification));
}
static double desiredInset(void) {
    if (desiredReason != 0) return 0;
    return desiredOrientation <= 2 ? desiredRect.size.height : desiredRect.size.width;
}
static void releasePreviousDisplay(void) {
    if (!active || !coordinator || !originalInfo) return;
    // WindowServer's rectangle is global, but WindowManager caches an inset
    // per display. Moving the replacement must clear the old display too.
    NSArray<NSNumber *> *saved = appleDisplayInfo[@(desiredDisplay)];
    originalInfo(coordinator, NSSelectorFromString(@"setDockInfoWithDisplayID:currentInset:maximumInset:orientation:"),
                 desiredDisplay, saved ? saved[0].doubleValue : 0, saved ? saved[1].doubleValue : 0,
                 saved ? saved[2].unsignedIntValue : desiredOrientation);
}
static void publish(void) {
    if (!originalSet || !originalBroadcast || !mainConnection) return;
    CGRect rect = active ? desiredRect : appleRect;
    int reason = active ? desiredReason : appleReason;
    int orientation = active ? desiredOrientation : appleOrientation;
    originalSet(mainConnection(), rect, reason, orientation);
    notifyGeometry(rect, reason, orientation);
    if (coordinator && originalInfo) {
        originalInfo(coordinator, NSSelectorFromString(@"setDockInfoWithDisplayID:currentInset:maximumInset:orientation:"),
                     active ? desiredDisplay : appleDisplay, active ? desiredInset() : appleInset,
                     active ? desiredInset() : appleMaximum, active ? desiredOrientation : appleInfoOrientation);
    }
}
static void interceptedInfo(id object, SEL selector, uint32_t display, double inset, double maximum, uint32_t orientation) {
    hookCalls++;
    coordinator = object;
    if ([bridgeError isEqualToString:missingCoordinator]) bridgeError = nil;
    appleDisplay = display; appleInset = inset; appleMaximum = maximum; appleInfoOrientation = orientation;
    appleDisplayInfo[@(display)] = @[@(inset), @(maximum), @(orientation)];
    if (active) {
        if (display != desiredDisplay) originalInfo(object, selector, display, inset, maximum, orientation);
        // Dock calls this adapter immediately after publishing its rectangle.
        // Republish within the same main-thread operation, then update the
        // tiling cache with the identical inset. Dock-origin notifications
        // refresh existing AppKit clients. No executable/GOT pages are edited.
        CGRect rect; int reason=0, edge=0;
        if (getRect(mainConnection(),&rect,&reason,&edge)==0
            && (!CGRectEqualToRect(rect,desiredRect) || reason!=desiredReason || edge!=desiredOrientation)) {
            appleRect=rect; appleReason=reason; appleOrientation=edge;
        }
        publish();
    } else {
        originalInfo(object,selector,display,inset,maximum,orientation);
    }
}
static BOOL installHooks(void) {
    void *sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    originalSet = dlsym(sky, "SLSSetDockRectWithOrientation");
    originalBroadcast = dlsym(RTLD_DEFAULT, "CGSPostBroadcastNotification");
    mainConnection = dlsym(sky, "SLSMainConnectionID");
    getRect = dlsym(sky, "SLSGetDockRectWithOrientation");
    if (!originalSet || !originalBroadcast || !mainConnection || !getRect) return NO;
    if (getRect(mainConnection(), &appleRect, &appleReason, &appleOrientation) != 0) return NO;
    appleDisplayInfo = [NSMutableDictionary dictionary];
    // Apple's modern tiling engine has a separate inset cache. Intercept its
    // Objective-C bridge as well as WindowServer's Dock rectangle publisher.
    SEL selector = NSSelectorFromString(@"setDockInfoWithDisplayID:currentInset:maximumInset:orientation:");
    // Swift metadata may be registered lazily; force the public coordinator
    // metadata before enumerating its Objective-C adapters.
    (void)NSClassFromString(@"WindowManager.ExposeCoordinator");
    unsigned int count = 0;
    Class __unsafe_unretained *classes = objc_copyClassList(&count);
    if (!classes) return NO;
    for (unsigned int index = 0; index < count; ++index) {
        Method method = class_getInstanceMethod(classes[index], selector);
        if (!method || method_getNumberOfArguments(method) != 6) continue;
        // Restrict the hook to the Apple WindowManager coordinator, not a
        // coincidentally named method on another class or inherited wrapper.
        const char *image = class_getImageName(classes[index]);
        if (!image || (!strstr(image,"/Dock.app/") && !strstr(image,"/WindowManager.framework/"))) continue;
        Class parent = class_getSuperclass(classes[index]);
        if (parent && class_getInstanceMethod(parent,selector) == method) continue;
        originalInfo = (DockInfo)method_setImplementation(method, (IMP)interceptedInfo);
        hookClassName = NSStringFromClass(classes[index]);
        hookClass = classes[index];
        break;
    }
    free(classes);
    // Injection occurs after Dock's first layout. Bootstrap its already-live
    // adapter from DockAgent, rather than waiting for a future publication.
    // These named, runtime-described object ivars were verified in Dock 27.
    id agent = existingDockAgent();
    Ivar expose = agent ? class_getInstanceVariable(object_getClass(agent), "expose") : NULL;
    if (expose && ivar_getOffset(expose) + sizeof(id) <= class_getInstanceSize(object_getClass(agent))) {
        id existing = object_getIvar(agent, expose);
        if ([existing isKindOfClass:hookClass]) coordinator = existing;
    }
    appleDisplay = CGMainDisplayID();
    appleInfoOrientation = (uint32_t)appleOrientation;
    appleInset = appleReason == 0 ? (appleOrientation <= 2 ? appleRect.size.height : appleRect.size.width) : 0;
    appleMaximum = appleOrientation <= 2 ? appleRect.size.height : appleRect.size.width;
    appleDisplayInfo[@(appleDisplay)] = @[@(appleInset), @(appleMaximum), @(appleInfoOrientation)];
    if (!originalInfo) bridgeError = @"WindowManager coordinator bridge is unavailable";
    else if (!coordinator) bridgeError = missingCoordinator;
    return originalInfo != NULL;
}
static BOOL isDocky(pid_t pid) {
    SecCodeRef code = NULL;
    NSDictionary *attributes = @{(__bridge NSString *)kSecGuestAttributePid: @(pid)};
    if (SecCodeCopyGuestWithAttributes(NULL, (__bridge CFDictionaryRef)attributes, 0, &code) != errSecSuccess) return NO;
    SecRequirementRef requirement = NULL;
    SecRequirementCreateWithString(CFSTR("identifier \"gt.quintero.Docky\""), 0, &requirement);
    BOOL valid = requirement && SecCodeCheckValidity(code, 0, requirement) == errSecSuccess;
    if (requirement) CFRelease(requirement);
    CFRelease(code);
    return valid;
}
static NSDictionary *acceptRequest(NSDictionary *request, pid_t peerPID) {
    NSDictionary *state = visibilityState();
    NSString *newSession = request[@"session"];
    if (![newSession isKindOfClass:NSString.class] || ![request[@"revision"] isKindOfClass:NSNumber.class]
        || ![request[@"display"] isKindOfClass:NSNumber.class] || ![request[@"reason"] isKindOfClass:NSNumber.class]
        || ![request[@"orientation"] isKindOfClass:NSNumber.class]) return @{@"error": @"Invalid request types"};
    if (![state[@"active"] boolValue] || ![state[@"reservationOwnerActive"] boolValue]
        || [state[@"ownerPID"] intValue] != peerPID
        || ![state[@"sessionID"] isEqual:newSession] || !isDocky(peerPID)) return @{@"error": @"Invalid owner/session"};
    if (bridgeError) return @{@"error": bridgeError};
    uint64_t nextRevision = [request[@"revision"] unsignedLongLongValue];
    if ([session isEqual:newSession] && nextRevision <= revision) return @{@"error": @"Stale revision"};
    NSArray *numbers = request[@"rect"];
    if (![numbers isKindOfClass:NSArray.class] || numbers.count != 4) return @{@"error": @"Invalid rectangle"};
    double values[4];
    for (int index = 0; index < 4; ++index) {
        if (![numbers[index] isKindOfClass:NSNumber.class]) return @{@"error": @"Invalid coordinate"};
        values[index] = [numbers[index] doubleValue];
        if (!isfinite(values[index])) return @{@"error": @"Invalid coordinate"};
    }
    int orientation = [request[@"orientation"] intValue], reason = [request[@"reason"] intValue];
    uint32_t display = [request[@"display"] unsignedIntValue];
    CGRect rect = CGRectMake(values[0], values[1], values[2], values[3]);
    CGRect bounds = CGDisplayBounds(display);
    if (orientation < 1 || orientation > 4 || (reason != 0 && reason != 2) || CGRectIsEmpty(bounds)
        || (reason == 0 && (CGRectIsEmpty(rect) || !CGRectContainsRect(CGRectInset(bounds,-1,-1),rect))))
        return @{@"error": @"Reservation is outside its display"};
    struct proc_bsdinfo identity = {};
    if (proc_pidinfo(peerPID, PROC_PIDTBSDINFO, 0, &identity, sizeof(identity)) != sizeof(identity))
        return @{@"error": @"Owner has exited"};
    if (active && desiredDisplay != display) releasePreviousDisplay();
    session = newSession; revision = nextRevision; ownerPID = peerPID; ownerIdentity = identity;
    desiredRect = rect; desiredReason = reason; desiredOrientation = orientation; desiredDisplay = display;
    active = YES;
    publish();
    NSString *details = [NSString stringWithFormat:@"adapter=%@ calls=%lu coordinator=%@ agent=%@ Apple(display=%u inset=%g maximum=%g orientation=%u)",
                         hookClassName, (unsigned long)hookCalls, coordinator ? NSStringFromClass([coordinator class]) : @"unavailable",
                         NSStringFromClass([NSApp.delegate class]),
                         appleDisplay, appleInset, appleMaximum, appleInfoOrientation];
    return bridgeError ? @{@"error": bridgeError}
        : @{@"revision": @(revision), @"dockPID": @(getpid()), @"backendDetails": details};
}
static void serveClient(int client) {
    uid_t uid = 0; gid_t gid = 0; pid_t pid = 0; socklen_t length = sizeof(pid);
    struct timeval budget = {1,0};
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &budget, sizeof(budget));
    setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &budget, sizeof(budget));
    int noSignal = 1; setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
    if (getpeereid(client,&uid,&gid) || uid != getuid() || getsockopt(client,SOL_LOCAL,LOCAL_PEERPID,&pid,&length)) return;
    uint32_t header = 0;
    if (recv(client,&header,sizeof(header),MSG_WAITALL) != sizeof(header)) return;
    uint32_t count = ntohl(header);
    if (!count || count >= 4096) return;
    char bytes[4096];
    if (recv(client,bytes,count,MSG_WAITALL) != count) return;
    NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)count];
    id request = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![request isKindOfClass:NSDictionary.class]) return;
    __block NSDictionary *response;
    dispatch_sync(dispatch_get_main_queue(), ^{ response = acceptRequest(request,pid); });
    NSData *reply = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
    if (reply) {
        uint32_t size = htonl((uint32_t)reply.length);
        NSMutableData *packet = [NSMutableData dataWithBytes:&size length:sizeof(size)];
        [packet appendData:reply];
        size_t offset = 0;
        while (offset < packet.length) {
            ssize_t written = write(client,(const char *)packet.bytes+offset,packet.length-offset);
            if (written < 0 && errno == EINTR) continue;
            if (written <= 0) break;
            offset += (size_t)written;
        }
    }
}
__attribute__((constructor)) static void initializeDockBridge(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.dock"]) return;
        statePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Docky/SystemDockVisibilityState.plist"];
        dispatch_async(dispatch_get_main_queue(), ^{
            int server = socket(AF_UNIX,SOCK_STREAM,0);
            if (server < 0) return;
            struct sockaddr_un address = {}; address.sun_family = AF_UNIX;
            snprintf(address.sun_path,sizeof(address.sun_path),"/tmp/DockyDockBridge-%u.sock",getuid());
            // A live bridge is already installed: never unlink its endpoint.
            int check = socket(AF_UNIX,SOCK_STREAM,0);
            if (check < 0) { close(server); return; }
            if (fcntl(check,F_SETFL,O_NONBLOCK) < 0) { close(check); close(server); return; }
            int connected = connect(check,(struct sockaddr*)&address,sizeof(address));
            int connectError = errno;
            close(check);
            // A connecting or backlogged endpoint belongs to a live server;
            // never block Apple's main thread or replace that socket.
            if (connected == 0 || connectError == EINPROGRESS || connectError == EAGAIN) { close(server);return; }
            struct stat existing;
            if (!lstat(address.sun_path,&existing) && (!S_ISSOCK(existing.st_mode) || existing.st_uid != getuid())) {
                close(server);return;
            }
            unlink(address.sun_path);
            mode_t oldMask = umask(077);
            int result = bind(server,(struct sockaddr*)&address,sizeof(address)); umask(oldMask);
            if (result || listen(server,4)) {close(server);return;}
            if (!installHooks() && !bridgeError) bridgeError = @"Dock publishing hooks are unavailable";
            CFNotificationCenterPostNotification(CFNotificationCenterGetDistributedCenter(),
                CFSTR("com.apple.dock.prefchanged"), NULL, NULL, true);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
                while (YES) {
                    int client = accept(server,NULL,NULL);
                    if (client < 0) continue;
                    @autoreleasepool { serveClient(client); }
                    close(client);
                }
            });
            NSTimer *leaseTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
                (void)timer;
                if (!active) return;
                NSDictionary *state = visibilityState();
                if (!ownerLives() || ![state[@"active"] boolValue] || ![state[@"reservationOwnerActive"] boolValue]
                    || ![state[@"sessionID"] isEqual:session]) {
                    releasePreviousDisplay();
                    active = NO; ownerPID = 0; publish();
                }
            }];
            [NSRunLoop.mainRunLoop addTimer:leaseTimer forMode:NSRunLoopCommonModes];
        });
    }
}
