//
//  CKVideoSession.swift
//  CameraKit
//
//  Created by Adrian Mateoaea on 09/01/2019.
//  Copyright © 2019 Wonderkiln. All rights reserved.
//

import AVFoundation
import Vision


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


extension CKFSession.FlashMode {
    var captureTorchMode: AVCaptureDevice.TorchMode {
        switch self {
        case .off: return .off
        case .on: return .on
        case .auto: return .auto
        }
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
            
            if let captureDeviceInput = self.captureDeviceInput {
                self.session.addInput(captureDeviceInput)
            }
        }
    }
    
    @objc public override var zoom: Double {
        didSet {
            guard let device = self.captureDeviceInput?.device else {
                return
            }
            
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = CGFloat(self.zoom)
                device.unlockForConfiguration()
            } catch {
                //
            }
            
            if let delegate = self.delegate {
                delegate.didChangeValue(session: self, value: self.zoom, key: "zoom")
            }
        }
    }
    
    @objc public var flashMode = CKFSession.FlashMode.off {
        didSet {
            guard let device = self.captureDeviceInput?.device else {
                return
            }
            
            do {
                try device.lockForConfiguration()
                if device.isTorchModeSupported(self.flashMode.captureTorchMode) {
                    device.torchMode = self.flashMode.captureTorchMode
                }
                device.unlockForConfiguration()
            } catch {
                //
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
            
            do {
                //let microphoneInput = try CKFSession.captureDeviceInput(type: .microphone)
                //self.session.addInput(microphoneInput)
            } catch let error {
                print(error.localizedDescription)
            }
        }
        
        self.session.sessionPreset = .hd1920x1080
        
        let settings: [String : Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)]
        
        //let dataOutputQueue = DispatchQueue(label: "net.machinethink.camera-queue")
        
        videoOutput.videoSettings = settings
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
        if self.session.canAddOutput(videoOutput) {
            self.session.addOutput(videoOutput)
        }
        
        depthOutput.setDelegate(self, callbackQueue: dataOutputQueue)
        depthOutput.isFilteringEnabled = true
        
        if let depthConnection = depthOutput.connection(with: .depthData) {
            depthConnection.isEnabled = true
            depthConnection.videoOrientation = .portrait
            //depthConnection.videoOrientation = .portrait
        } else {
            
            print("No AVCaptureConnection")
        }
        
        
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
        //        self.session.stopRunning()
        defer {
            self.recordCallback = { (_) in }
            self.errorCallback = { (_) in }
        }
        self.recordCallback(url)

    }
    
    @objc public func togglePosition() {
        self.cameraPosition = self.cameraPosition == .back ? .front : .back
    }
    
    @objc public func setWidth(_ width: Int, height: Int, frameRate: Int) {
        guard
            let input = self.captureDeviceInput,
            let format = CKFSession.deviceInputFormat(input: input, width: width, height: height, frameRate: frameRate)
        else {
            return
        }
        
        do {
            try input.device.lockForConfiguration()
            input.device.activeFormat = format
            input.device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            input.device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            input.device.unlockForConfiguration()
        } catch {
        }
    }
    
    //    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    //      // Because lowering the capture device's FPS looks ugly in the preview,
    //      // we capture at full speed but only call the delegate at its desired
    //      // framerate.
    //      print(90000)
    //      let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    //      let deltaTime = timestamp - lastTimestamp
    //      if deltaTime >= CMTimeMake(value: 1, timescale: Int32(fps)) {
    //        lastTimestamp = timestamp
    //        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    //        myDelegate?.videoCapture(didCaptureVideoFrame: imageBuffer, timestamp: timestamp)
    //
    //        // AVAssetWriter Addition
    //        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
    //                switch _captureState {
    //                case .start:
    //                    // Set up recorder
    //                    _filename = UUID().uuidString
    //                    let videoPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("\(_filename).mov")
    //                    let writer = try! AVAssetWriter(outputURL: videoPath, fileType: .mov)
    //                    let settings = videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov)
    //                    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings) // [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1920, AVVideoHeightKey: 1080])
    ////                    let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
    //
    //                    input.mediaTimeScale = CMTimeScale(bitPattern: 600)
    //                    input.expectsMediaDataInRealTime = true
    //                    input.transform = CGAffineTransform(rotationAngle: .pi/2)
    //                    let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
    //                    if writer.canAdd(input) {
    //                        writer.add(input)
    //                    }
    //                    writer.startWriting()
    //                    writer.startSession(atSourceTime: .zero)
    //                    _assetWriter = writer
    //                    _assetWriterInput = input
    //                    _adpater = adapter
    //                    _captureState = .capturing
    //                    _time = timestamp
    //                case .capturing:
    //                    if _assetWriterInput?.isReadyForMoreMediaData == true {
    //                        let time = CMTime(seconds: timestamp - _time, preferredTimescale: CMTimeScale(600))
    //                        _adpater?.append(CMSampleBufferGetImageBuffer(sampleBuffer)!, withPresentationTime: time)
    //                    }
    //                    break
    //                default:
    //                    break
    //                }
    //      }
    //    }
    //
    //    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    //      //print("dropped frame")
    //    }
    
    //    public func depthDataOutput(_ output: AVCaptureDepthDataOutput,
    //                         didOutput depthData: AVDepthData,
    //                         timestamp: CMTime,
    //                         connection: AVCaptureConnection) {
    //
    //      var convertedDepth: AVDepthData
    //      print(499999)
    //      let depthDataType = kCVPixelFormatType_DepthFloat32
    //      if depthData.depthDataType != depthDataType {
    //        convertedDepth = depthData.converting(toDepthDataType: depthDataType)
    //      } else {
    //        convertedDepth = depthData
    //      }
    //      let pixelBuffer = convertedDepth.depthDataMap
    //
    //      //pixelBuffer.clamp()
    //
    //      //print(pixelBuffer)
    //      let depthMap = CIImage(cvPixelBuffer: pixelBuffer)
    //
    //      CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
    //
    //      let depthPointer = unsafeBitCast(CVPixelBufferGetBaseAddress(pixelBuffer), to: UnsafeMutablePointer<Float32>.self)
    //
    //      let point = CGPoint(x: 120, y: 160)
    //      let width = CVPixelBufferGetWidth(pixelBuffer)
    //      let distanceAtXYPoint = depthPointer[Int(point.y * CGFloat(width) + point.x)]
    //
    //      print(distanceAtXYPoint)
    //
    //      let distancevalue = String(format: "%.2f",distanceAtXYPoint)
    //      print(distancevalue)
    //        //myDelegate?.depthvideoCapture(distance: distanceAtXYPoint)
    //
    //      }
    
}

