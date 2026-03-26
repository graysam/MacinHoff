#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MHRadioTransportState) {
    MHRadioTransportStateIdle = 0,
    MHRadioTransportStateReceiving = 1,
    MHRadioTransportStateTransmitting = 2,
    MHRadioTransportStateFault = 3,
};

@interface MHHackRFDeviceSnapshot : NSObject

@property (nonatomic, copy) NSString *serialNumber;
@property (nonatomic, copy) NSString *boardName;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *firmwareVersion;
@property (nonatomic, copy) NSString *usbAPIVersion;
@property (nonatomic, assign) NSInteger sharedUSBDeviceCount;

- (instancetype)initWithSerialNumber:(NSString *)serialNumber
                           boardName:(NSString *)boardName
                         displayName:(NSString *)displayName
                     firmwareVersion:(NSString *)firmwareVersion
                      usbAPIVersion:(NSString *)usbAPIVersion
                sharedUSBDeviceCount:(NSInteger)sharedUSBDeviceCount NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface MHRadioStatusSnapshot : NSObject

@property (nonatomic, copy) NSArray<MHHackRFDeviceSnapshot *> *devices;
@property (nonatomic, copy) NSString *libraryVersion;
@property (nonatomic, copy, nullable) NSString *connectedSerialNumber;
@property (nonatomic, copy) NSString *connectionSummary;
@property (nonatomic, copy, nullable) NSString *lastError;
@property (nonatomic, assign) MHRadioTransportState transportState;
@property (nonatomic, copy) NSArray<NSNumber *> *spectrumBins;
@property (nonatomic, assign) BOOL ampEnabled;
@property (nonatomic, assign) NSInteger lnaGain;
@property (nonatomic, assign) NSInteger vgaGain;
@property (nonatomic, assign) NSInteger txVGAGain;
@property (nonatomic, assign) double sampleRate;
@property (nonatomic, assign) uint64_t tunedFrequencyHz;

- (instancetype)initWithDevices:(NSArray<MHHackRFDeviceSnapshot *> *)devices
                  libraryVersion:(NSString *)libraryVersion
            connectedSerialNumber:(nullable NSString *)connectedSerialNumber
               connectionSummary:(NSString *)connectionSummary
                        lastError:(nullable NSString *)lastError
                   transportState:(MHRadioTransportState)transportState
                     spectrumBins:(NSArray<NSNumber *> *)spectrumBins
                       ampEnabled:(BOOL)ampEnabled
                          lnaGain:(NSInteger)lnaGain
                          vgaGain:(NSInteger)vgaGain
                        txVGAGain:(NSInteger)txVGAGain
                       sampleRate:(double)sampleRate
                 tunedFrequencyHz:(uint64_t)tunedFrequencyHz NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface MHRadioEngineBridge : NSObject

- (MHRadioStatusSnapshot *)refreshStatus;
- (MHRadioStatusSnapshot *)currentStatus;
- (MHRadioStatusSnapshot *)connectToSerialNumber:(nullable NSString *)serialNumber;
- (MHRadioStatusSnapshot *)disconnectDevice;
- (MHRadioStatusSnapshot *)startRX;
- (MHRadioStatusSnapshot *)stopRX;
- (MHRadioStatusSnapshot *)applyFrequencyHz:(uint64_t)frequencyHz
                                 sampleRate:(double)sampleRate
                                 ampEnabled:(BOOL)ampEnabled
                                    lnaGain:(NSInteger)lnaGain
                                    vgaGain:(NSInteger)vgaGain
                                  txVGAGain:(NSInteger)txVGAGain;

@end

NS_ASSUME_NONNULL_END
