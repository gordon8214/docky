// Native macOS 27 menu-extra hosting. Private ABI is checked before use.
#import <AppKit/AppKit.h>
#import <Security/Security.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <sys/stat.h>
#import <unistd.h>

static id objectValue(id obj, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    return [obj respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(obj, sel) : nil;
}
static void sendObject(id obj, NSString *name, id value) {
    SEL sel = NSSelectorFromString(name);
    if ([obj respondsToSelector:sel]) ((void (*)(id, SEL, id))objc_msgSend)(obj, sel, value);
}
static void sendBool(id obj, NSString *name, BOOL value) {
    SEL sel = NSSelectorFromString(name);
    if ([obj respondsToSelector:sel]) ((void (*)(id, SEL, BOOL))objc_msgSend)(obj, sel, value);
}
static void sendVoid(id obj, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    if ([obj respondsToSelector:sel]) ((void (*)(id, SEL))objc_msgSend)(obj, sel);
}
static NSString *bridgeDirectory(void) {
    return [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
        stringByAppendingPathComponent:@"DockyNativeMenuBridge"];
}
static BOOL rectValue(id value, NSRect *rect);
static NSDictionary *readState(NSString *path) {
    struct stat metadata;
    if (lstat(path.fileSystemRepresentation, &metadata) || !S_ISREG(metadata.st_mode)
        || metadata.st_uid != getuid() || (metadata.st_mode & 0777) != 0600
        || metadata.st_size <= 0 || metadata.st_size > 131072) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    id state = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![state isKindOfClass:NSDictionary.class]
        || ![state[@"version"] isKindOfClass:NSNumber.class] || [state[@"version"] intValue] != 1
        || ![state[@"pid"] isKindOfClass:NSNumber.class]
        || ![state[@"session"] isKindOfClass:NSString.class] || [state[@"session"] length] > 128
        || ![state[@"expires"] isKindOfClass:NSNumber.class]
        || ![state[@"items"] isKindOfClass:NSArray.class] || [state[@"items"] count] > 80) return nil;
    for (id item in state[@"items"]) {
        NSRect source, destination;
        if (![item isKindOfClass:NSDictionary.class]
            || ![item[@"id"] isKindOfClass:NSString.class] || [item[@"id"] length] > 1024
            || ![item[@"ownerPID"] isKindOfClass:NSNumber.class] || [item[@"ownerPID"] intValue] <= 0
            || ![item[@"eventTag"] isKindOfClass:NSNumber.class] || [item[@"eventTag"] longLongValue] <= 0
            || !rectValue(item[@"source"], &source) || !rectValue(item[@"destination"], &destination)
            || ![item[@"system"] isKindOfClass:NSNumber.class]
            || (item[@"persistentID"] && ![item[@"persistentID"] isKindOfClass:NSString.class])) return nil;
    }
    id activation = state[@"activation"];
    if (activation && (![activation isKindOfClass:NSDictionary.class]
        || ![activation[@"id"] isKindOfClass:NSString.class]
        || ![activation[@"sequence"] isKindOfClass:NSString.class])) return nil;
    double remaining = [state[@"expires"] doubleValue] - NSDate.date.timeIntervalSince1970;
    if (!isfinite(remaining) || remaining <= 0 || remaining > 4) return nil;
    pid_t owner = [state[@"pid"] intValue];
    if (owner <= 0) return nil;
#ifdef DOCKY_NATIVE_MENU_PROTOCOL_TEST
    return owner == getpid() ? state : nil;
#else
    // The agent sandbox prohibits kill(pid, 0) and SecCode guest inspection.
    // LaunchServices can validate the running owner; the private, same-UID file
    // and short lease bound the local experiment without changing the sandbox.
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:owner];
    return app && !app.isTerminated && [app.bundleIdentifier isEqual:@"gt.quintero.Docky"] ? state : nil;