// KT
extension CKFVideoSession: AVCaptureDepthDataOutputDelegate {
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
        
        //pixelBuffer.clamp()
        
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        let depthPointer = unsafeBitCast(CVPixelBufferGetBaseAddress(pixelBuffer), to: UnsafeMutablePointer<Float32>.self)
        let depthPointer2 = unsafeBitCast(CVPixelBufferGetBaseAddress(pixelBuffer), to: UnsafeMutablePointer<Float32>.self)
        let depthPointer3 = unsafeBitCast(CVPixelBufferGetBaseAddress(pixelBuffer), to: UnsafeMutablePointer<Float32>.self)
        let depthPointer4 = unsafeBitCast(CVPixelBufferGetBaseAddress(pixelBuffer), to: UnsafeMutablePointer<Float32>.self)
        
        //let point = CGPoint(x: 120, y: 160)
        //let width = CVPixelBufferGetWidth(pixelBuffer)
        //let distanceAtXYPoint = depthPointer[Int(point.y * CGFloat(width) + point.x)]
        var total_distance = 0.0
        var total_distance_temp = 0.0
        //let frameSize = CGPoint(x: UIScreen.main.bounds.size.width*0.5,y: UIScreen.main.bounds.size.height*0.5)
        let videoDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back).devices.first
        let dimensions = CMVideoFormatDescriptionGetDimensions((videoDevice?.activeFormat.formatDescription)!)
        
        for i in 1...5
        {
            for j in 1...5
            {
                let temp = ( (CGFloat(dimensions.height) * CGFloat(0.5) ) + CGFloat(j))
                let temp2 = ( (CGFloat(dimensions.width) * CGFloat(0.5)) + CGFloat(i))
                var distanceXY = depthPointer[Int(temp+temp2)]
                //print(distanceXY)
                if(distanceXY<0.1)
                {
                    distanceXY = 0
                }
                let temp3 = ( (CGFloat(dimensions.height) * CGFloat(0.5) ) + CGFloat(j))
                let temp4 = ( (CGFloat(dimensions.width) * CGFloat(0.5)) - CGFloat(i))
                var distanceXY2 = depthPointer2[Int(temp3+temp4)]
                //print(distanceXY2)
                if(distanceXY2<0.1)
                {
                    distanceXY2 = 0
                }
                
                let temp5 = ( (CGFloat(dimensions.height) * CGFloat(0.5) ) - CGFloat(j))
                let temp6 = ( (CGFloat(dimensions.width) * CGFloat(0.5)) - CGFloat(i))
                var distanceXY3 = depthPointer3[Int(temp5+temp6)]
                //print(distanceXY3)
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
                
                
                total_distance = total_distance+Double(distanceXY) + Double(distanceXY2) + Double(distanceXY3) + Double(distanceXY4)
                //total_distance = total_distance + Double(distanceXY)
                
            }
            
            total_distance_temp = total_distance_temp + total_distance
            total_distance = 0.0
        }
        
        total_distance = total_distance_temp/100
        
        let distancevalue = String(format: "%.1f",total_distance)
        myDelegate?.depthvideoCapture( distance: distancevalue)
        
    }
}


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
            if _assetWriterInput?.isReadyForMoreMediaData == true {
                let time = CMTime(seconds: timestamp_av - _time, preferredTimescale: CMTimeScale(600))
                _adpater?.append(CMSampleBufferGetImageBuffer(sampleBuffer)!, withPresentationTime: time)
            }
            break
        default:
            break
        }
        DispatchQueue.global(qos: .userInitiated).async {
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
