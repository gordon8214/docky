// Compiled inside payload.m: owner-side native popover and custom-window anchoring.
static NSRect popupFrame(NSRect proposed, NSRect content, NSRect anchor, NSRect visible) {
    CGFloat x = MAX(NSMinX(visible), MIN(NSMidX(anchor) - content.size.width / 2,
                                       NSMaxX(visible) - content.size.width));
    CGFloat y = MAX(NSMinY(visible), MIN(NSMaxY(anchor) + 6, NSMaxY(visible) - content.size.height));
    proposed.origin = NSMakePoint(x - content.origin.x, y - content.origin.y);
    return proposed;
}
static BOOL popupCandidate(NSWindow *window) {
    NSString *name = NSStringFromClass(window.class).lowercaseString;
    BOOL known = [name containsString:@"modulewindow"] || [name containsString:@"menubarextra"]
        || [name containsString:@"expandedinterface"];
    BOOL panel = [window isKindOfClass:NSPanel.class] && !(window.styleMask & NSWindowStyleMaskTitled)
        && window.level >= 20 && ![name containsString:@"popover"];
    return (known || panel) && window.frame.size.width >= 80 && window.frame.size.height >= 60;
}
static void accessibilityContent(id element, NSRect window, NSRect *content, NSUInteger depth, int *remaining) {
    if (depth > 10 || --*remaining < 0 || ![element respondsToSelector:@selector(accessibilityFrame)]) return;
    NSRect frame = [element accessibilityFrame];
    NSString *role = [element accessibilityRole];
    if (frame.size.width > 0 && frame.size.height > 0 && NSContainsRect(window, frame)
        && ![role isEqual:NSAccessibilityGroupRole] && ![role isEqual:NSAccessibilityWindowRole]
        && frame.size.width * frame.size.height < window.size.width * window.size.height * 0.9)
        *content = NSIsEmptyRect(*content) ? frame : NSUnionRect(*content, frame);
    for (id child in [element accessibilityChildren]) accessibilityContent(child, window, content, depth + 1, remaining);
}
static NSRect popupContent(NSWindow *window) {
    // Control Center surrounds its controls with a large transparent backdrop.
    // Ordinary app panels need their complete frame, including native margins.
    if (![NSStringFromClass(window.class).lowercaseString containsString:@"modulewindow"])
        return NSMakeRect(0, 0, window.frame.size.width, window.frame.size.height);
    NSRect content = NSZeroRect;
    int remaining = 320;
    accessibilityContent(window, window.frame, &content, 0, &remaining);
    if (NSIsEmptyRect(content)) return NSZeroRect;
    content = NSIntersectionRect(NSInsetRect(content, -12, -12), window.frame);
    content.origin.x -= window.frame.origin.x; content.origin.y -= window.frame.origin.y;
    return content;
}
static NSDictionary *ownerLease(void) {
    NSDictionary *state = readState([bridgeDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"owner-%d.json", getpid()]]);
    return [state[@"ownerPID"] intValue] == getpid() ? state : nil;
}
static NSScreen *anchorScreen(NSRect anchor) {
    for (NSScreen *screen in NSScreen.screens) if (NSIntersectsRect(screen.frame, anchor)) return screen;
    return nil;
}

@interface DockyPopupPlacement : NSObject
@property(nonatomic, copy) NSDictionary *entry;
@property(nonatomic) NSRect original;
@property(nonatomic) NSRect content;
@end
@implementation DockyPopupPlacement @end

@interface DockyPopoverPlacement : NSObject
@property(nonatomic, strong) NSPanel *panel;
@property(nonatomic, copy) NSDictionary *entry;
@end
@implementation DockyPopoverPlacement @end

