import AudioToolbox
import Foundation

private final class FloatRingBuffer {
    private let capacity: Int
    private var storage: [Float]
    private var readIndex = 0
    private var writeIndex = 0
    private var count = 0
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
        self.storage = Array(repeating: 0, count: max(capacity, 1))
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        readIndex = 0
        writeIndex = 0
        count = 0
    }

    func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        for sample in samples {
            if count == capacity {
                readIndex = (readIndex + 1) % capacity
                count -= 1
            }

            storage[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
            count += 1
        }
    }

    func pop(into destination: UnsafeMutablePointer<Float>, count requestedCount: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let sampleCount = min(requestedCount, count)
        guard sampleCount > 0 else { return 0 }

        for index in 0..<sampleCount {
            destination[index] = storage[readIndex]
            readIndex = (readIndex + 1) % capacity
        }
        count -= sampleCount
        return sampleCount
    }
}

final class AudioOutputService {
    private static let outputSampleRate = 48_000.0
    private static let framesPerBuffer = 1_024
    private static let queueBufferCount = 4

    private let sampleProvider: (Int) -> [Float]
    private let ringBuffer = FloatRingBuffer(capacity: 48_000 * 4)
    private let stateLock = NSLock()
    private let feederQueue = DispatchQueue(label: "com.sam.MacinHoff.audio-feeder", qos: .userInitiated)

    private var queue: AudioQueueRef?
    private var queueBuffers: [AudioQueueBufferRef] = []
    private var feederTimer: DispatchSourceTimer?
    private var isRunning = false
    private var currentOutputName = "System Default"

    init(sampleProvider: @escaping (Int) -> [Float]) {
        self.sampleProvider = sampleProvider
    }

    deinit {
        stop()
    }

    func update(shouldPlay: Bool, outputDeviceName: String) {
        stateLock.lock()
        let needsRestart = currentOutputName != outputDeviceName
        currentOutputName = outputDeviceName
        let running = isRunning
        stateLock.unlock()

        if !shouldPlay {
            if running {
                stop()
            }
            return
        }

        if needsRestart, running {
            stop()
        }

        if !running || needsRestart {
            start()
        }
    }

    func stop() {
        feederTimer?.cancel()
        feederTimer = nil

        stateLock.lock()
        defer { stateLock.unlock() }

        ringBuffer.clear()
        queueBuffers.removeAll()

        if let queue {
            AudioQueueStop(queue, true)
            AudioQueueDispose(queue, true)
            self.queue = nil
        }
        isRunning = false
    }

    private func start() {
        stop()

        var format = AudioStreamBasicDescription(
            mSampleRate: Self.outputSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        var newQueue: AudioQueueRef?
        let result = AudioQueueNewOutput(
            &format,
            Self.audioQueueCallback,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            nil,
            nil,
            0,
            &newQueue
        )

        guard result == noErr, let newQueue else { return }

        applySelectedOutputDevice(to: newQueue)

        let bufferByteSize = UInt32(Self.framesPerBuffer * MemoryLayout<Float>.size)
        for _ in 0..<Self.queueBufferCount {
            var buffer: AudioQueueBufferRef?
            guard AudioQueueAllocateBuffer(newQueue, bufferByteSize, &buffer) == noErr, let buffer else {
                AudioQueueDispose(newQueue, true)
                return
            }
            queueBuffers.append(buffer)
            fillAndEnqueue(buffer, queue: newQueue)
        }

        AudioQueueStart(newQueue, nil)

        stateLock.lock()
        queue = newQueue
        isRunning = true
        stateLock.unlock()

        let timer = DispatchSource.makeTimerSource(queue: feederQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let samples = self.sampleProvider(4_096)
                if !samples.isEmpty {
                    self.ringBuffer.append(samples)
                }
            }
        }
        timer.resume()
        feederTimer = timer
    }

    private func fillAndEnqueue(_ buffer: AudioQueueBufferRef, queue: AudioQueueRef) {
        let requestedFrames = Self.framesPerBuffer
        let rawPointer = buffer.pointee.mAudioData.bindMemory(to: Float.self, capacity: requestedFrames)
        let populatedFrames = ringBuffer.pop(into: rawPointer, count: requestedFrames)

        if populatedFrames < requestedFrames {
            rawPointer.advanced(by: populatedFrames).initialize(repeating: 0, count: requestedFrames - populatedFrames)
        }

        buffer.pointee.mAudioDataByteSize = UInt32(requestedFrames * MemoryLayout<Float>.size)
        AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
    }

    private func applySelectedOutputDevice(to queue: AudioQueueRef) {
        guard let deviceUID = AudioDeviceService.outputDeviceUID(named: currentOutputName) else {
            return
        }

        let cfDeviceUID = deviceUID as CFString
        var deviceValue = cfDeviceUID
        AudioQueueSetProperty(
            queue,
            kAudioQueueProperty_CurrentDevice,
            &deviceValue,
            UInt32(MemoryLayout<CFString>.size)
        )
    }

    private static let audioQueueCallback: AudioQueueOutputCallback = { userData, queue, buffer in
        guard let userData else { return }
        let service = Unmanaged<AudioOutputService>.fromOpaque(userData).takeUnretainedValue()
        service.fillAndEnqueue(buffer, queue: queue)
    }
}
