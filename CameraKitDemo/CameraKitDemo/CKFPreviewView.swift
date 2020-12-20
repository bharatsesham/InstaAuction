//
//  CameraKit
//
//  Created by Avinash Parasurampuram on 08/23/2020.
//  Copyright © 2020 Avinash. All rights reserved.
//

import UIKit
import AVFoundation
import Vision

@objc open class CKFPreviewView: UIView {
    
    private var lastScale: CGFloat = 1.0
    public var bufferSize: CGSize = .zero
    public var rootLayer: CALayer! = nil
    
    static private var colors: [String: UIColor] = [:]
  
    @IBOutlet weak private var previewView: UIView!
    
    @objc private(set) public var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            
            if let previewLayer = previewLayer {
                self.layer.addSublayer(previewLayer)
            }
        }
    }
    
    @objc public var session: CKFSession? {
        
        didSet {
            oldValue?.stop()
          
            if let session = session {
                self.previewLayer = AVCaptureVideoPreviewLayer(session: session.session)
                session.previewLayer = self.previewLayer
                session.overlayView = self
                session.start()
            }
        }
    }

    @objc public var autorotate: Bool = false {
        didSet {
            if !self.autorotate {
                self.previewLayer?.connection?.videoOrientation = .portrait
            }
        }
    }
    
    @objc public override init(frame: CGRect) {
        super.init(frame: frame)
        self.setupView()
    }
    
    @objc public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.setupView()
    }
    
    private func setupView() {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(recognizer:)))
        self.addGestureRecognizer(tapGestureRecognizer)
        
        let pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(recognizer:)))
        self.addGestureRecognizer(pinchGestureRecognizer)
    }
    
    @objc private func handleTap(recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: self)
        if let point = self.previewLayer?.captureDevicePointConverted(fromLayerPoint: location) {
            self.session?.focus(at: point)
        }
    }
    
    @objc private func handlePinch(recognizer: UIPinchGestureRecognizer) {
        if recognizer.state == .began {
            recognizer.scale = self.lastScale
        }
        
        let zoom = max(1.0, min(10.0, recognizer.scale))
        self.session?.zoom = Double(zoom)
        
        if recognizer.state == .ended {
            self.lastScale = zoom
        }
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        self.previewLayer?.frame = self.bounds
        
        if self.autorotate {
            self.previewLayer?.connection?.videoOrientation = UIDevice.current.orientation.videoOrientation
        }
    }
    
    // Select the color for the bounding box
    public func labelColor(with label: String) -> UIColor {
        if let color = CKFPreviewView.colors[label] {
            return color
        } else {
            let color = UIColor(hue: .random(in: 0...1), saturation: 1, brightness: 1, alpha: 0.8)
            CKFPreviewView.colors[label] = color
            return color
        }
    }
    
    // Draw the bounding boxes on the predicted objects coming from the car detection model
    public var predictedObjects: [VNRecognizedObjectObservation] = [] {
        didSet {
            self.drawBoxs(with: predictedObjects)
            self.setNeedsDisplay()
        }
    }
    
    // Draw the bounding box for each prediction only if the vision model detects a car
    func drawBoxs(with predictions: [VNRecognizedObjectObservation]){
        subviews.forEach({ $0.removeFromSuperview() })
        for prediction in predictions {
            if (prediction.label == "car" && prediction.boundingBox.width * prediction.boundingBox.height > 0.15) {
                print(prediction.boundingBox.width * prediction.boundingBox.height, 1000)
                createLabelAndBox(prediction: prediction)
            }
        }
    }
    
    
    func createLabelAndBox(prediction: VNRecognizedObjectObservation) {
        let labelString: String? = prediction.label
        let color: UIColor = labelColor(with: labelString ?? "N/A")
    
        let bgRect = rotateRect(prediction.boundingBox)
        let bgView = UIView(frame: bgRect)
        bgView.layer.borderColor = color.cgColor
        bgView.layer.borderWidth = 4
        bgView.backgroundColor = UIColor.clear
        addSubview(bgView)
    }
    
    func rotateRect(_ rect: CGRect) -> CGRect {
        let x = rect.midX
        let y = rect.midY
        let scale = CGAffineTransform.identity.scaledBy(x: bounds.width, y: bounds.height)
        let transform = CGAffineTransform(translationX: x, y: y)
                                        .rotated(by: .pi / 2)
                                        .translatedBy(x: -x, y: -y)
        return rect.applying(transform).applying(scale)
    }
}

extension VNRecognizedObjectObservation {
    var label: String? {
        return self.labels.first?.identifier
    }
}
