#include "HackRFManager.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <cstring>
#include <deque>
#include <memory>
#include <mutex>
#include <sstream>
#include <stdexcept>

#include <libhackrf/hackrf.h>

namespace macinhoff {

namespace {

std::string safeCString(const char* value) {
    return value != nullptr ? std::string(value) : std::string();
}

enum class DemodMode {
    usb,
    lsb,
    cw,
    am,
    nfm,
};

DemodMode demodModeFromString(const std::string& modeName) {
    if (modeName == "LSB") {
        return DemodMode::lsb;
    }
    if (modeName == "CW") {
        return DemodMode::cw;
    }
    if (modeName == "AM") {
        return DemodMode::am;
    }
    if (modeName == "NFM") {
        return DemodMode::nfm;
    }
    return DemodMode::usb;
}

std::string formatUSBAPIVersion(uint16_t version) {
    std::ostringstream stream;
    stream << ((version >> 8) & 0xFF) << "." << ((version)&0xFF);
    return stream.str();
}

int clampGain(int value, int minimum, int maximum, int step) {
    value = std::clamp(value, minimum, maximum);
    const int offset = value - minimum;
    return minimum + ((offset / step) * step);
}

void expectSuccess(int result, const char* operation) {
    if (result == HACKRF_SUCCESS) {
        return;
    }

    std::ostringstream stream;
    stream << operation << " failed: " << safeCString(hackrf_error_name(static_cast<hackrf_error>(result))) << " (" << result << ")";
    throw std::runtime_error(stream.str());
}

} // namespace

struct HackRFManager::Impl {
    static constexpr std::size_t kSpectrumBinCount = 128;
    static constexpr std::size_t kFFTSize = 256;
    static constexpr double kAudioRate = 48'000.0;
    static constexpr std::size_t kMaxBufferedAudioSamples = 48'000 * 4;

    std::mutex mutex;
    hackrf_device* device = nullptr;
    bool libraryInitialized = false;
    StatusSnapshot status;
    std::array<float, kFFTSize> hannWindow{};
    std::deque<float> audioSamples;
    std::complex<float> previousIQ{0.0f, 0.0f};
    float amDCLevel = 0.0f;
    float audioFilterState = 0.0f;
    double cwBFOPhase = 0.0;
    double resampleAccumulator = 0.0;

    Impl() {
        const int result = hackrf_init();
        if (result == HACKRF_SUCCESS) {
            libraryInitialized = true;
        } else {
            status.lastError = "hackrf_init failed";
            status.transportState = TransportState::fault;
        }

        status.libraryVersion = safeCString(hackrf_library_version());
        status.connectionSummary = "No HackRF connected";

        for (std::size_t index = 0; index < hannWindow.size(); ++index) {
            const float ratio = static_cast<float>(index) / static_cast<float>(hannWindow.size() - 1);
            hannWindow[index] = 0.5f * (1.0f - std::cos(2.0f * static_cast<float>(M_PI) * ratio));
        }
    }

    ~Impl() {
        if (device != nullptr && hackrf_is_streaming(device) == HACKRF_TRUE) {
            hackrf_stop_rx(device);
        }
        closeDevice();
        if (libraryInitialized) {
            hackrf_exit();
        }
    }

    void resetDSPState() {
        audioSamples.clear();
        previousIQ = std::complex<float>(0.0f, 0.0f);
        amDCLevel = 0.0f;
        audioFilterState = 0.0f;
        cwBFOPhase = 0.0;
        resampleAccumulator = 0.0;
        status.rxRFLevel = 0.0f;
        status.rxAudioLevel = 0.0f;
        status.txRFLevel = 0.0f;
        status.txAudioLevel = 0.0f;
    }

    void closeDevice() {
        if (device != nullptr) {
            hackrf_close(device);
            device = nullptr;
        }
        status.connectedSerialNumber.reset();
        status.transportState = TransportState::idle;
        status.connectionSummary = "No HackRF connected";
        std::fill(status.spectrumBins.begin(), status.spectrumBins.end(), 0.0f);
        resetDSPState();
    }

