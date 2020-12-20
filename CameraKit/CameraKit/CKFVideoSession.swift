//
//  This file is responsible for capturing depth and the movie frame output buffer. It is then passed to the Controller using the
//  delegate methods present in the VideoCaptureDelegate protocol.
//  Created by Avinash Parasurampuram on 09/17/2020.
//

import AVFoundation
import Vision

// This protocal acts like an interface that has the delegate methods to capture Video and Depth outputs.
public protocol VideoCaptureDelegate: class {
    func videoCapture(didCaptureVideoFrame: CVPixelBuffer?, timestamp: CMTime)
    
    func depthvideoCapture(distance: String)
}


public class VideoCaptureSession: CKFSession {

    var myDelegate: VideoCaptureDelegate? {
        get { return delegate as? VideoCaptureDelegate }
        set { delegate = newValue as? CKFSessionDelegate }
    }
}


@objc public class CKFVideoSession: VideoCaptureSession  {
    @objc public private(set) var isRecording = false
    private enum _CaptureState {
        case idle, start, capturing, end
    }
    private var _captureState = _CaptureState.idle
    private var _filename = ""
    private var _assetWriter: AVAssetWriter?
    private var _assetWriterInput: AVAssetWriterInput?
    private var _adpater: AVAssetWriterInputPixelBufferAdaptor?
    private var _time: Double = 0

    var lastTimestamp = CMTime()
    public var fps = 10

    @objc public var cameraPosition = CameraPosition.back {
        didSet {
            do {
                let deviceInput = try CKFSession.captureDeviceInput(type: self.cameraPosition.deviceType)
                self.captureDeviceInput = deviceInput
            } catch let error {
                print(error.localizedDescription)
            }
        }
    }

    var captureDeviceInput: AVCaptureDeviceInput? {
        didSet {
            if let oldValue = oldValue {
                self.session.removeInput(oldValue)
            }

            // Adding captureDeviceInput to the session
            if let captureDeviceInput = self.captureDeviceInput {
                self.session.addInput(captureDeviceInput)
            }
        }
    }

    let videoOutput = AVCaptureVideoDataOutput()
    let depthOutput = AVCaptureDepthDataOutput()
    let dataOutputQueue = DispatchQueue(label: "video data queue",
                                        qos: .userInitiated,
                                        attributes: [],
                                        autoreleaseFrequency: .workItem)

    @objc public init(position: CameraPosition = .back) {
        super.init()

        defer {
            self.cameraPosition = position
        }

        self.session.sessionPreset = .hd1920x1080

        let settings: [String : Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)]

        videoOutput.videoSettings = settings
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)

        // Adding videoOutput to the session
        if self.session.canAddOutput(videoOutput) {
            self.session.addOutput(videoOutput)
        }

        depthOutput.setDelegate(self, callbackQueue: dataOutputQueue)
        depthOutput.isFilteringEnabled = true

        if let depthConnection = depthOutput.connection(with: .depthData) {
            depthConnection.isEnabled = true
            depthConnection.videoOrientation = .portrait
        } else {
            print("No AVCaptureConnection")
        }

        // Adding depthOutput to the session
        if self.session.canAddOutput(depthOutput) {
            self.session.addOutput(depthOutput)
        }

    }

    var recordCallback: (URL) -> Void = { (_) in }
    var errorCallback: (Error) -> Void = { (_) in }


    @objc public func record(url: URL? = nil, _ callback: @escaping (URL) -> Void, error: @escaping (Error) -> Void) {
        if self.isRecording { return }

        self.recordCallback = callback
        self.errorCallback = error

        self.session.startRunning()
        _captureState = .start
        self.isRecording = true
    }

    @objc public func stopRecording() {
        if !self.isRecording { return }
        _captureState = .end
        self.isRecording = false
        guard _assetWriterInput?.isReadyForMoreMediaData == true, _assetWriter!.status != .failed else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("\(_filename).mov")
        _assetWriterInput?.markAsFinished()
        _assetWriter?.finishWriting { [weak self] in
            self?._captureState = .idle
            self?._assetWriter = nil
            self?._assetWriterInput = nil
        }
        defer {
            self.recordCallback = { (_) in }
            self.errorCallback = { (_) in }
        }
        self.recordCallback(url)
    }

}

extension CKFVideoSession: AVCaptureDepthDataOutputDelegate {

