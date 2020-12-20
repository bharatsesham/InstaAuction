//
//  This file initiates the AVCaptureSession and returns the camera device input. It is also responsible for start and stop of the session
//
//  Created by Avinash Parasurampuram on 09/03/2020.
//

import AVFoundation

public extension UIDeviceOrientation {

    var videoOrientation: AVCaptureVideoOrientation {
        switch UIDevice.current.orientation {
        case .portraitUpsideDown:
            return .portrait
        case .landscapeLeft:
            return .portrait
        case .landscapeRight:
            return .portrait
        default:
            return .portrait
        }
    }
}

private extension CKFSession.DeviceType {

    var captureDeviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .frontCamera, .backCamera:
            return .builtInWideAngleCamera
        case .microphone:
            return .builtInMicrophone
        }
    }

    var captureMediaType: AVMediaType {
        switch self {
        case .frontCamera, .backCamera:
            return .video
        case .microphone:
            return .audio
        }
    }

    var capturePosition: AVCaptureDevice.Position {
        switch self {
        case .frontCamera:
            return .front
        case .backCamera:
            return .back
        case .microphone:
            return .unspecified
        }
    }
}

extension CKFSession.CameraPosition {
    var deviceType: CKFSession.DeviceType {
        switch self {
        case .back:
            return .backCamera
        case .front:
            return .frontCamera
        }
    }
}

@objc public protocol CKFSessionDelegate: class {
    @objc func didChangeValue(session: CKFSession, value: Any, key: String)
}

@objc public class CKFSession: NSObject {

    @objc public enum DeviceType: UInt {
        case frontCamera, backCamera, microphone
    }

    @objc public enum CameraPosition: UInt {
        case front, back
    }

    @objc public let session: AVCaptureSession

    @objc public var previewLayer: AVCaptureVideoPreviewLayer?
    @objc public var overlayView: UIView?
    
    @objc public var zoom = 1.0

    @objc public weak var delegate: CKFSessionDelegate?

    @objc override init() {
        self.session = AVCaptureSession()
    }

    @objc deinit {
        self.session.stopRunning()
    }

    @objc public func start() {
        self.session.startRunning()
    }

    @objc public func stop() {
        self.session.stopRunning()
    }

    //Captures the AVCaptureDeviceInput of the camera. In this case - BuiltInDualCamera
    @objc public static func captureDeviceInput(type: DeviceType) throws -> AVCaptureDeviceInput {

        guard let captureDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) else {
          fatalError("No depth video camera available")
        }

        let cameraInput = try AVCaptureDeviceInput(device: captureDevice)

        return cameraInput
    }
    
}