    DeviceInfo readDeviceInfo(hackrf_device_list_t* list, int index) {
        DeviceInfo info;
        info.serialNumber = safeCString(list->serial_numbers[index]);
        info.displayName = info.serialNumber.empty() ? "HackRF" : "HackRF " + info.serialNumber.substr(std::max<int>(0, static_cast<int>(info.serialNumber.size()) - 4));

        const auto boardID = list->usb_board_ids[index];
        info.boardName = safeCString(hackrf_usb_board_id_name(boardID));
        info.sharedUSBDeviceCount = std::max(0, hackrf_device_list_bus_sharing(list, index));

        hackrf_device* tempDevice = nullptr;
        if (hackrf_device_list_open(list, index, &tempDevice) == HACKRF_SUCCESS) {
            std::array<char, 256> version{};
            uint16_t usbAPIVersion = 0;

            if (hackrf_version_string_read(tempDevice, version.data(), version.size() - 1) == HACKRF_SUCCESS) {
                info.firmwareVersion = version.data();
            }

            if (hackrf_usb_api_version_read(tempDevice, &usbAPIVersion) == HACKRF_SUCCESS) {
                info.usbAPIVersion = formatUSBAPIVersion(usbAPIVersion);
            }

            hackrf_close(tempDevice);
        }

        if (info.boardName.empty()) {
            info.boardName = "HackRF";
        }
        if (info.firmwareVersion.empty()) {
            info.firmwareVersion = "Unknown";
        }
        if (info.usbAPIVersion.empty()) {
            info.usbAPIVersion = "Unknown";
        }

        return info;
    }

    void enumerateDevices() {
        status.devices.clear();

        if (!libraryInitialized) {
            return;
        }

        hackrf_device_list_t* list = hackrf_device_list();
        if (list == nullptr) {
            status.lastError = "Unable to enumerate HackRF devices";
            status.transportState = TransportState::fault;
            return;
        }

        for (int index = 0; index < list->devicecount; ++index) {
            status.devices.push_back(readDeviceInfo(list, index));
        }

        hackrf_device_list_free(list);

        if (!status.connectedSerialNumber.has_value()) {
            status.connectionSummary = status.devices.empty() ? "No HackRF detected" : "HackRF available";
            status.transportState = TransportState::idle;
        }
    }

    std::optional<DeviceInfo> findDevice(const std::optional<std::string>& serialNumber) const {
        if (status.devices.empty()) {
            return std::nullopt;
        }

        if (!serialNumber.has_value() || serialNumber->empty()) {
            return status.devices.front();
        }

        for (const auto& deviceInfo : status.devices) {
            if (deviceInfo.serialNumber == *serialNumber) {
                return deviceInfo;
            }
        }

        return std::nullopt;
    }

    bool isStreaming() const {
        if (device == nullptr) {
            return false;
        }
        return hackrf_is_streaming(device) == HACKRF_TRUE;
    }

    static int rxCallback(hackrf_transfer* transfer) {
        if (transfer == nullptr || transfer->rx_ctx == nullptr) {
            return -1;
        }
        return static_cast<Impl*>(transfer->rx_ctx)->handleRXTransfer(*transfer);
    }