#endif
}
static BOOL rectValue(id value, NSRect *rect) {
    if (![value isKindOfClass:NSArray.class] || [value count] != 4) return NO;
    for (id number in value)
        if (![number isKindOfClass:NSNumber.class] || !isfinite([number doubleValue])) return NO;
    *rect = NSMakeRect([value[0] doubleValue], [value[1] doubleValue],
                       [value[2] doubleValue], [value[3] doubleValue]);
    return fabs(rect->origin.x) <= 1e6 && fabs(rect->origin.y) <= 1e6
        && rect->size.width > 0 && rect->size.width <= 1024 && rect->size.height > 0 && rect->size.height <= 80;
}
static BOOL destinationIsVisible(NSRect rect) {
    for (NSScreen *screen in NSScreen.screens) if (NSContainsRect(screen.frame, rect)) return YES;
    return NO;
}
static void writeResult(NSDictionary *result) {
    NSString *path = [bridgeDirectory() stringByAppendingPathComponent:@"result.json"];
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    [data writeToFile:path options:NSDataWritingAtomic error:nil];
    chmod(path.fileSystemRepresentation, 0600);
}

@interface DockyNativeMenuPanel : NSPanel @end
@implementation DockyNativeMenuPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

static BOOL performExpandedAction(NSView *view, NSTimeInterval timestamp) {
    id host = objectValue(view, @"host");
    SEL supported = NSSelectorFromString(@"supportsExpandedInterface");
    SEL action = NSSelectorFromString(@"performActionOnItem:");
    if (![host respondsToSelector:supported] || ![host respondsToSelector:action]
        || !((BOOL (*)(id, SEL))objc_msgSend)(host, supported)) return NO;
    ((void (*)(id, SEL, double))objc_msgSend)(host, action, timestamp);
    return YES;
}

@interface DockyNativeStatusEvents : NSView
@property(nonatomic, strong) NSView *hosted;
@property(nonatomic) NSInteger eventTag;
@property(nonatomic) BOOL expandedAction;
@end
@implementation DockyNativeStatusEvents
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }
- (NSEvent *)tagged:(NSEvent *)event {
    return [NSEvent mouseEventWithType:event.type location:event.locationInWindow modifierFlags:event.modifierFlags
        timestamp:event.timestamp windowNumber:event.windowNumber context:nil eventNumber:self.eventTag
        clickCount:event.clickCount pressure:event.pressure] ?: event;
}
- (NSView *)hitTest:(NSPoint)point { return NSPointInRect(point, self.frame) ? self : nil; }
- (void)mouseDown:(NSEvent *)event {
    self.expandedAction = performExpandedAction(self.hosted, event.timestamp);
    if (!self.expandedAction) [self.hosted mouseDown:[self tagged:event]];
}
- (void)mouseUp:(NSEvent *)event {
    if (!self.expandedAction) [self.hosted mouseUp:[self tagged:event]];
    self.expandedAction = NO;
}
- (void)mouseDragged:(NSEvent *)event { [self.hosted mouseDragged:[self tagged:event]]; }
- (void)rightMouseDown:(NSEvent *)event { [self.hosted mouseDown:[self tagged:event]]; }
- (void)rightMouseUp:(NSEvent *)event { [self.hosted mouseUp:[self tagged:event]]; }
@end

@interface DockyNativeMenuEntry : NSObject
@property(nonatomic, strong) NSPanel *panel;
@property(nonatomic, strong) NSView *hosted;
@property(nonatomic, copy) NSString *persistentID;
@property(nonatomic, copy) NSString *identity;
@property(nonatomic) NSInteger eventTag;
@property(nonatomic, strong) id systemPresentation;
@property(nonatomic, weak) NSView *source;
@property(nonatomic, strong) CALayer *remoteLayer;
@property(nonatomic) CGPoint originalLayerAnchor;
@end
@implementation DockyNativeMenuEntry
- (void)invalidate {
    [self.panel orderOut:nil];
    if (self.systemPresentation) {
        self.remoteLayer.anchorPoint = self.originalLayerAnchor;
        sendVoid(self.systemPresentation, @"deactivate");
    }
    sendVoid(self.hosted, @"invalidate");
    [self.hosted removeFromSuperview];
    [self.panel close];
}
@end

