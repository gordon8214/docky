// Read-only investigation of native menu-extra hosts. No remote writes or hooks.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <dlfcn.h>

static void inspectTaskAccess(void) {
    for (NSString *identifier in @[@"com.apple.dock", @"com.apple.MenuBarAgent",
                                   @"com.apple.controlcenter", @"com.github.xor-gate.syncthing-macosx"]) {
        NSArray<NSRunningApplication *> *apps =
            [NSRunningApplication runningApplicationsWithBundleIdentifier:identifier];
        for (NSRunningApplication *app in apps) {
            mach_port_t task = MACH_PORT_NULL;
            kern_return_t result = task_for_pid(mach_task_self(), app.processIdentifier, &task);
            printf("%s pid=%d task_for_pid=%d (%s)\n", identifier.UTF8String,
                   app.processIdentifier, result, mach_error_string(result));
            if (task != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), task);
        }
    }
}

static BOOL relevantMethod(NSString *name) {
    for (NSString *fragment in @[@"frame", @"rect", @"anchor", @"position", @"menu", @"tracking",
                                 @"trigger", @"popover", @"delegate", @"itemid", @"context"]) {
        if ([name.lowercaseString containsString:fragment]) return YES;
    }
    return NO;
}

static void inspectClass(Class cls) {
    printf("CLASS %s\n", class_getName(cls));
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int index = 0; index < count; index++) {
        NSString *name = NSStringFromSelector(method_getName(methods[index]));
        if (relevantMethod(name)) printf("  %s :: %s\n", name.UTF8String, method_getTypeEncoding(methods[index]));
    }
    free(methods);
    Ivar *ivars = class_copyIvarList(cls, &count);
    for (unsigned int index = 0; index < count; index++) {
        printf("  IVAR %s :: %s offset=%td\n", ivar_getName(ivars[index]),
               ivar_getTypeEncoding(ivars[index]), ivar_getOffset(ivars[index]));
    }
    free(ivars);
}

static void inspectRuntime(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore",
                          RTLD_LAZY | RTLD_LOCAL);
    if (!handle) { fprintf(stderr, "%s\n", dlerror()); return; }
    unsigned int count = 0;
    Class __unsafe_unretained *classes = objc_copyClassList(&count);
    for (unsigned int index = 0; index < count; index++) {
        NSString *name = NSStringFromClass(classes[index]);
        if ([name hasPrefix:@"MBMenu"] || [name hasPrefix:@"MBTrigger"]
            || [name hasPrefix:@"NSStatus"] || [name isEqualToString:@"NSPopover"]
            || [name isEqualToString:@"NSMenu"]) inspectClass(classes[index]);
    }
    free(classes);
    Protocol *__unsafe_unretained *protocols = objc_copyProtocolList(&count);
    for (unsigned int index = 0; index < count; index++) {
        if (![@(protocol_getName(protocols[index])) hasPrefix:@"MBMenuBarItem"]) continue;
        printf("PROTOCOL %s\n", protocol_getName(protocols[index]));
        for (int required = 0; required < 2; required++) {
            unsigned int methodCount = 0;
            struct objc_method_description *methods =
                protocol_copyMethodDescriptionList(protocols[index], required, YES, &methodCount);
            for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
                printf("  %s :: %s\n", sel_getName(methods[methodIndex].name), methods[methodIndex].types);
            }
            free(methods);
        }
    }
    free(protocols);
    dlclose(handle);
}

static AXUIElementRef findTrayButton(AXUIElementRef element, NSString *label,
                                    unsigned int depth, unsigned int *remaining) {
    if (depth > 18 || *remaining == 0) return NULL;
    (*remaining)--;
    CFTypeRef description = NULL;
    AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute, &description);
    BOOL matches = description && [(__bridge id)description isEqual:label];
    if (description) CFRelease(description);
    if (matches) return (AXUIElementRef)CFRetain(element);
    CFTypeRef children = NULL;
    if (AXUIElementCopyAttributeValue(element, kAXChildrenAttribute, &children) != kAXErrorSuccess
        || !children) return NULL;
    AXUIElementRef found = NULL;
    if (CFGetTypeID(children) == CFArrayGetTypeID()) {
        for (id child in (__bridge NSArray *)children) {
            if (CFGetTypeID((__bridge CFTypeRef)child) != AXUIElementGetTypeID()) continue;
            found = findTrayButton((__bridge AXUIElementRef)child, label, depth + 1, remaining);
            if (found) break;
        }
    }
    CFRelease(children);
    return found;
}

