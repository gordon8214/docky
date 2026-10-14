// Exercise the payload's display-cache forwarding without injecting into Dock.
#import "../payload.m"

static NSMutableArray<NSArray<NSNumber *> *> *calls;
static int fakeConnection(void) { return 1; }
static int fakeSet(int connection, CGRect rect, int reason, int orientation) {
    (void)connection; (void)rect; (void)reason; (void)orientation;
    return 0;
}
static int fakeBroadcast(uint32_t type, void *data, uint32_t size) {
    (void)type; (void)data; (void)size;
    return 0;
}
static int fakeGet(int connection, CGRect *rect, int *reason, int *orientation) {
    (void)connection;
    *rect = CGRectZero; *reason = 2; *orientation = 2;
    return 0;
}
static void fakeInfo(id object, SEL selector, uint32_t display, double inset, double maximum, uint32_t orientation) {
    (void)object; (void)selector;
    [calls addObject:@[@(display), @(inset), @(maximum), @(orientation)]];
}
static void require(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "%s\n", message.UTF8String); exit(1); }
}
static void checkOwnerAuthentication(void) {
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    require([NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:NO
                                                   attributes:nil error:nil], @"Could not create authentication fixture");
    statePath = [directory stringByAppendingPathComponent:@"state.plist"];
    NSDictionary *state = @{@"active": @YES, @"reservationOwnerActive": @YES,
                            @"ownerPID": @(getpid()), @"sessionID": @"fixture"};
    require([state writeToFile:statePath atomically:YES], @"Could not write authentication fixture");
    require(chmod(statePath.fileSystemRepresentation, 0600) == 0, @"Could not protect authentication fixture");
    NSMutableDictionary *request = [@{@"session": @"wrong-session", @"revision": @1,
                                     @"display": @1, @"reason": @0, @"orientation": @2} mutableCopy];
    require([acceptRequest(request, getpid())[@"error"] isEqual:@"Invalid owner/session"],
            @"Session authentication must precede code signature validation");
    request[@"session"] = @"fixture";
    require([acceptRequest(request, getpid())[@"error"] containsString:@"code signature"],
            @"An unsigned owner must be rejected with a code signature diagnostic");
    [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
}
int main(void) {
    @autoreleasepool {
        checkOwnerAuthentication();
        calls = [NSMutableArray array];
        appleDisplayInfo = [NSMutableDictionary dictionary];
        originalInfo = fakeInfo; originalSet = fakeSet; originalBroadcast = fakeBroadcast;
        mainConnection = fakeConnection; getRect = fakeGet;
        coordinator = [NSObject new];
        SEL selector = NSSelectorFromString(@"setDockInfoWithDisplayID:currentInset:maximumInset:orientation:");
        active = YES; desiredDisplay = 1; desiredReason = 0; desiredOrientation = 2;
        desiredRect = CGRectMake(0, 800, 1440, 70);
        interceptedInfo(coordinator, selector, 1, 40, 60, 2);
        [calls removeAllObjects];
        interceptedInfo(coordinator, selector, 2, 0, 55, 3);
        require(calls.count == 2, @"Both the non-owned and owned displays must be updated");
        require([calls[0] isEqual:@[@2, @0, @55, @3]], @"Non-owned display callback was lost");
        require([calls[1] isEqual:@[@1, @70, @70, @2]], @"Owned inset was not republished");
        releasePreviousDisplay();
        require([calls.lastObject isEqual:@[@1, @40, @60, @2]], @"Rollback used another display's snapshot");
        desiredDisplay = 2;
        releasePreviousDisplay();
        require([calls.lastObject isEqual:@[@2, @0, @55, @3]], @"Second display snapshot was lost");
        active = NO;
        bridgeError = missingCoordinator;
        coordinator = nil;
        interceptedInfo([NSObject new], selector, 2, 0, 0, 2);
        require(coordinator != nil && bridgeError == nil, @"Late coordinator discovery must recover");
        bridgeError = @"Unrelated failure";
        interceptedInfo(coordinator, selector, 2, 0, 0, 2);
        require([bridgeError isEqual:@"Unrelated failure"], @"Recovery cleared an unrelated failure");
        puts("Dock payload display-cache and coordinator recovery regressions passed");
    }
    return 0;
}
