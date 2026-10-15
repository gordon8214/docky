// One-shot owner-side experiment using the owner's original NSMenu object.
// This payload installs no persistent hooks and never moves rendered windows.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <sys/stat.h>
#import <unistd.h>

#ifndef DOCKY_ANCHOR_REQUEST
#error Define the absolute path to the one-shot request at build time.
#endif

static NSString *reportPath;
static void report(NSString *text) {
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", NSDate.date, text];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:reportPath];
    if (!file) return;
    [file seekToEndOfFile];
    [file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [file closeFile];
}

__attribute__((constructor)) static void initializeOwnerAnchor(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        struct stat metadata;
        if (lstat(DOCKY_ANCHOR_REQUEST, &metadata) != 0 || !S_ISREG(metadata.st_mode)
            || metadata.st_uid != getuid() || (metadata.st_mode & 0777) != 0600) return;
        NSData *data = [NSData dataWithContentsOfFile:@DOCKY_ANCHOR_REQUEST];
        NSDictionary *request = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![request isKindOfClass:NSDictionary.class]
            || ![request[@"bundle"] isEqualToString:NSBundle.mainBundle.bundleIdentifier]
            || [request[@"pid"] intValue] != getpid()) return;
        NSTimeInterval remaining = [request[@"expires"] doubleValue] - [NSDate.date timeIntervalSince1970];
        if (remaining <= 0 || remaining > 60) return;
        NSArray *rect = request[@"anchor"];
        if (![rect isKindOfClass:NSArray.class] || rect.count != 4) return;
        for (id value in rect) if (![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue])) return;
        NSRect anchor = NSMakeRect([rect[0] doubleValue], [rect[1] doubleValue],
                                  [rect[2] doubleValue], [rect[3] doubleValue]);
        reportPath = request[@"report"];
        if (![reportPath isKindOfClass:NSString.class] || !reportPath.isAbsolutePath) return;
        NSStatusBar *bar = NSStatusBar.systemStatusBar;
        Ivar itemsIvar = class_getInstanceVariable(NSStatusBar.class, "_items");
        id storage = itemsIvar ? object_getIvar(bar, itemsIvar) : nil;
        if (![storage isKindOfClass:NSPointerArray.class]) { report(@"Status-item storage unavailable"); return; }
        NSMutableArray<NSMenu *> *menus = NSMutableArray.array;
        for (id item in [(NSPointerArray *)storage allObjects]) {
            if (![item isKindOfClass:NSStatusItem.class]) continue;
            NSMenu *menu = [(NSStatusItem *)item menu];
            if (menu && ![menus containsObject:menu]) [menus addObject:menu];
        }
        if (menus.count != 1) {
            report([NSString stringWithFormat:@"Expected one original status menu; found %lu", menus.count]);
            return;
        }
        NSMenu *menu = menus.firstObject;
        [menu update];
        NSSize size = menu.size;
        NSPoint point = NSMakePoint(NSMidX(anchor) - size.width / 2, NSMaxY(anchor) + 8 + size.height);
        report([NSString stringWithFormat:@"Presenting original menu %p items=%ld at %@ size %@",
                 (__bridge void *)menu, menu.numberOfItems, NSStringFromPoint(point), NSStringFromSize(size)]);
        BOOL selected = [menu popUpMenuPositioningItem:nil atLocation:point inView:nil];
        report([NSString stringWithFormat:@"Original menu closed; selected=%d", selected]);
    });
}
