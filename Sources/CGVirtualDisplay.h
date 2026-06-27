// CGVirtualDisplay.h
// Deklarasi private API CoreGraphics untuk virtual display.
// Catatan: ini API tak terdokumentasi; signature bisa berubah antar versi macOS.

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@class CGVirtualDisplay;

@interface CGVirtualDisplayDescriptor : NSObject
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, copy)   NSString *name;

@property(nonatomic, assign) uint32_t maxPixelsWide;
@property(nonatomic, assign) uint32_t maxPixelsHigh;
@property(nonatomic, assign) CGSize   sizeInMillimeters;

@property(nonatomic, assign) uint32_t serialNum;
@property(nonatomic, assign) uint32_t productID;
@property(nonatomic, assign) uint32_t vendorID;

@property(nonatomic, copy, nullable)
    void (^terminationHandler)(NSError * _Nullable err,
                               CGVirtualDisplay * _Nullable display);
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(uint32_t)width
                       height:(uint32_t)height
                  refreshRate:(double)refreshRate;
@property(nonatomic, readonly) uint32_t width;
@property(nonatomic, readonly) uint32_t height;
@property(nonatomic, readonly) double   refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic, strong) NSArray<CGVirtualDisplayMode *> *modes;
@property(nonatomic, assign) uint32_t hiDPI;
@end

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings
    NS_SWIFT_NAME(apply(_:));
@property(nonatomic, readonly) CGDirectDisplayID displayID;
@end

NS_ASSUME_NONNULL_END
