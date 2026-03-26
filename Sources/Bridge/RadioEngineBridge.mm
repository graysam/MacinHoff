#import "RadioEngineBridge.h"

#import <memory>
#import <optional>

#import "HackRFManager.hpp"

using macinhoff::DeviceInfo;
using macinhoff::HackRFManager;
using macinhoff::StatusSnapshot;
using macinhoff::TransportState;

@implementation MHHackRFDeviceSnapshot

- (instancetype)initWithSerialNumber:(NSString *)serialNumber
                           boardName:(NSString *)boardName
                         displayName:(NSString *)displayName
                     firmwareVersion:(NSString *)firmwareVersion
                      usbAPIVersion:(NSString *)usbAPIVersion
                sharedUSBDeviceCount:(NSInteger)sharedUSBDeviceCount {
    self = [super init];
    if (self) {
        _serialNumber = [serialNumber copy];
        _boardName = [boardName copy];
        _displayName = [displayName copy];
        _firmwareVersion = [firmwareVersion copy];
        _usbAPIVersion = [usbAPIVersion copy];
        _sharedUSBDeviceCount = sharedUSBDeviceCount;
    }
    return self;
}

@end

@implementation MHRadioStatusSnapshot

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
                 tunedFrequencyHz:(uint64_t)tunedFrequencyHz {
    self = [super init];
    if (self) {
        _devices = [devices copy];
        _libraryVersion = [libraryVersion copy];
        _connectedSerialNumber = [connectedSerialNumber copy];
        _connectionSummary = [connectionSummary copy];
        _lastError = [lastError copy];
        _transportState = transportState;
        _spectrumBins = [spectrumBins copy];
        _ampEnabled = ampEnabled;
        _lnaGain = lnaGain;
        _vgaGain = vgaGain;
        _txVGAGain = txVGAGain;
        _sampleRate = sampleRate;
        _tunedFrequencyHz = tunedFrequencyHz;
    }
    return self;
}

@end

static MHRadioTransportState transportStateForSnapshot(const TransportState state) {
    switch (state) {
        case TransportState::idle:
            return MHRadioTransportStateIdle;
        case TransportState::receiving:
            return MHRadioTransportStateReceiving;
        case TransportState::transmitting:
            return MHRadioTransportStateTransmitting;
        case TransportState::fault:
            return MHRadioTransportStateFault;
    }
}

static NSString *stringFromStdString(const std::string &value) {
    return [[NSString alloc] initWithBytes:value.data() length:value.size() encoding:NSUTF8StringEncoding] ?: @"";
}

static MHHackRFDeviceSnapshot *deviceSnapshotFromInfo(const DeviceInfo &deviceInfo) {
    return [[MHHackRFDeviceSnapshot alloc] initWithSerialNumber:stringFromStdString(deviceInfo.serialNumber)
                                                      boardName:stringFromStdString(deviceInfo.boardName)
                                                    displayName:stringFromStdString(deviceInfo.displayName)
                                                firmwareVersion:stringFromStdString(deviceInfo.firmwareVersion)
                                                 usbAPIVersion:stringFromStdString(deviceInfo.usbAPIVersion)
                                           sharedUSBDeviceCount:deviceInfo.sharedUSBDeviceCount];
}

static MHRadioStatusSnapshot *statusSnapshotFromStatus(const StatusSnapshot &status) {
    NSMutableArray<MHHackRFDeviceSnapshot *> *devices = [NSMutableArray arrayWithCapacity:status.devices.size()];
    for (const auto &deviceInfo : status.devices) {
        [devices addObject:deviceSnapshotFromInfo(deviceInfo)];
    }

    NSMutableArray<NSNumber *> *spectrumBins = [NSMutableArray arrayWithCapacity:status.spectrumBins.size()];
    for (const auto &value : status.spectrumBins) {
        [spectrumBins addObject:@(value)];
    }

    NSString *connectedSerial = status.connectedSerialNumber.has_value() ? stringFromStdString(*status.connectedSerialNumber) : nil;
    NSString *lastError = status.lastError.has_value() ? stringFromStdString(*status.lastError) : nil;

    return [[MHRadioStatusSnapshot alloc] initWithDevices:devices
                                           libraryVersion:stringFromStdString(status.libraryVersion)
                                         connectedSerialNumber:connectedSerial
                                        connectionSummary:stringFromStdString(status.connectionSummary)
                                                 lastError:lastError
                                            transportState:transportStateForSnapshot(status.transportState)
                                              spectrumBins:spectrumBins
                                                ampEnabled:status.ampEnabled
                                                   lnaGain:status.lnaGain
                                                   vgaGain:status.vgaGain
                                                 txVGAGain:status.txVGAGain
                                                sampleRate:status.sampleRate
                                          tunedFrequencyHz:status.tunedFrequencyHz];
}

@interface MHRadioEngineBridge ()

@property (nonatomic, assign) HackRFManager *manager;

@end

@implementation MHRadioEngineBridge {
    std::unique_ptr<HackRFManager> _storage;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _storage = std::make_unique<HackRFManager>();
        _manager = _storage.get();
    }
    return self;
}

- (MHRadioStatusSnapshot *)refreshStatus {
    return statusSnapshotFromStatus(self.manager->refreshStatus());
}

- (MHRadioStatusSnapshot *)currentStatus {
    return statusSnapshotFromStatus(self.manager->currentStatus());
}

- (MHRadioStatusSnapshot *)connectToSerialNumber:(NSString *)serialNumber {
    std::optional<std::string> selectedSerial;
    if (serialNumber.length > 0) {
        selectedSerial = std::string(serialNumber.UTF8String);
    }
    return statusSnapshotFromStatus(self.manager->connect(selectedSerial));
}

- (MHRadioStatusSnapshot *)disconnectDevice {
    return statusSnapshotFromStatus(self.manager->disconnect());
}

- (MHRadioStatusSnapshot *)startRX {
    return statusSnapshotFromStatus(self.manager->startRX());
}

- (MHRadioStatusSnapshot *)stopRX {
    return statusSnapshotFromStatus(self.manager->stopRX());
}

- (MHRadioStatusSnapshot *)applyFrequencyHz:(uint64_t)frequencyHz
                                 sampleRate:(double)sampleRate
                                 ampEnabled:(BOOL)ampEnabled
                                    lnaGain:(NSInteger)lnaGain
                                    vgaGain:(NSInteger)vgaGain
                                  txVGAGain:(NSInteger)txVGAGain {
    return statusSnapshotFromStatus(self.manager->applyTuning(
        frequencyHz,
        sampleRate,
        ampEnabled,
        static_cast<int>(lnaGain),
        static_cast<int>(vgaGain),
        static_cast<int>(txVGAGain)
    ));
}

@end