static BOOL accessibilityFrame(AXUIElementRef element, NSRect *rect) {
    CFTypeRef position = NULL, size = NULL;
    AXUIElementCopyAttributeValue(element, kAXPositionAttribute, &position);
    AXUIElementCopyAttributeValue(element, kAXSizeAttribute, &size);
    CGPoint point = CGPointZero;
    CGSize dimensions = CGSizeZero;
    BOOL valid = position && size && CFGetTypeID(position) == AXValueGetTypeID()
        && CFGetTypeID(size) == AXValueGetTypeID()
        && AXValueGetValue(position, kAXValueCGPointType, &point)
        && AXValueGetValue(size, kAXValueCGSizeType, &dimensions);
    if (position) CFRelease(position);
    if (size) CFRelease(size);
    if (valid) *rect = NSMakeRect(point.x, point.y, dimensions.width, dimensions.height);
    return valid;
}

static void contentBounds(AXUIElementRef element, NSRect container, unsigned int depth,
                           unsigned int *remaining, NSRect *bounds) {
    if (depth > 5 || *remaining == 0) return;
    (*remaining)--;
    CFTypeRef role = NULL, children = NULL;
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute, &role);
    NSRect rect;
    if (role && ![(__bridge id)role isEqual:(__bridge id)kAXGroupRole]
        && ![(__bridge id)role isEqual:(__bridge id)kAXWindowRole]
        && accessibilityFrame(element, &rect) && NSContainsRect(container, rect) && !NSIsEmptyRect(rect))
        *bounds = NSIsEmptyRect(*bounds) ? rect : NSUnionRect(*bounds, rect);
    if (role) CFRelease(role);
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute, &children);
    if (children && CFGetTypeID(children) == CFArrayGetTypeID())
        for (id child in (__bridge NSArray *)children)
            contentBounds((__bridge AXUIElementRef)child, container, depth + 1, remaining, bounds);
    if (children) CFRelease(children);
}

static void addPopupGeometry(NSMutableDictionary *request, pid_t ownerPID, NSRect anchor, CGFloat reference) {
    AXUIElementRef app = AXUIElementCreateApplication(ownerPID);
    AXUIElementSetMessagingTimeout(app, 0.1);
    CFTypeRef windows = NULL;
    AXUIElementCopyAttributeValue(app, kAXWindowsAttribute, &windows);
    NSArray *physical = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, 0));
    if (windows && CFGetTypeID(windows) == CFArrayGetTypeID()) {
        for (id value in (__bridge NSArray *)windows) {
            AXUIElementRef window = (__bridge AXUIElementRef)value;
            NSRect container;
            if (!accessibilityFrame(window, &container) || container.size.width < 100
                || container.size.height < 100) continue;
            NSNumber *identifier = nil;
            for (NSDictionary *candidate in physical) {
                CGRect frame;
                id bounds = candidate[(__bridge id)kCGWindowBounds];
                if ([candidate[(__bridge id)kCGWindowOwnerPID] intValue] != ownerPID
                    || ![bounds isKindOfClass:NSDictionary.class]
                    || !CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)bounds, &frame)) continue;
                if (NSEqualRects(frame, container)) identifier = candidate[(__bridge id)kCGWindowNumber];
            }
            if (!identifier) continue;
            unsigned int remaining = 160;
            NSRect content = NSZeroRect;
            contentBounds(window, container, 0, &remaining, &content);
            if (NSIsEmptyRect(content)) continue;
            content = NSIntersectionRect(NSInsetRect(content, -12, -12), container);
            NSScreen *screen = NSScreen.screens.firstObject;
            NSRect visible = screen.visibleFrame;
            if (content.size.width > visible.size.width || content.size.height > visible.size.height) continue;
            CGFloat x = MAX(NSMinX(visible), MIN(NSMidX(anchor) - content.size.width / 2,
                                                NSMaxX(visible) - content.size.width));
            CGFloat top = MAX(reference - NSMaxY(visible),
                MIN(reference - NSMaxY(anchor) - content.size.height - 8,
                    reference - NSMinY(visible) - content.size.height));
            NSRect destination = container;
            destination.origin.x = x - content.origin.x + container.origin.x;
            destination.origin.y = reference - (top - content.origin.y + container.origin.y) - container.size.height;
            request[@"window"] = identifier;
            request[@"destination"] = @[@(destination.origin.x), @(destination.origin.y),
                                        @(destination.size.width), @(destination.size.height)];
            printf("Popup id=%u content=%s destination=%s\n", identifier.unsignedIntValue,
                   NSStringFromRect(content).UTF8String, NSStringFromRect(destination).UTF8String);
            break;
        }
    }
    if (windows) CFRelease(windows);
    CFRelease(app);
}

