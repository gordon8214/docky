#define DOCKY_NATIVE_MENU_PROTOCOL_TEST 1
#import "../payload.m"
#import <assert.h>
@interface MenuIdentityFixture : NSObject
@property(nonatomic, strong) id active;
@property(nonatomic, copy) NSString *autosaveName;
@end
@implementation MenuIdentityFixture
- (id)_activeItem { return self.active ?: self; }
@end
int main(void) {
    @autoreleasepool {
        MenuIdentityFixture *original = MenuIdentityFixture.new;
        original.autosaveName = @"Item-0";
        MenuIdentityFixture *replicant = MenuIdentityFixture.new;
        replicant.active = original;
        assert([statusIdentifier(replicant) isEqual:@"Item-0"]);
        assert([statusIdentifier(original) isEqual:@"Item-0"]);
        NSEvent *remote = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSZeroPoint
            modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:-30828 clickCount:1 pressure:1];
        assert(eventMatchesTag(remote, 1156679572));
        assert(!eventMatchesTag(remote, 1156679573));
        assert(!eventMatchesTag(nil, 1156679572));
        NSRect rect;
        assert(rectValue(@[@(-1440), @(-800), @32, @28], &rect));
        assert(!rectValue(@[@0, @0, @0, @28], &rect));
        assert(!rectValue(@[@0, @0, @32, @800], &rect));
        assert(!rectValue(@[@0, @0, @"32", @28], &rect));
        assert(!rectValue(@[@0, @0, @32], &rect));
        NSRect anchored = popupFrame(NSMakeRect(1016, 5, 656, 962), NSMakeRect(162, 398, 316, 534),
            NSMakeRect(1353, 7, 34, 34), NSMakeRect(0, 48, 1496, 891));
        assert(anchored.origin.y + 398 >= 48);
        assert(anchored.origin.x + 162 + 316 <= 1496);
        NSRect negative = popupFrame(NSMakeRect(0, 0, 400, 400), NSMakeRect(0, 0, 400, 400),
            NSMakeRect(-1400, -780, 32, 28), NSMakeRect(-1440, -800, 1440, 900));
        assert(negative.origin.x >= -1440 && negative.origin.y >= -800);
        Method frameMethod = class_getInstanceMethod(NSWindow.class, NSSelectorFromString(@"_setFrameCommon:display:fromServer:"));
        assert(frameMethod && strcmp(method_getTypeEncoding(frameMethod), "v56@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16B48B52") == 0);
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSMutableDictionary *state = [@{@"version": @1, @"pid": @(getpid()), @"session": @"test",
            @"expires": @(NSDate.date.timeIntervalSince1970 + 3), @"items": @[]} mutableCopy];
        void (^save)(void) = ^{
            NSData *data = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
            [data writeToFile:path atomically:YES]; chmod(path.fileSystemRepresentation, 0600);
        };
        save(); assert(readState(path));
        chmod(path.fileSystemRepresentation, 0644); assert(!readState(path));
        save(); state[@"expires"] = @(NSDate.date.timeIntervalSince1970 - 1); save(); assert(!readState(path));
        state[@"expires"] = @(NSDate.date.timeIntervalSince1970 + 60); save(); assert(!readState(path));
        state[@"expires"] = @(NSDate.date.timeIntervalSince1970 + 3);
        state[@"pid"] = @(-1); save(); assert(!readState(path));
        state[@"pid"] = @(getpid()); state[@"version"] = @2; save(); assert(!readState(path));
        state[@"version"] = @1; state[@"expires"] = NSNull.null; save(); assert(!readState(path));
        state[@"expires"] = @(NSDate.date.timeIntervalSince1970 + 3);
        state[@"items"] = @[@"invalid"]; save(); assert(!readState(path));
        NSMutableDictionary *item = [@{@"id": @"test", @"ownerPID": @(getpid()), @"eventTag": @12345,
            @"source": @[@0, @0, @34, @28], @"destination": @[@100, @10, @34, @28], @"system": @NO} mutableCopy];
        state[@"items"] = @[item]; save(); assert(readState(path));
        item[@"eventTag"] = NSNull.null; save(); assert(!readState(path));
        item[@"eventTag"] = @12345;
        state[@"activation"] = @{@"id": NSNull.null, @"sequence": @"request"}; save(); assert(!readState(path));
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        assert(!readState(path));
        puts("Native menu lease, identity, permissions, and geometry checks passed");
    }
}