static BOOL hasSceneIdentifier(NSView *view, NSString *identifier) {
    if ([objectValue(view, @"scene") description] &&
        [[objectValue(view, @"scene") description] containsString:identifier]) return YES;
    for (NSView *child in view.subviews) if (hasSceneIdentifier(child, identifier)) return YES;
    return NO;
}
static id statusHost(NSDictionary *item, NSView *source) {
    NSArray *hosts = objectValue(NSClassFromString(@"NSStatusItemHost"), @"allHosts");
    NSMutableArray *candidates = NSMutableArray.array;
    for (id host in hosts) {
        SEL pidSelector = NSSelectorFromString(@"pid");
        if (![host respondsToSelector:pidSelector]) continue;
        if (((pid_t (*)(id, SEL))objc_msgSend)(host, pidSelector) != [item[@"ownerPID"] intValue]) continue;
        [candidates addObject:host];
        for (NSDictionary *variant in objectValue(host, @"_variantsDiagnostics")) {
            NSString *identifier = variant[@"sceneIdentifier"];
            if (identifier.length && hasSceneIdentifier(source, identifier)) return host;
        }
    }
    return candidates.count == 1 ? candidates.firstObject : nil;
}
static NSView *sourceContainer(NSDictionary *item) {
    NSRect quartz;
    if (!rectValue(item[@"source"], &quartz)) return nil;
    CGFloat reference = NSMaxY(NSScreen.screens.firstObject.frame);
    for (NSWindow *window in NSApp.windows) {
        if (![NSStringFromClass(window.class) isEqual:@"MenuBarCore.DisplayItemAppKitWindow"]
            || !window.isVisible) continue;
        for (NSView *view in window.contentView.subviews) {
            if (![NSStringFromClass(view.class) containsString:@"SceneHostDisplayItemContainer"]) continue;
            NSRect frame = [window convertRectToScreen:[view convertRect:view.bounds toView:nil]];
            frame.origin.y = reference - NSMaxY(frame);
            if (fabs(NSMidX(frame) - NSMidX(quartz)) < 2 && fabs(frame.origin.y - quartz.origin.y) < 2) return view;
        }
    }
    return nil;
}
static DockyNativeMenuEntry *createEntry(NSDictionary *item, NSRect destination, NSString *identity) {
    NSView *source = sourceContainer(item);
    if (!source) return nil;
    NSView *hosted;
    id presentation = nil;
    NSString *persistentID;
    if ([item[@"system"] boolValue]) {
        NSView *original = nil;
        for (NSView *child in source.subviews)
            if ([NSStringFromClass(child.class) isEqual:@"NSSceneHostingView"]) original = child;
        presentation = objectValue(objectValue(original, @"scene"), @"sh_createPresentation");
        Class cls = NSClassFromString(@"NSSceneHostingView");
        SEL initializer = NSSelectorFromString(@"initWithPresentation:");
        if (!presentation || ![cls instancesRespondToSelector:initializer]) return nil;
        hosted = ((id (*)(id, SEL, id))objc_msgSend)([cls alloc], initializer, presentation);
        sendBool(hosted, @"setTracksContentSize:", NO);
        persistentID = item[@"identifier"];
    } else {
        id host = statusHost(item, source);
        if (!host) return nil;
        hosted = objectValue(host, @"createActiveReplicantView");
        persistentID = objectValue(host, @"persistentIdentifier");
        sendBool(hosted, @"setAppearsActive:", YES);
        sendObject(hosted, @"setDisplayIdentifier:", objectValue(objectValue(host, @"itemView"), @"displayIdentifier"));
        SEL height = NSSelectorFromString(@"setMenuBarHeight:");
        if ([hosted respondsToSelector:height]) ((void (*)(id, SEL, double))objc_msgSend)(hosted, height, destination.size.height);
    }
    if (![hosted isKindOfClass:NSView.class]) return nil;
    DockyNativeMenuEntry *entry = DockyNativeMenuEntry.new;
    entry.hosted = hosted; entry.persistentID = persistentID; entry.identity = identity;
    entry.source = source; entry.systemPresentation = presentation;
    entry.eventTag = [item[@"eventTag"] integerValue];
    entry.panel = [[DockyNativeMenuPanel alloc] initWithContentRect:destination
        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
        backing:NSBackingStoreBuffered defer:NO];
    entry.panel.releasedWhenClosed = NO;
    entry.panel.title = @"Docky Native Menu Extra";
    entry.panel.level = 21;
    entry.panel.opaque = NO; entry.panel.backgroundColor = NSColor.clearColor;
    entry.panel.hasShadow = NO;
    entry.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    NSView *container = entry.panel.contentView;
    if (!presentation) {
        DockyNativeStatusEvents *events = [[DockyNativeStatusEvents alloc] initWithFrame:container.bounds];
        events.hosted = hosted; events.eventTag = [item[@"eventTag"] integerValue];
        events.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [container addSubview:events]; container = events;
    } else {
        // System scene actions use the original AX item, underneath the live icon.
        entry.panel.ignoresMouseEvents = YES;
    }
    hosted.frame = container.bounds;
    hosted.translatesAutoresizingMaskIntoConstraints = YES;
    hosted.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [container addSubview:hosted];
    if (presentation) {
        NSView *surface = objectValue(hosted, @"scenePresentationView");
        sendBool(surface, @"setTracksContentSize:", NO);
        surface.translatesAutoresizingMaskIntoConstraints = YES;
        surface.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        surface.frame = hosted.bounds;
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(presentation, NSSelectorFromString(@"setPriority:"), 100);
        sendVoid(hosted, @"activate");
        sendVoid(presentation, @"activate");
    }
    [entry.panel orderFrontRegardless];
    return entry;
}