static int writeAnchorRequest(NSString *requestPath, NSString *reportPath, NSString *bundle, NSString *label) {
    if (!requestPath.isAbsolutePath || !reportPath.isAbsolutePath) return 64;
    if (![@[@"com.github.xor-gate.syncthing-macosx", @"com.apple.controlcenter"] containsObject:bundle]) return 64;
    NSRunningApplication *docky =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:@"gt.quintero.Docky"].firstObject;
    NSRunningApplication *owner = [NSRunningApplication runningApplicationsWithBundleIdentifier:bundle].firstObject;
    if (!docky || !owner || !AXIsProcessTrusted()) return 1;
    AXUIElementRef app = AXUIElementCreateApplication(docky.processIdentifier);
    AXUIElementSetMessagingTimeout(app, 0.1);
    unsigned int remaining = 1000;
    AXUIElementRef button = findTrayButton(app, label, 0, &remaining);
    CFRelease(app);
    if (!button) return 1;
    CFTypeRef position = NULL, size = NULL;
    AXUIElementCopyAttributeValue(button, kAXPositionAttribute, &position);
    AXUIElementCopyAttributeValue(button, kAXSizeAttribute, &size);
    CFRelease(button);
    CGPoint point = CGPointZero;
    CGSize dimensions = CGSizeZero;
    BOOL valid = position && size && CFGetTypeID(position) == AXValueGetTypeID()
        && CFGetTypeID(size) == AXValueGetTypeID()
        && AXValueGetValue(position, kAXValueCGPointType, &point)
        && AXValueGetValue(size, kAXValueCGSizeType, &dimensions);
    if (position) CFRelease(position);
    if (size) CFRelease(size);
    if (!valid) return 1;
    CGFloat reference = NSScreen.screens.firstObject.frame.origin.y + NSScreen.screens.firstObject.frame.size.height;
    NSMutableDictionary *request = [@{@"bundle": owner.bundleIdentifier, @"pid": @(owner.processIdentifier),
        @"expires": @([NSDate.date timeIntervalSince1970] + 60), @"report": reportPath,
        @"anchor": @[@(point.x), @(reference - point.y - dimensions.height),
                     @(dimensions.width), @(dimensions.height)]} mutableCopy];
    if ([bundle isEqualToString:@"com.apple.controlcenter"]) {
        addPopupGeometry(request, owner.processIdentifier,
            NSMakeRect(point.x, reference - point.y - dimensions.height, dimensions.width, dimensions.height), reference);
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:request options:NSJSONWritingPrettyPrinted error:nil];
    NSDictionary *attributes = @{NSFilePosixPermissions: @0600};
    if (![NSFileManager.defaultManager createFileAtPath:reportPath contents:NSData.data attributes:attributes]
        || ![NSFileManager.defaultManager createFileAtPath:requestPath contents:data attributes:attributes]) return 1;
    printf("Prepared %s owner anchor at %.0f,%.0f %.0fx%.0f (AX coordinates)\n",
           label.UTF8String, point.x, point.y, dimensions.width, dimensions.height);
    return 0;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--task-access") == 0) inspectTaskAccess();
        else if (argc == 2 && strcmp(argv[1], "--runtime") == 0) inspectRuntime();
        else if (argc == 4 && strcmp(argv[1], "--anchor-request") == 0)
            return writeAnchorRequest(@(argv[2]), @(argv[3]), @"com.github.xor-gate.syncthing-macosx", @"Syncthing");
        else if (argc == 6 && strcmp(argv[1], "--anchor-request") == 0)
            return writeAnchorRequest(@(argv[2]), @(argv[3]), @(argv[4]), @(argv[5]));
        else {
            fprintf(stderr, "usage: menu_host_probe --task-access | --runtime | "
                "--anchor-request request.json report.log [bundle label]\n");
            return 64;
        }
    }
    return 0;
}