    float demodulatedAudio(const std::complex<float>& iq) {
        switch (demodModeFromString(status.demodMode)) {
            case DemodMode::am: {
                const float magnitude = std::abs(iq);
                const float dcAlpha = std::clamp(
                    static_cast<float>((2.0 * M_PI * 20.0) / std::max(status.sampleRate, 1.0)),
                    0.000001f,
                    0.05f
                );
                amDCLevel += dcAlpha * (magnitude - amDCLevel);
                return (magnitude - amDCLevel) * 8.0f;
            }
            case DemodMode::nfm: {
                float sample = 0.0f;
                if (std::norm(previousIQ) > 0.0f) {
                    const auto delta = std::conj(previousIQ) * iq;
                    sample = std::atan2(delta.imag(), delta.real()) * 2.8f;
                }
                previousIQ = iq;
                return sample;
            }
            case DemodMode::cw: {
                const float bfoHz = 700.0f;
                const std::complex<float> oscillator(
                    std::cos(static_cast<float>(cwBFOPhase)),
                    std::sin(static_cast<float>(cwBFOPhase))
                );
                cwBFOPhase += (2.0 * M_PI * bfoHz) / std::max(status.sampleRate, 1.0);
                if (cwBFOPhase > 2.0 * M_PI) {
                    cwBFOPhase -= 2.0 * M_PI;
                }
                return (iq * oscillator).real() * 3.0f;
            }
            case DemodMode::lsb:
                return (iq.real() + iq.imag()) * 1.7f;
            case DemodMode::usb:
                return (iq.real() - iq.imag()) * 1.7f;
        }
    }