@interface DockyNativeMenuRuntime : NSObject
@property(nonatomic, strong) NSMutableDictionary<NSString *, DockyNativeMenuEntry *> *entries;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, copy) NSString *lastActivation;
@end
@implementation DockyNativeMenuRuntime
- (void)tick {
    NSDictionary *state = readState([bridgeDirectory() stringByAppendingPathComponent:@"state.json"]);
    NSArray *items = state[@"items"];
    if (![items isKindOfClass:NSArray.class] || items.count > 80) items = @[];
    NSMutableSet *kept = NSMutableSet.set;
    NSMutableArray *results = NSMutableArray.array;
    for (NSDictionary *item in items) {
        if (![item isKindOfClass:NSDictionary.class] || ![item[@"id"] isKindOfClass:NSString.class]) continue;
        NSRect destination;
        if (!rectValue(item[@"destination"], &destination) || !destinationIsVisible(destination)) continue;
        NSString *key = item[@"id"];
        NSString *identity = [NSString stringWithFormat:@"%@:%@:%@", state[@"session"], item[@"ownerPID"], item[@"source"]];
        DockyNativeMenuEntry *entry = self.entries[key];
        if (entry && (![entry.identity isEqual:identity] || !entry.source.superview)) {
            [entry invalidate]; [self.entries removeObjectForKey:key]; entry = nil;
        }
        if (!entry) entry = createEntry(item, destination, identity);
        if (!entry) continue;
        self.entries[key] = entry; [kept addObject:key];
        if (!NSEqualRects(entry.panel.frame, destination)) [entry.panel setFrame:destination display:YES];
        if (entry.systemPresentation) {
            NSRect native;
            rectValue(item[@"source"], &native);
            entry.hosted.frame = NSMakeRect((destination.size.width - native.size.width) / 2, 0,
                                            native.size.width, destination.size.height);
            CALayer *layer = objectValue(entry.systemPresentation, @"hostingLayer");
            CALayer *remote = layer.sublayers.firstObject;
            if (remote && remote != entry.remoteLayer) {
                entry.remoteLayer = remote; entry.originalLayerAnchor = remote.anchorPoint;
            }
            // MenuBarCore sets the shared scene layer's anchor to zero. A normal
            // ScenePresentationLayer centers it, so restore the expected anchor.
            if (remote) { remote.anchorPoint = CGPointMake(0.5, 0.5); [layer setNeedsLayout]; [layer layoutIfNeeded]; }
        }
        entry.panel.appearance = [NSAppearance appearanceNamed:[state[@"dark"] boolValue] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
        [results addObject:@{@"id": key, @"persistentID": entry.persistentID ?: @"", @"window": @(entry.panel.windowNumber)}];
    }
    for (NSString *key in self.entries.allKeys) if (![kept containsObject:key]) {
        [self.entries[key] invalidate]; [self.entries removeObjectForKey:key];
    }
    NSDictionary *activation = state[@"activation"];
    if ([activation isKindOfClass:NSDictionary.class] && [activation[@"sequence"] isKindOfClass:NSString.class]
        && ![activation[@"sequence"] isEqual:self.lastActivation]) {
        self.lastActivation = activation[@"sequence"];
        DockyNativeMenuEntry *entry = self.entries[activation[@"id"]];
        if (entry.eventTag > 0 && !entry.systemPresentation) {
            if (performExpandedAction(entry.hosted, NSProcessInfo.processInfo.systemUptime)) {
                writeResult(@{@"version": @1, @"session": state[@"session"] ?: @"", @"items": results,
                    @"expires": @(NSDate.date.timeIntervalSince1970 + 1)});
                return;
            }
            NSPoint point = NSMakePoint(NSMidX(entry.hosted.bounds), NSMidY(entry.hosted.bounds));
            point = [entry.hosted convertPoint:point toView:nil];
            NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:0
                timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:entry.panel.windowNumber
                context:nil eventNumber:entry.eventTag clickCount:1 pressure:1];
            NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:point modifierFlags:0
                timestamp:NSProcessInfo.processInfo.systemUptime + 0.06 windowNumber:entry.panel.windowNumber
                context:nil eventNumber:entry.eventTag clickCount:1 pressure:0];
            [entry.hosted mouseDown:down];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                [entry.hosted mouseUp:up];
            });
        }
    }
    writeResult(@{@"version": @1, @"session": state[@"session"] ?: @"", @"items": results,
                   @"expires": @(NSDate.date.timeIntervalSince1970 + 1)});
}