    // Callback for depth where the depthData is received
    public func depthDataOutput(_ output: AVCaptureDepthDataOutput,
                                didOutput depthData: AVDepthData,
                                timestamp: CMTime,
                                connection: AVCaptureConnection) {

        var convertedDepth: AVDepthData
        let depthDataType = kCVPixelFormatType_DepthFloat32
        if depthData.depthDataType != depthDataType {
            convertedDepth = depthData.converting(toDepthDataType: depthDataType)
        } else {
            convertedDepth = depthData
        }
        let pixelBuffer = convertedDepth.depthDataMap

        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

        // We take four pointers, calculate the distance from each point, average them out and take that distance as the depth
        let depthPointer1 = unsafeBitCast(CVPixelBufferGetBaseAddress(pixelBuffer), to: UnsafeMutablePointer<Float32>.self)
        let depthPointer2 = unsafeBitCast(CVPixelBufferGetBaseAddress(pixelBuffer), to: UnsafeMutablePointer<Float32>.self)
        let depthPointer3 = unsafeBitCast(CVPixelBufferGetBaseAddress(pixelBuffer), to: UnsafeMutablePointer<Float32>.self)
        let depthPointer4 = unsafeBitCast(CVPixelBufferGetBaseAddress(pixelBuffer), to: UnsafeMutablePointer<Float32>.self)

        var total_distance = 0.0
        var total_distance_temp = 0.0

        let videoDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back).devices.first
        let dimensions = CMVideoFormatDescriptionGetDimensions((videoDevice?.activeFormat.formatDescription)!)

        for i in 1...5
        {
            for j in 1...5
            {
                let temp1 = ( (CGFloat(dimensions.height) * CGFloat(0.5) ) + CGFloat(j))
                let temp2 = ( (CGFloat(dimensions.width) * CGFloat(0.5)) + CGFloat(i))
                var distanceXY1 = depthPointer1[Int(temp1+temp2)]
                if(distanceXY1<0.1)
                {
                    distanceXY1 = 0
                }

                let temp3 = ( (CGFloat(dimensions.height) * CGFloat(0.5) ) + CGFloat(j))
                let temp4 = ( (CGFloat(dimensions.width) * CGFloat(0.5)) - CGFloat(i))
                var distanceXY2 = depthPointer2[Int(temp3+temp4)]
                if(distanceXY2<0.1)
                {
                    distanceXY2 = 0
                }

                let temp5 = ( (CGFloat(dimensions.height) * CGFloat(0.5) ) - CGFloat(j))
                let temp6 = ( (CGFloat(dimensions.width) * CGFloat(0.5)) - CGFloat(i))
                var distanceXY3 = depthPointer3[Int(temp5+temp6)]
                if(distanceXY3<0.1)
                {
                    distanceXY3=0
                }

                let temp7 = ( (CGFloat(dimensions.height) * CGFloat(0.5) ) - CGFloat(j))
                let temp8 = ( (CGFloat(dimensions.width) * CGFloat(0.5)) + CGFloat(i))
                var distanceXY4 = depthPointer4[Int(temp7+temp8)]
                if(distanceXY4<0.1)
                {
                    distanceXY4 = 0
                }

                total_distance = total_distance + Double(distanceXY1) + Double(distanceXY2) + Double(distanceXY3) + Double(distanceXY4)

            }

            total_distance_temp = total_distance_temp + total_distance
            total_distance = 0.0
        }

        total_distance = total_distance_temp/100

        let distancevalue = String(format: "%.1f",total_distance)
        myDelegate?.depthvideoCapture( distance: distancevalue)

    }
}

// Simultaneous AVCaptureVideoDataOutput + AVCaptureMovieFileOutput use is not supported. So recording video and grabbing frames
// simultaneoulsy is not possible. So we use AVAssetWriter, AVAssetWriterInput and AVAssetWriterInputPixelBufferAdaptor to write
// frames out to an H.264 encoded movie file.
extension CKFVideoSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Because lowering the capture device's FPS looks ugly in the preview,
        // we capture at full speed but only call the delegate at its desired
        // framerate.
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let deltaTime = timestamp - lastTimestamp

        // AVAssetWriter Addition
        let timestamp_av = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        switch _captureState {
        case .start:
            // Set up recorder
            _filename = UUID().uuidString
            let videoPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("\(_filename).mov")
            let writer = try! AVAssetWriter(outputURL: videoPath, fileType: .mov)
            let settings = videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov)

            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            input.transform = CGAffineTransform(rotationAngle: .pi/2)
            let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
            if writer.canAdd(input) {
                writer.add(input)
            }
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
            _assetWriter = writer
            _assetWriterInput = input
            _adpater = adapter
            _captureState = .capturing
            _time = timestamp_av
        case .capturing:
            // Using AVAssetWriterInputPixelBufferAdaptor, we append the sampleBuffer received from the videop frame to this
            // adapter.
            if _assetWriterInput?.isReadyForMoreMediaData == true {
                let time = CMTime(seconds: timestamp_av - _time, preferredTimescale: CMTimeScale(600))
                _adpater?.append(CMSampleBufferGetImageBuffer(sampleBuffer)!, withPresentationTime: time)
            }
            break
        default:
            break
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // We dont call the delegate continuously, we allow some time and then call it.
            if deltaTime >= CMTimeMake(value: 1, timescale: Int32(self.fps)) {
                self.lastTimestamp = timestamp
                let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
                self.myDelegate?.videoCapture(didCaptureVideoFrame: imageBuffer, timestamp: timestamp)
            }
        }
    }

    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    }
}

