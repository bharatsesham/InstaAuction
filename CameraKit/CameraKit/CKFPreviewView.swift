//
// This is a custom view for showing the frames/record the video. This file also is responsible for drawing bounding boxes.
//
//  Created by Avinash Parasurampuram on 08/23/2020.
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
    }

    @objc public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
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

    // Draw the bounding box for each prediction only if the vision model detects a car.
    func drawBoxs(with predictions: [VNRecognizedObjectObservation]){
        subviews.forEach({ $0.removeFromSuperview() })
        for prediction in predictions {
            if (prediction.label == "car" && prediction.boundingBox.width * prediction.boundingBox.height > 0.15) {
                print(prediction.boundingBox.width * prediction.boundingBox.height, 1000)
                createLabelAndBox(prediction: prediction)
            }
        }
    }

    // This will create the box around the predicted object.
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

    // Rotates the bounding box predictions by 90 degrees.
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