@end

static NSString *statusIdentifier(id item) {
    // Event delivery uses a scene replicant, whose autosave name is empty.
    // Its active item owns the stable identifier and the actual menu.
    for (int depth = 0; depth < 5; depth++) {
        id active = objectValue(item, @"_activeItem");
        if (!active || active == item) break;
        item = active;
    }
    return objectValue(item, @"autosaveName") ?: objectValue(item, @"_defaultAutosaveName");
}

static BOOL eventMatchesTag(NSEvent *event, NSInteger tag) {
    BOOL mouse = event.type == NSEventTypeLeftMouseDown || event.type == NSEventTypeLeftMouseUp
        || event.type == NSEventTypeRightMouseDown || event.type == NSEventTypeRightMouseUp;
    // AppKit's remote status-item transport serializes the event number as Int16.
    return event && mouse && tag > 0 && (int16_t)event.eventNumber == (int16_t)tag;
}

static void writeTracking(NSString *session, BOOL active) {
    NSString *path = [bridgeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"tracking-%d.json", getpid()]];
    NSDictionary *value = @{@"session": session, @"expires": @(active ? NSDate.date.timeIntervalSince1970 + 1 : 0)};
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    [data writeToFile:path options:NSDataWritingAtomic error:nil];
    chmod(path.fileSystemRepresentation, 0600);
}

