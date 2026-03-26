#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace macinhoff {

enum class TransportState {
    idle,
    receiving,
    transmitting,
    fault,
};

struct DeviceInfo {
    std::string serialNumber;
    std::string boardName;
    std::string displayName;
    std::string firmwareVersion;
    std::string usbAPIVersion;
    int sharedUSBDeviceCount = 0;
};

struct StatusSnapshot {
    std::vector<DeviceInfo> devices;
    std::string libraryVersion;
    std::optional<std::string> connectedSerialNumber;
    std::string connectionSummary;
    std::optional<std::string> lastError;
    TransportState transportState = TransportState::idle;
    std::vector<float> spectrumBins = std::vector<float>(128, 0.0f);
    bool ampEnabled = false;
    int lnaGain = 16;
    int vgaGain = 16;
    int txVGAGain = 0;
    double sampleRate = 10'000'000.0;
    std::uint64_t tunedFrequencyHz = 14'200'000;
    std::string demodMode = "USB";
    double rxFilterHz = 2'700.0;
    float rxRFLevel = 0.0f;
    float rxAudioLevel = 0.0f;
    float txRFLevel = 0.0f;
    float txAudioLevel = 0.0f;
};

class HackRFManager {
public:
    HackRFManager();
    ~HackRFManager();

    StatusSnapshot refreshStatus();
    StatusSnapshot currentStatus();
    StatusSnapshot connect(const std::optional<std::string>& serialNumber);
    StatusSnapshot disconnect();
    StatusSnapshot startRX();
    StatusSnapshot stopRX();
    StatusSnapshot applyTuning(std::uint64_t frequencyHz,
                               double sampleRate,
                               bool ampEnabled,
                               int lnaGain,
                               int vgaGain,
                               int txVGAGain,
                               const std::string& demodMode,
                               double rxFilterHz);
    std::vector<float> consumeRXAudio(std::size_t maxSamples);

private:
    struct Impl;
    Impl& impl();
    const Impl& impl() const;
    StatusSnapshot applyTuningLocked(std::uint64_t frequencyHz,
                                     double sampleRate,
                                     bool ampEnabled,
                                     int lnaGain,
                                     int vgaGain,
                                     int txVGAGain,
                                     const std::string& demodMode,
                                     double rxFilterHz,
                                     bool resumeRX);

    Impl* impl_ = nullptr;
};

} // namespace macinhoff