@interface DockyNativePopupRuntime : NSObject
@property(nonatomic, copy) NSDictionary *pending;
@property(nonatomic) NSTimeInterval deadline;
@property(nonatomic, copy) NSString *lastActivation;
@property(nonatomic, strong) NSHashTable<NSWindow *> *previous;
@property(nonatomic, strong) NSHashTable<NSWindow *> *lastVisible;
@property(nonatomic, strong) NSMapTable<NSWindow *, DockyPopupPlacement *> *windows;
@property(nonatomic, strong) NSMapTable<NSPopover *, DockyPopoverPlacement *> *popovers;
@property(nonatomic, strong) NSMapTable<NSStatusItemExpandedInterfaceSession *, NSString *> *expandedSessions;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) BOOL repositioning;
- (void)refreshActivation;
- (void)begin:(NSDictionary *)entry;
- (DockyPopupPlacement *)placementFor:(NSWindow *)window;
- (void)tick;
@end
static DockyNativePopupRuntime *popupRuntime;
static IMP originalFrameCommon, originalPopoverShow, originalStatusDown, originalStatusUp, originalStatusRight;
static IMP originalSceneActions;
static IMP originalExpandedBegin, originalSceneExpandedBegin;
static NSDictionary *nativePopupPendingEntry(void) {
    [popupRuntime refreshActivation];
    return popupRuntime.deadline >= NSDate.date.timeIntervalSince1970 ? popupRuntime.pending : nil;
}

@implementation DockyNativePopupRuntime
- (void)begin:(NSDictionary *)entry {
    self.pending = entry;
    self.deadline = NSDate.date.timeIntervalSince1970 + 1.5;
    // The owner can receive the AX action before its next timer tick. Preserve
    // the preceding visibility snapshot so that first-frame popups stay eligible.
    self.previous = self.lastVisible ?: NSHashTable.weakObjectsHashTable;
}
- (void)refreshActivation {
    NSDictionary *lease = ownerLease(), *activation = lease[@"activation"];
    if (!lease) { self.pending = nil; self.deadline = 0; return; }
    NSString *sequence = activation[@"sequence"];
    if (![sequence isKindOfClass:NSString.class] || [sequence isEqual:self.lastActivation]) return;
    self.lastActivation = sequence;
    NSNumber *time = activation[@"time"];
    if (![time isKindOfClass:NSNumber.class] || fabs(NSDate.date.timeIntervalSince1970 - time.doubleValue) > 1.5) return;
    for (NSDictionary *entry in lease[@"items"]) if ([entry[@"id"] isEqual:activation[@"id"]]) {
        NSMutableDictionary *matched = [entry mutableCopy]; matched[@"session"] = lease[@"session"];
        [self begin:matched]; break;
    }
}
- (DockyPopupPlacement *)placementFor:(NSWindow *)window {
    DockyPopupPlacement *placement = [self.windows objectForKey:window];
    if (placement || !popupCandidate(window) || self.deadline < NSDate.date.timeIntervalSince1970
        || !self.pending || [self.previous containsObject:window]) return placement;
    // NSPopover has its own native positioning view and arrow orientation.
    for (NSPopover *popover in self.popovers.keyEnumerator)
        if (popover.contentViewController.view.window == window) return nil;
    placement = DockyPopupPlacement.new;
    placement.entry = self.pending; placement.original = window.frame;
    [self.windows setObject:placement forKey:window];
    return placement;
}
- (void)tick {
    [self refreshActivation];
    NSDictionary *lease = ownerLease();
    NSString *session = lease[@"session"];
    for (NSStatusItemExpandedInterfaceSession *expanded in self.expandedSessions.keyEnumerator.allObjects)
        if (![[self.expandedSessions objectForKey:expanded] isEqual:session]) {
            [expanded cancel];
            [self.expandedSessions removeObjectForKey:expanded];
        }
    for (NSWindow *window in NSApp.windows) if (window.isVisible && popupCandidate(window)) [self placementFor:window];
    BOOL tracking = NO;
    for (NSWindow *window in self.windows.keyEnumerator.allObjects) {
        DockyPopupPlacement *placement = [self.windows objectForKey:window];
        BOOL valid = [placement.entry[@"session"] isEqual:session];
        NSRect anchor;
        if (!window.isVisible || !valid || !rectValue(placement.entry[@"destination"], &anchor)) {
            self.repositioning = YES;
            if (window.isVisible && !valid) [window orderOut:nil];
            [self.windows removeObjectForKey:window];
            [window setFrame:placement.original display:NO];
            self.repositioning = NO;
            continue;
        }
        self.repositioning = YES;
        NSRect content = popupContent(window);
        if (!NSIsEmptyRect(content)) placement.content = content;
        NSScreen *screen = anchorScreen(anchor);
        if (screen && !NSIsEmptyRect(placement.content)) {
            NSRect frame = popupFrame(window.frame, placement.content, anchor, screen.visibleFrame);
            if (!NSEqualRects(frame, window.frame)) [window setFrame:frame display:YES];
        }
        self.repositioning = NO;
        tracking = YES;
    }
    for (NSPopover *popover in self.popovers.keyEnumerator.allObjects) {
        DockyPopoverPlacement *placement = [self.popovers objectForKey:popover];
        BOOL valid = [placement.entry[@"session"] isEqual:session];
        if (!popover.isShown || !valid) {
            if (popover.isShown) [popover close];
            [placement.panel orderOut:nil]; [placement.panel close];
            [self.popovers removeObjectForKey:popover];
        } else tracking = YES;
    }
    // NSMenu uses its own tracking timer; do not overwrite that signal while idle.
    if (tracking && session) writeTracking(session, YES);
    self.lastVisible = NSHashTable.weakObjectsHashTable;
    for (NSWindow *window in NSApp.windows) if (window.isVisible) [self.lastVisible addObject:window];
}
@end

