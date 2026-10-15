// Live cross-process fixture: native NSPopover and a custom menu-extra window.
#import <AppKit/AppKit.h>
@interface DockyPopoverFixture : NSObject <NSApplicationDelegate, NSStatusItemExpandedInterfaceDelegate>
@property(strong) NSArray<NSStatusItem *> *items;
@property(strong) NSPopover *popover;
@property(strong) NSPanel *panel;
@property(strong) NSStatusItemExpandedInterfaceSession *expandedSession;
@property NSInteger count;
@end
@implementation DockyPopoverFixture
- (void)reportSession:(BOOL)active {
    NSString *directory = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
        stringByAppendingPathComponent:@"DockyNativeMenuBridge"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"active": @(active), @"pid": @(getpid())}
        options:0 error:nil];
    [data writeToFile:[directory stringByAppendingPathComponent:@"fixture-session.json"] atomically:YES];
}
- (NSView *)content:(NSString *)title {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 180)];
    NSTextField *label = [NSTextField labelWithString:title]; label.frame = NSMakeRect(20, 130, 260, 24);
    label.font = [NSFont boldSystemFontOfSize:16]; [view addSubview:label];
    NSButton *count = [NSButton buttonWithTitle:@"Count: 0" target:self action:@selector(increment:)];
    count.frame = NSMakeRect(20, 80, 260, 32); [view addSubview:count];
    NSButton *close = [NSButton buttonWithTitle:@"Close" target:self action:@selector(close:)];
    close.frame = NSMakeRect(20, 30, 260, 32); [view addSubview:close];
    return view;
}
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    (void)note;
    NSMutableArray *items = NSMutableArray.array;
    NSArray *names = @[@"Docky Native Popover Fixture", @"Docky Custom Window Fixture"];
    NSArray *symbols = @[@"bubble.left.fill", @"rectangle.on.rectangle"];
    for (int i = 0; i < 2; i++) {
        BOOL expanded = [NSProcessInfo.processInfo.arguments containsObject:@"--expanded-window-only"];
        if ((expanded || [NSProcessInfo.processInfo.arguments containsObject:@"--custom-window-only"]) && i == 0) continue;
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--popover-only"] && i == 1) continue;
        NSStatusItem *item = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
        item.autosaveName = names[i]; item.button.toolTip = names[i];
        item.button.image = [NSImage imageWithSystemSymbolName:symbols[i] accessibilityDescription:names[i]];
        [item.button setAccessibilityLabel:names[i]];
        item.button.target = self; item.button.action = i ? @selector(showWindow:) : @selector(showPopover:);
        if (expanded) item.expandedInterfaceDelegate = self;
        [items addObject:item];
    }
    self.items = items;
    [NSTimer scheduledTimerWithTimeInterval:600 repeats:NO block:^(NSTimer *timer) { (void)timer; [NSApp terminate:nil]; }];
}
- (void)statusItem:(NSStatusItem *)item didBeginExpandedInterfaceSession:(NSStatusItemExpandedInterfaceSession *)session {
    self.expandedSession = session;
    [self reportSession:YES];
    [self showWindow:item.button];
}
- (void)statusItemDidEndExpandedInterfaceSession:(NSStatusItem *)item animated:(BOOL)animated {
    (void)item; (void)animated;
    self.expandedSession = nil;
    [self reportSession:NO];
    [self.panel orderOut:nil];
}
- (void)showPopover:(NSStatusBarButton *)button {
    if (self.popover.isShown) { [self.popover close]; return; }
    self.popover = NSPopover.new; self.popover.behavior = NSPopoverBehaviorTransient; self.popover.animates = NO;
    NSViewController *controller = NSViewController.new; controller.view = [self content:@"Native NSPopover"];
    self.popover.contentViewController = controller; self.popover.contentSize = controller.view.frame.size;
    [self.popover showRelativeToRect:button.bounds ofView:button preferredEdge:NSRectEdgeMinY];
}
- (void)showWindow:(NSStatusBarButton *)button {
    if (self.panel.isVisible) { [self.panel orderOut:nil]; return; }
    if (!self.panel) {
        self.panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 300, 180)
            styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        self.panel.title = @"Docky Custom Window Fixture"; self.panel.releasedWhenClosed = NO;
        self.panel.level = NSPopUpMenuWindowLevel; self.panel.contentView = [self content:@"Native custom window"];
    }
    NSRect source = [button.window convertRectToScreen:[button convertRect:button.bounds toView:nil]];
    [self.panel setFrameOrigin:NSMakePoint(NSMinX(source), NSMinY(source) - 180)];
    [self.panel orderFrontRegardless];
}
- (void)increment:(NSButton *)sender { sender.title = [NSString stringWithFormat:@"Count: %ld", ++self.count]; }
- (void)close:(id)sender {
    (void)sender;
    [self.expandedSession cancel]; [self.popover close]; [self.panel orderOut:nil];
}
@end
int main(void) { @autoreleasepool {
    NSApplication *app = NSApplication.sharedApplication; DockyPopoverFixture *delegate = DockyPopoverFixture.new;
    app.delegate = delegate; [app setActivationPolicy:NSApplicationActivationPolicyAccessory]; [app run];
} }