    int handleRXTransfer(const hackrf_transfer& transfer) {
        const std::size_t sampleCount = static_cast<std::size_t>(transfer.valid_length) / 2;
        const std::size_t spectrumSampleCount = std::min<std::size_t>(sampleCount, kFFTSize);
        if (spectrumSampleCount < kFFTSize / 2) {
            return 0;
        }

        std::array<std::complex<float>, kFFTSize> samples{};
        for (std::size_t index = 0; index < spectrumSampleCount; ++index) {
            const float i = static_cast<float>(transfer.buffer[index * 2]) / 128.0f;
            const float q = static_cast<float>(transfer.buffer[index * 2 + 1]) / 128.0f;
            samples[index] = std::complex<float>(i * hannWindow[index], q * hannWindow[index]);
        }

        std::vector<float> bins(kSpectrumBinCount, 0.0f);
        for (std::size_t bin = 0; bin < kSpectrumBinCount; ++bin) {
            std::complex<float> accumulator(0.0f, 0.0f);
            for (std::size_t sampleIndex = 0; sampleIndex < kFFTSize; ++sampleIndex) {
                const float angle = -2.0f * static_cast<float>(M_PI) * static_cast<float>(bin) * static_cast<float>(sampleIndex) / static_cast<float>(kFFTSize);
                accumulator += samples[sampleIndex] * std::complex<float>(std::cos(angle), std::sin(angle));
            }

            const float magnitude = std::abs(accumulator);
            const float decibels = 20.0f * std::log10(magnitude + 1e-6f);
            bins[bin] = std::clamp((decibels + 70.0f) / 70.0f, 0.0f, 1.0f);
        }

        const float filterHz = static_cast<float>(std::clamp(status.rxFilterHz, 300.0, 12'000.0));
        const float filterAlpha = std::clamp(
            static_cast<float>(1.0 - std::exp((-2.0 * M_PI * filterHz) / std::max(status.sampleRate, 1.0))),
            0.000001f,
            1.0f
        );

        std::vector<float> demodulatedChunk;
        demodulatedChunk.reserve(static_cast<std::size_t>((sampleCount * kAudioRate) / std::max(status.sampleRate, 1.0)) + 8);

        double rfPowerSum = 0.0;
        double audioPowerSum = 0.0;
        std::size_t audioSampleCount = 0;
        const bool isCW = demodModeFromString(status.demodMode) == DemodMode::cw;

        for (std::size_t index = 0; index < sampleCount; ++index) {
            const auto iq = std::complex<float>(
                static_cast<float>(transfer.buffer[index * 2]) / 128.0f,
                static_cast<float>(transfer.buffer[index * 2 + 1]) / 128.0f
            );
            rfPowerSum += std::norm(iq);

            const float demodulated = demodulatedAudio(iq);
            audioFilterState += (isCW ? std::max(filterAlpha, 0.02f) : filterAlpha) * (demodulated - audioFilterState);

            resampleAccumulator += kAudioRate;
            if (resampleAccumulator >= status.sampleRate) {
                resampleAccumulator -= status.sampleRate;
                const float audioSample = std::clamp(audioFilterState, -1.0f, 1.0f);
                demodulatedChunk.push_back(audioSample);
                audioPowerSum += static_cast<double>(audioSample) * static_cast<double>(audioSample);
                audioSampleCount += 1;
            }
        }

        std::lock_guard lock(mutex);
        status.spectrumBins = std::move(bins);
        status.transportState = TransportState::receiving;
        status.connectionSummary = "Receiving on " + status.connectedSerialNumber.value_or("HackRF");
        status.rxRFLevel = std::clamp(std::sqrt(rfPowerSum / std::max<std::size_t>(sampleCount, 1)) * 0.9, 0.0, 1.0);
        status.rxAudioLevel = audioSampleCount > 0
            ? std::clamp(std::sqrt(audioPowerSum / static_cast<double>(audioSampleCount)) * 2.6, 0.0, 1.0)
            : 0.0f;

        for (const float sample : demodulatedChunk) {
            audioSamples.push_back(sample);
        }
        while (audioSamples.size() > kMaxBufferedAudioSamples) {
            audioSamples.pop_front();
        }
        return 0;
    }
};

HackRFManager::HackRFManager()
    : impl_(new Impl()) {}

HackRFManager::~HackRFManager() {
    delete impl_;
}

HackRFManager::Impl& HackRFManager::impl() {
    return *impl_;
}

const HackRFManager::Impl& HackRFManager::impl() const {
    return *impl_;
}

StatusSnapshot HackRFManager::refreshStatus() {
    auto& state = impl();
    std::lock_guard lock(state.mutex);
    state.enumerateDevices();
    state.status.libraryVersion = safeCString(hackrf_library_version());
    return state.status;
}

StatusSnapshot HackRFManager::currentStatus() {
    auto& state = impl();
    std::lock_guard lock(state.mutex);
    state.status.libraryVersion = safeCString(hackrf_library_version());
    if (state.device != nullptr && state.status.transportState == TransportState::receiving && !state.isStreaming()) {
        state.status.transportState = TransportState::idle;
        state.status.connectionSummary = "HackRF RX stopped";
    }
    return state.status;
}

StatusSnapshot HackRFManager::connect(const std::optional<std::string>& serialNumber) {
    auto& state = impl();
    std::lock_guard lock(state.mutex);
    state.enumerateDevices();
    state.status.lastError.reset();

    if (!state.libraryInitialized) {
        state.status.transportState = TransportState::fault;
        state.status.lastError = "libhackrf initialization failed";
        return state.status;
    }

    if (state.device != nullptr) {
        hackrf_close(state.device);
        state.device = nullptr;
    }

    const auto targetDevice = state.findDevice(serialNumber);
    if (!targetDevice.has_value()) {
        state.status.connectionSummary = "No matching HackRF found";
        state.status.transportState = TransportState::fault;
        state.status.lastError = "No matching HackRF found";
        return state.status;
    }

    hackrf_device* openedDevice = nullptr;
    const int result = hackrf_open_by_serial(targetDevice->serialNumber.c_str(), &openedDevice);
    if (result != HACKRF_SUCCESS) {
        state.status.connectionSummary = "HackRF connection failed";
        state.status.transportState = TransportState::fault;
        state.status.lastError = safeCString(hackrf_error_name(static_cast<hackrf_error>(result)));
        return state.status;
    }

    state.device = openedDevice;
    state.status.connectedSerialNumber = targetDevice->serialNumber;
    state.status.connectionSummary = "Connected to " + targetDevice->displayName;
    state.status.transportState = TransportState::idle;

    return applyTuningLocked(state.status.tunedFrequencyHz,
                             state.status.sampleRate,
                             state.status.ampEnabled,
                             state.status.lnaGain,
                             state.status.vgaGain,
                             state.status.txVGAGain,
                             state.status.demodMode,
                             state.status.rxFilterHz,
                             false);
}

StatusSnapshot HackRFManager::disconnect() {
    auto& state = impl();
    hackrf_device* device = nullptr;
    bool wasStreaming = false;

    {
        std::lock_guard lock(state.mutex);
        state.status.lastError.reset();
        device = state.device;
        wasStreaming = state.isStreaming();
    }

    if (device != nullptr && wasStreaming) {
        try {
            expectSuccess(hackrf_stop_rx(device), "hackrf_stop_rx");
        } catch (const std::exception& exception) {
            std::lock_guard lock(state.mutex);
            state.status.transportState = TransportState::fault;
            state.status.lastError = exception.what();
            state.status.connectionSummary = "HackRF RX stop failed";
            return state.status;
        }
    }

    std::lock_guard lock(state.mutex);
    state.closeDevice();
    state.enumerateDevices();
    return state.status;
}

StatusSnapshot HackRFManager::startRX() {
    auto& state = impl();
    std::lock_guard lock(state.mutex);

    if (state.device == nullptr) {
        state.status.transportState = TransportState::fault;
        state.status.lastError = "Connect a HackRF before starting RX";
        state.status.connectionSummary = "HackRF RX unavailable";
        return state.status;
    }

    if (state.isStreaming()) {
        state.status.transportState = TransportState::receiving;
        return state.status;
    }

    state.status.lastError.reset();
    try {
        expectSuccess(hackrf_start_rx(state.device, &Impl::rxCallback, &state), "hackrf_start_rx");
        state.status.transportState = TransportState::receiving;
        state.status.connectionSummary = "Receiving on " + state.status.connectedSerialNumber.value_or("HackRF");
    } catch (const std::exception& exception) {
        state.status.transportState = TransportState::fault;
        state.status.lastError = exception.what();
        state.status.connectionSummary = "HackRF RX failed";
    }

    return state.status;
}

StatusSnapshot HackRFManager::stopRX() {
    auto& state = impl();
    hackrf_device* device = nullptr;
    bool wasStreaming = false;

    {
        std::lock_guard lock(state.mutex);
        if (state.device == nullptr) {
            state.status.transportState = TransportState::idle;
            return state.status;
        }

        device = state.device;
        wasStreaming = state.isStreaming();
    }

    if (device != nullptr && wasStreaming) {
        try {
            expectSuccess(hackrf_stop_rx(device), "hackrf_stop_rx");
        } catch (const std::exception& exception) {
            std::lock_guard lock(state.mutex);
            state.status.transportState = TransportState::fault;
            state.status.lastError = exception.what();
            state.status.connectionSummary = "HackRF RX stop failed";
            return state.status;
        }
    }

    std::lock_guard lock(state.mutex);
    state.status.transportState = TransportState::idle;
    state.status.connectionSummary = "Connected to " + state.status.connectedSerialNumber.value_or("HackRF");
    std::fill(state.status.spectrumBins.begin(), state.status.spectrumBins.end(), 0.0f);
    state.resetDSPState();
    return state.status;
}

StatusSnapshot HackRFManager::applyTuning(std::uint64_t frequencyHz,
                                          double sampleRate,
                                          bool ampEnabled,
                                          int lnaGain,
                                          int vgaGain,
                                          int txVGAGain,
                                          const std::string& demodMode,
                                          double rxFilterHz) {
    auto& state = impl();
    hackrf_device* device = nullptr;
    bool resumeRX = false;

    {
        std::lock_guard lock(state.mutex);
        device = state.device;
        resumeRX = state.isStreaming();
    }

    if (device != nullptr && resumeRX) {
        try {
            expectSuccess(hackrf_stop_rx(device), "hackrf_stop_rx");
        } catch (const std::exception& exception) {
            std::lock_guard lock(state.mutex);
            state.status.transportState = TransportState::fault;
            state.status.lastError = exception.what();
            state.status.connectionSummary = "HackRF reconfiguration fault";
            return state.status;
        }
    }

    std::lock_guard lock(state.mutex);
    return applyTuningLocked(frequencyHz, sampleRate, ampEnabled, lnaGain, vgaGain, txVGAGain, demodMode, rxFilterHz, resumeRX);
}

StatusSnapshot HackRFManager::applyTuningLocked(std::uint64_t frequencyHz,
                                                double sampleRate,
                                                bool ampEnabled,
                                                int lnaGain,
                                                int vgaGain,
                                                int txVGAGain,
                                                const std::string& demodMode,
                                                double rxFilterHz,
                                                bool resumeRX) {
    auto& state = impl();

    state.status.tunedFrequencyHz = frequencyHz;
    state.status.sampleRate = sampleRate;
    state.status.ampEnabled = ampEnabled;
    state.status.lnaGain = clampGain(lnaGain, 0, 40, 8);
    state.status.vgaGain = clampGain(vgaGain, 0, 62, 2);
    state.status.txVGAGain = clampGain(txVGAGain, 0, 47, 1);
    state.status.demodMode = demodMode;
    state.status.rxFilterHz = std::clamp(rxFilterHz, 300.0, 12'000.0);

    if (state.device == nullptr) {
        state.enumerateDevices();
        state.status.connectionSummary = state.status.devices.empty() ? "No HackRF detected" : "HackRF available, not connected";
        state.status.transportState = TransportState::idle;
        return state.status;
    }

    state.status.lastError.reset();

    try {
        expectSuccess(hackrf_set_sample_rate(state.device, sampleRate), "hackrf_set_sample_rate");
        const uint32_t baseband = hackrf_compute_baseband_filter_bw(static_cast<uint32_t>(sampleRate * 0.75));
        expectSuccess(hackrf_set_baseband_filter_bandwidth(state.device, baseband), "hackrf_set_baseband_filter_bandwidth");
        expectSuccess(hackrf_set_freq(state.device, frequencyHz), "hackrf_set_freq");
        expectSuccess(hackrf_set_amp_enable(state.device, ampEnabled ? 1 : 0), "hackrf_set_amp_enable");
        expectSuccess(hackrf_set_lna_gain(state.device, state.status.lnaGain), "hackrf_set_lna_gain");
        expectSuccess(hackrf_set_vga_gain(state.device, state.status.vgaGain), "hackrf_set_vga_gain");
        expectSuccess(hackrf_set_txvga_gain(state.device, state.status.txVGAGain), "hackrf_set_txvga_gain");
        state.resetDSPState();

        if (resumeRX) {
            expectSuccess(hackrf_start_rx(state.device, &Impl::rxCallback, &state), "hackrf_start_rx");
            state.status.connectionSummary = "Receiving on " + state.status.connectedSerialNumber.value_or("HackRF");
            state.status.transportState = TransportState::receiving;
        } else {
            state.status.connectionSummary = "Configured " + state.status.connectedSerialNumber.value_or("HackRF");
            state.status.transportState = TransportState::idle;
        }
    } catch (const std::exception& exception) {
        state.status.transportState = TransportState::fault;
        state.status.lastError = exception.what();
        state.status.connectionSummary = "HackRF configuration fault";
    }

    if (!state.isStreaming()) {
        state.enumerateDevices();
    }
    return state.status;
}

std::vector<float> HackRFManager::consumeRXAudio(std::size_t maxSamples) {
    auto& state = impl();
    std::lock_guard lock(state.mutex);

    const std::size_t sampleCount = std::min(maxSamples, state.audioSamples.size());
    std::vector<float> samples;
    samples.reserve(sampleCount);

    for (std::size_t index = 0; index < sampleCount; ++index) {
        samples.push_back(state.audioSamples.front());
        state.audioSamples.pop_front();
    }

    return samples;
}

} // namespace macinhoff
