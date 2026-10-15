// Owner-side Control Center diagnostics and a bounded frame-placement experiment.
// The original frame is restored after one second; no persistent hook is installed.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sys/stat.h>
#import <unistd.h>

#ifndef DOCKY_ANCHOR_REQUEST
#error Define the absolute path to the one-shot request at build time.
#endif

__attribute__((constructor)) static void inspectMenuOwnerWindows(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        struct stat metadata;
        if (lstat(DOCKY_ANCHOR_REQUEST, &metadata) != 0 || !S_ISREG(metadata.st_mode)
            || metadata.st_uid != getuid() || (metadata.st_mode & 0777) != 0600) return;
        NSData *data = [NSData dataWithContentsOfFile:@DOCKY_ANCHOR_REQUEST];
        NSDictionary *request = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![request isKindOfClass:NSDictionary.class]
            || ![request[@"bundle"] isEqualToString:NSBundle.mainBundle.bundleIdentifier]
            || [request[@"pid"] intValue] != getpid()) return;
        NSTimeInterval remaining = [request[@"expires"] doubleValue] - NSDate.date.timeIntervalSince1970;
        if (remaining <= 0 || remaining > 60 || ![request[@"report"] isKindOfClass:NSString.class]) return;
        NSMutableString *report = NSMutableString.string;
        for (NSWindow *window in NSApp.windows) {
            if (!window.isVisible) continue;
            [report appendFormat:@"WINDOW id=%ld class=%@ frame=%@ view=%@ controller=%@\n",
                window.windowNumber, NSStringFromClass(window.class), NSStringFromRect(window.frame),
                NSStringFromClass(window.contentView.class), NSStringFromClass(window.contentViewController.class)];
            SEL selector = NSSelectorFromString(@"_cgsPositionManagedByExternalAgent");
            Method method = class_getInstanceMethod(window.class, selector);
            if (method && strcmp(method_getTypeEncoding(method), "B16@0:8") == 0) {
                BOOL managed = ((BOOL (*)(id, SEL))objc_msgSend)(window, selector);
                [report appendFormat:@"  externalPosition=%d\n", managed];
            }
        }
        unsigned int count = 0;
        Class __unsafe_unretained *classes = objc_copyClassList(&count);
        for (unsigned int index = 0; index < count; index++) {
            NSString *name = NSStringFromClass(classes[index]);
            if (![name containsString:@"ControlCenterApp"]
                || !([name containsString:@"MenuAnchor"] || [name containsString:@"PositionCoordinator"])) continue;
            [report appendFormat:@"CLASS %@\n", name];
            unsigned int ivarCount = 0;
            Ivar *ivars = class_copyIvarList(classes[index], &ivarCount);
            for (unsigned int field = 0; field < ivarCount; field++) {
                [report appendFormat:@"  %s :: %s offset=%td\n", ivar_getName(ivars[field]),
                    ivar_getTypeEncoding(ivars[field]), ivar_getOffset(ivars[field])];
            }
            free(ivars);
        }
        free(classes);
        [report writeToFile:request[@"report"] atomically:NO encoding:NSUTF8StringEncoding error:nil];
        NSArray *destination = request[@"destination"];
        if (![destination isKindOfClass:NSArray.class] || destination.count != 4) return;
        for (id value in destination)
            if (![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue])) return;
        for (NSWindow *window in NSApp.windows) {
            if (window.windowNumber != [request[@"window"] integerValue]
                || ![NSStringFromClass(window.class) isEqualToString:@"ControlCenterApp.ModuleWindow"]) continue;
            NSRect original = window.frame;
            NSRect target = NSMakeRect([destination[0] doubleValue], [destination[1] doubleValue],
                                      [destination[2] doubleValue], [destination[3] doubleValue]);
            if (!NSEqualSizes(original.size, target.size)) return;
            [window setFrame:target display:YES];
            [report appendFormat:@"OWNER MOVE requested=%@ immediate=%@\n",
                NSStringFromRect(target), NSStringFromRect(window.frame)];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [report appendFormat:@"OWNER MOVE one-second=%@\n", NSStringFromRect(window.frame)];
                [window setFrame:original display:YES];
                [report appendFormat:@"OWNER MOVE restored=%@\n", NSStringFromRect(window.frame)];
                [report writeToFile:request[@"report"] atomically:NO encoding:NSUTF8StringEncoding error:nil];
            });
            break;
        }
    });
}