// Owner-side anchor override is active only while a leased Docky icon is clicked.
static NSDictionary *ownerAnchor(NSStatusItem *item, NSEvent *event) {
    NSDictionary *state = readState([bridgeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"owner-%d.json", getpid()]]);
    if ([state[@"ownerPID"] intValue] != getpid()) return nil;
    NSPoint pointer = NSEvent.mouseLocation;
    for (NSDictionary *entry in state[@"items"]) {
        NSRect rect;
        if (!rectValue(entry[@"destination"], &rect)) continue;
        NSInteger tag = [entry[@"eventTag"] integerValue];
        BOOL tagged = eventMatchesTag(event, tag);
        if (!tagged && !NSPointInRect(pointer, rect)) continue;
        NSString *identifier = entry[@"persistentID"];
        NSString *actual = statusIdentifier(item);
        if (item && ![identifier isEqual:actual]) continue;
        NSMutableDictionary *matched = [entry mutableCopy];
        matched[@"session"] = state[@"session"];
        return matched;
    }
    return nil;
}
static IMP originalMenuPopup;
static NSDictionary *nativePopupPendingEntry(void);
static void menuPopup(id cls, SEL sel, NSMenu *menu, NSStatusItem *item, NSStatusBar *bar,
                      NSRect rect, NSView *view, NSEvent *event) {
    NSDictionary *entry = ownerAnchor(item, event) ?: nativePopupPendingEntry();
    NSRect anchor;
    if (entry && rectValue(entry[@"destination"], &anchor)) {
        [menu update];
        NSPoint point = NSMakePoint(NSMidX(anchor) - menu.size.width / 2, NSMaxY(anchor) + 6 + menu.size.height);
        NSString *session = entry[@"session"];
        writeTracking(session, YES);
        NSTimer *tracking = [NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) {
            (void)timer;
            NSString *path = [bridgeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"owner-%d.json", getpid()]];
            if (![readState(path)[@"session"] isEqual:session]) { [menu cancelTracking]; return; }
            writeTracking(session, YES);
        }];
        [NSRunLoop.mainRunLoop addTimer:tracking forMode:NSRunLoopCommonModes];
        @try { [menu popUpMenuPositioningItem:nil atLocation:point inView:nil]; }
        @finally { [tracking invalidate]; writeTracking(session, NO); }
        return;
    }
    ((void (*)(id, SEL, id, id, id, NSRect, id, id))originalMenuPopup)(cls, sel, menu, item, bar, rect, view, event);
}

#include "popups.h"

#ifndef DOCKY_NATIVE_MENU_PROTOCOL_TEST
__attribute__((constructor)) static void initializeNativeMenus(void) {
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 27) return;
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
        if ([NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.MenuBarAgent"]) {
            SEL key = NSSelectorFromString(@"dockyNativeMenuRuntime");
            if (objc_getAssociatedObject(NSApp, key)) return;
            DockyNativeMenuRuntime *runtime = DockyNativeMenuRuntime.new;
            objc_setAssociatedObject(NSApp, key, runtime, OBJC_ASSOCIATION_RETAIN_NONATOMIC); runtime.entries = NSMutableDictionary.dictionary;
            runtime.timer = [NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) { (void)timer; [runtime tick]; }];
            [NSRunLoop.mainRunLoop addTimer:runtime.timer forMode:NSRunLoopCommonModes];
            [runtime tick];
        } else {
            installNativePopupHooks();
            SEL selector = NSSelectorFromString(@"popUpStatusBarMenu:ofItem:ofBar:inRect:ofView:withEvent:");
            Method method = class_getClassMethod(NSClassFromString(@"NSStatusBarButtonCell"), selector);
            if (method && strcmp(method_getTypeEncoding(method), "v88@0:8@16@24@32{CGRect={CGPoint=dd}{CGSize=dd}}40@72@80") == 0)
                originalMenuPopup = method_setImplementation(method, (IMP)menuPopup);
        }
    });
    CFRunLoopWakeUp(CFRunLoopGetMain());
}

#endif
