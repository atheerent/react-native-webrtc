
#import "VideoCaptureController.h"

#import <React/RCTLog.h>
#import <WebRTC/WebRTC.h>

@implementation VideoCaptureController {
    RTCAtheerVideoCapturer *_atheerCapturer;
    RTCCameraVideoCapturer *_capturer;
    NSString *_deviceId;
    BOOL _running;
    BOOL _usingFrontCamera;
    int _width;
    int _height;
    int _fps;

    BOOL _usingAtheerCapturer;
}

-(instancetype)initWithCapturer:(RTCCameraVideoCapturer *)capturer
                 andConstraints:(NSDictionary *)constraints {
    self = [super init];
    if (self) {
        _capturer = capturer;
        _running = NO;

        // Default to the front camera.
        _usingFrontCamera = YES;

        _deviceId = constraints[@"deviceId"];
        _width = [constraints[@"width"] intValue];
        _height = [constraints[@"height"] intValue];
        _fps = [constraints[@"frameRate"] intValue];

        id facingMode = constraints[@"facingMode"];

        if (facingMode && [facingMode isKindOfClass:[NSString class]]) {
            AVCaptureDevicePosition position;
            if ([facingMode isEqualToString:@"environment"]) {
                position = AVCaptureDevicePositionBack;
            } else if ([facingMode isEqualToString:@"user"]) {
                position = AVCaptureDevicePositionFront;
            } else {
                // If the specified facingMode value is not supported, fall back
                // to the front camera.
                position = AVCaptureDevicePositionFront;
            }

            _usingFrontCamera = position == AVCaptureDevicePositionFront;
        }
    }

    return self;
}

-(void)startCapture {
    AVCaptureDevice *device;
    if (_deviceId) {
        device = [AVCaptureDevice deviceWithUniqueID:_deviceId];
    }
    if (!device) {
        AVCaptureDevicePosition position
            = _usingFrontCamera
                ? AVCaptureDevicePositionFront
                : AVCaptureDevicePositionBack;
        device = [self findDeviceForPosition:position];
    }

    if (!device) {
        RCTLogWarn(@"[VideoCaptureController] No capture devices found!");

        return;
    }

    AVCaptureDeviceFormat *format
        = [self selectFormatForDevice:device
                      withTargetWidth:_width
                     withTargetHeight:_height];
    if (!format) {
        RCTLogWarn(@"[VideoCaptureController] No valid formats for device %@", device);

        return;
    }

    RCTLog(@"[VideoCaptureController] Capture will start");

    // Starting the capture happens on another thread. Wait for it.
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    [_capturer startCaptureWithDevice:device format:format fps:_fps completionHandler:^(NSError *err) {
        if (err) {
            RCTLogError(@"[VideoCaptureController] Error starting capture: %@", err);
        } else {
            RCTLog(@"[VideoCaptureController] Capture started");
            self->_running = YES;
        }
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

-(void)stopCapture {
    if (!_running)
        return;

    RCTLog(@"[VideoCaptureController] Capture will stop");

    // Stopping the capture happens on another thread. Wait for it.
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    [_capturer stopCaptureWithCompletionHandler:^{
        RCTLog(@"[VideoCaptureController] Capture stopped");
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

-(void)switchCamera {
    _usingFrontCamera = !_usingFrontCamera;
    _deviceId = NULL;

    [self startCapture];
}

-(void)setAtheerCapturer:(RTCCameraVideoCapturer *)atheerCapturer {
    RCTLogWarn(@"[VideoCaptureController] setAtheerCapturer");
    _atheerCapturer = atheerCapturer;
    _usingAtheerCapturer = NO;
}

-(void)switchAtheerBuffer {
    RCTLogWarn(@"[VideoCaptureController] switchAtheerBuffer");
    if (_usingAtheerCapturer) {
        RCTLogWarn(@"[VideoCaptureController] Stopping AR Capturer");
        [_atheerCapturer stopCapture];
    } else {
        RCTLogWarn(@"[VideoCaptureController] Starting AR Capturer");
        [_atheerCapturer startCapturingFromAtheerBuffer];
    }
    _usingAtheerCapturer = !_usingAtheerCapturer;
}

#pragma mark Private

- (AVCaptureDevice *)findDeviceForPosition:(AVCaptureDevicePosition)position {
    NSArray<AVCaptureDevice *> *captureDevices = [RTCCameraVideoCapturer captureDevices];
    for (AVCaptureDevice *device in captureDevices) {
        if (device.position == position) {
            return device;
        }
    }

    return [captureDevices firstObject];
}

- (AVCaptureDeviceFormat *)selectFormatForDevice:(AVCaptureDevice *)device
                                 withTargetWidth:(int)targetWidth
                                withTargetHeight:(int)targetHeight {
    NSArray<AVCaptureDeviceFormat *> *formats =
    [RTCCameraVideoCapturer supportedFormatsForDevice:device];
    AVCaptureDeviceFormat *selectedFormat = nil;
    int currentDiff = INT_MAX;

    for (AVCaptureDeviceFormat *format in formats) {
        CMVideoDimensions dimension = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
        FourCharCode pixelFormat = CMFormatDescriptionGetMediaSubType(format.formatDescription);
        int diff = abs(targetWidth - dimension.width) + abs(targetHeight - dimension.height);
        if (diff < currentDiff) {
            selectedFormat = format;
            currentDiff = diff;
        } else if (diff == currentDiff && pixelFormat == [_capturer preferredOutputPixelFormat]) {
            selectedFormat = format;
        }
    }

    return selectedFormat;
}

@end