static void anchoredFrameCommon(NSWindow *window, SEL selector, NSRect frame, BOOL display, BOOL server) {
    if (popupRuntime && !popupRuntime.repositioning && popupCandidate(window)) {
        [popupRuntime refreshActivation];
        DockyPopupPlacement *placement = [popupRuntime placementFor:window];
        if (placement && popupRuntime.pending && popupRuntime.deadline >= NSDate.date.timeIntervalSince1970
            && [NSStringFromClass(window.class).lowercaseString containsString:@"modulewindow"])
            placement.entry = popupRuntime.pending;
        NSRect anchor;
        if (placement && !NSIsEmptyRect(placement.content) && rectValue(placement.entry[@"destination"], &anchor)) {
            NSScreen *screen = anchorScreen(anchor);
            if (screen) frame = popupFrame(frame, placement.content, anchor, screen.visibleFrame);
        }
    }
    ((void (*)(id, SEL, NSRect, BOOL, BOOL))originalFrameCommon)(window, selector, frame, display, server);
}
static void statusMouse(NSView *view, SEL selector, NSEvent *event, IMP original) {
    id item = objectValue(view, @"_statusItem");
    NSDictionary *entry = ownerAnchor(item, event);
    if (entry) [popupRuntime begin:entry];
    ((void (*)(id, SEL, id))original)(view, selector, event);
}
static void statusDown(NSView *view, SEL selector, NSEvent *event) { statusMouse(view, selector, event, originalStatusDown); }
static void statusUp(NSView *view, SEL selector, NSEvent *event) { statusMouse(view, selector, event, originalStatusUp); }
static void statusRight(NSView *view, SEL selector, NSEvent *event) { statusMouse(view, selector, event, originalStatusRight); }
static id sceneActions(id item, SEL selector, id scene, NSSet *actions) {
    NSDictionary *lease = ownerLease();
    for (id action in actions) {
        if (![NSStringFromClass([action class]) isEqual:@"NSStatusItemSendEventAction"]) continue;
        NSInteger number = ((NSInteger (*)(id, SEL))objc_msgSend)(action, @selector(eventNumber));
        for (NSDictionary *entry in lease[@"items"])
            if ((int16_t)number == (int16_t)[entry[@"eventTag"] integerValue]
                && [entry[@"persistentID"] isEqual:statusIdentifier(item)]) {
                NSMutableDictionary *matched = [entry mutableCopy]; matched[@"session"] = lease[@"session"];
                [popupRuntime begin:matched]; break;
            }
    }
    return ((id (*)(id, SEL, id, id))originalSceneActions)(item, selector, scene, actions);
}
static void beginExpanded(id item, SEL selector, double timestamp, IMP original) {
    NSDictionary *entry = ownerAnchor(item, NSApp.currentEvent) ?: nativePopupPendingEntry();
    if (entry) [popupRuntime begin:entry];
    ((void (*)(id, SEL, double))original)(item, selector, timestamp);
    NSStatusItemExpandedInterfaceSession *session = objectValue(item, @"expandedInterfaceSession");
    if (entry && session) [popupRuntime.expandedSessions setObject:entry[@"session"] forKey:session];
}
static void expandedBegin(id item, SEL selector, double timestamp) {
    beginExpanded(item, selector, timestamp, originalExpandedBegin);
}
static void sceneExpandedBegin(id item, SEL selector, double timestamp) {
    beginExpanded(item, selector, timestamp, originalSceneExpandedBegin);
}
static void anchoredPopover(NSPopover *popover, SEL selector, NSRect rect, NSView *view, NSRectEdge edge) {
    NSPanel *previousPanel = [popupRuntime.popovers objectForKey:popover].panel;
    [popupRuntime refreshActivation];
    NSDictionary *entry = ownerAnchor(objectValue(view, @"_statusItem"), NSApp.currentEvent);
    if (!entry && popupRuntime.deadline >= NSDate.date.timeIntervalSince1970) entry = popupRuntime.pending;
    NSRect anchor;
    if (entry && rectValue(entry[@"destination"], &anchor) && anchorScreen(anchor)) {
        DockyPopoverPlacement *placement = DockyPopoverPlacement.new;
        placement.entry = entry;
        placement.panel = [[DockyNativeMenuPanel alloc] initWithContentRect:anchor
            styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        placement.panel.releasedWhenClosed = NO; placement.panel.level = 21;
        placement.panel.opaque = NO; placement.panel.backgroundColor = NSColor.clearColor;
        placement.panel.hasShadow = NO; placement.panel.ignoresMouseEvents = YES;
        [placement.panel setAccessibilityElement:NO];
        [placement.panel orderFrontRegardless];
        [popupRuntime.popovers setObject:placement forKey:popover];
        rect = placement.panel.contentView.bounds; view = placement.panel.contentView; edge = NSRectEdgeMaxY;
    }
    ((void (*)(id, SEL, NSRect, id, NSRectEdge))originalPopoverShow)(popover, selector, rect, view, edge);
    if (previousPanel) { [previousPanel orderOut:nil]; [previousPanel close]; }
}
static IMP replaceMethod(Class cls, SEL selector, IMP replacement, const char *encoding) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || strcmp(method_getTypeEncoding(method), encoding)) return NULL;
    IMP original = method_getImplementation(method);
    if (!class_addMethod(cls, selector, replacement, encoding)) method_setImplementation(method, replacement);
    return original;
}
static void installNativePopupHooks(void) {
    SEL key = NSSelectorFromString(@"dockyNativePopupRuntime");
    DockyNativePopupRuntime *existing = objc_getAssociatedObject(NSApp, key);
    if (existing) { popupRuntime = existing; return; }
    popupRuntime = DockyNativePopupRuntime.new;
    popupRuntime.windows = NSMapTable.weakToStrongObjectsMapTable;
    popupRuntime.popovers = NSMapTable.weakToStrongObjectsMapTable;
    popupRuntime.expandedSessions = NSMapTable.weakToStrongObjectsMapTable;
    objc_setAssociatedObject(NSApp, key, popupRuntime, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    originalFrameCommon = replaceMethod(NSWindow.class, NSSelectorFromString(@"_setFrameCommon:display:fromServer:"),
        (IMP)anchoredFrameCommon, "v56@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16B48B52");
    originalPopoverShow = replaceMethod(NSPopover.class, @selector(showRelativeToRect:ofView:preferredEdge:),
        (IMP)anchoredPopover, "v64@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16@48Q56");
    Class button = NSClassFromString(@"NSStatusBarButton");
    originalStatusDown = replaceMethod(button, @selector(mouseDown:), (IMP)statusDown, "v24@0:8@16");
    originalStatusUp = replaceMethod(button, @selector(mouseUp:), (IMP)statusUp, "v24@0:8@16");
    originalStatusRight = replaceMethod(button, @selector(rightMouseDown:), (IMP)statusRight, "v24@0:8@16");
    originalSceneActions = replaceMethod(NSClassFromString(@"NSSceneStatusItem"), NSSelectorFromString(@"scene:handleActions:"),
        (IMP)sceneActions, "@32@0:8@16@24");
    SEL begin = NSSelectorFromString(@"_beginExpandedInterfaceSession:");
    originalExpandedBegin = replaceMethod(NSStatusItem.class, begin, (IMP)expandedBegin, "v24@0:8d16");
    originalSceneExpandedBegin = replaceMethod(NSClassFromString(@"NSSceneStatusItem"), begin,
        (IMP)sceneExpandedBegin, "v24@0:8d16");
    popupRuntime.timer = [NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) { (void)timer; [popupRuntime tick]; }];
    [NSRunLoop.mainRunLoop addTimer:popupRuntime.timer forMode:NSRunLoopCommonModes];
}
