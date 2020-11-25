//
//  VideoViewController.swift
//  CameraKitDemo
//
//  Created by Adrian Mateoaea on 17/01/2019.
//  Modified by Bharat Sesham, Avinash Parasurampuram
//  Copyright © 2019 Wonderkiln. All rights reserved.
//

import UIKit

import CameraKit
import AVKit
import Vision
import CoreMedia
import CoreMotion

class VideoPreviewViewController: UIViewController {
    
    var url: URL?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let url = self.url {
            let player = AVPlayerViewController()
            player.player = AVPlayer(url: url)
            player.view.frame = self.view.bounds
            
            self.view.addSubview(player.view)
            self.addChild(player)
            
            player.player?.play()
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    @IBAction func handleCancel(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func handleSave(_ sender: Any) {
        if let url = self.url {
            UISaveVideoAtPathToSavedPhotosAlbum(url.path, self, #selector(handleDidCompleteSavingToLibrary(path:error:contextInfo:)), nil)
        }
    }
    
    @objc func handleDidCompleteSavingToLibrary(path: String?, error: Error?, contextInfo: Any?) {
        self.dismiss(animated: true, completion: nil)
    }
}

class VideoSettingsViewController: UITableViewController {
    
    var previewView: CKFPreviewView!
    
    @IBOutlet weak var cameraSegmentControl: UISegmentedControl!
    @IBOutlet weak var flashSegmentControl: UISegmentedControl!
    @IBOutlet weak var gridSegmentControl: UISegmentedControl!
    
    @IBAction func handleCamera(_ sender: UISegmentedControl) {
        if let session = self.previewView.session as? CKFVideoSession {
            session.cameraPosition = sender.selectedSegmentIndex == 0 ? .back : .front
        }
    }
    
    @IBAction func handleFlash(_ sender: UISegmentedControl) {
        if let session = self.previewView.session as? CKFVideoSession {
            let values: [CKFVideoSession.FlashMode] = [.auto, .on, .off]
            session.flashMode = values[sender.selectedSegmentIndex]
        }
    }
    
    @IBAction func handleGrid(_ sender: UISegmentedControl) {
        //self.previewView.showGrid = sender.selectedSegmentIndex == 1
    }
    
    @IBAction func handleMode(_ sender: UISegmentedControl) {
        if let session = self.previewView.session as? CKFVideoSession {
            let modes = [(1920, 1080, 30), (1920, 1080, 60), (3840, 2160, 30)]
            let mode = modes[sender.selectedSegmentIndex]
            session.setWidth(mode.0, height: mode.1, frameRate: mode.2)
        }
    }
}



class VideoViewController: UIViewController, CKFSessionDelegate{
    
    
    var isInferencing = false
    
    @IBOutlet weak var zoomLabel: UILabel!
    @IBOutlet weak var captureButton: UIButton!
    
    @IBOutlet weak var labelsTableView: UITableView!
    
    //@IBOutlet weak var depthvalue:UILabel!
    
    @IBOutlet weak var predictionLabel: UILabel!
    @IBOutlet weak var timeLabel: UILabel!
    
    var request: VNCoreMLRequest!
//    var requests = [VNRequest]()
    var requests: VNCoreMLRequest?
    var predictions: [VNRecognizedObjectObservation] = []


    
    var startTimes: [CFTimeInterval] = []
    
    var framesDone = 0
    var frameCapturingStartTime = CACurrentMediaTime()
    let semaphore = DispatchSemaphore(value: 3)
    var detectionOverlay: CALayer! = nil
    
    // Newly Added Code
    
    
    func didChangeValue(session: CKFSession, value: Any, key: String) {
        if key == "zoom" {
            //self.zoomLabel.text = String(format: "%.1fx", value as! Double)
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let vc = segue.destination as? VideoSettingsViewController {
            vc.previewView = self.previewView
        } else if let nvc = segue.destination as? UINavigationController, let vc = nvc.children.first as? VideoPreviewViewController {
            vc.url = sender as? URL
        }
    }
    
    
    @IBOutlet weak var previewView: CKFPreviewView! {
        didSet {
            
        }
    }
    
    @IBOutlet weak var panelView: UIVisualEffectView!
    
    var model: MLModel? = nil
    var model2: MLModel? = nil
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.landscapeLeft
    }
    
    override var shouldAutorotate: Bool {
        return false
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let value = UIInterfaceOrientation.portrait.rawValue
        UIDevice.current.setValue(value, forKey: "orientation")
        
        
        //        self.panelView.transform = CGAffineTransform(translationX: 0, y: self.panelView.frame.height + 5)
        //        self.panelView.isUserInteractionEnabled = false
        
        model = resnet50custom_recent().model
        model2 = YOLOv3TinyNew().model
        
        
        let session = CKFVideoSession()
        
        let videoDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera], mediaType: .video, position: .back).devices.first
        
        do {
            try  videoDevice!.lockForConfiguration()
            let dimensions = CMVideoFormatDescriptionGetDimensions((videoDevice?.activeFormat.formatDescription)!)
            self.previewView.bufferSize.width = CGFloat(dimensions.width)
            self.previewView.bufferSize.height = CGFloat(dimensions.height)
            videoDevice!.unlockForConfiguration()
        } catch {
            print(error)
        }
        session.delegate = self
        
        
        self.previewView.autorotate = true
        self.previewView.session = session
        self.previewView.previewLayer?.videoGravity = .resizeAspectFill
        self.previewView.rootLayer = self.previewView.layer
        self.previewView.previewLayer!.frame = self.previewView.rootLayer.bounds
        self.previewView.rootLayer.addSublayer(self.previewView.previewLayer!)
        
        setUpVision()
        
    }
    
    func setUpVision() -> NSError?{
        
        let error: NSError! = nil
        
        guard let visionModel = try? VNCoreMLModel(for: model!) else {
            print("Error: could not create Vision model")
            return NSError(domain: "VNClassificationObservation", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model file is missing"])
        }
        
        guard let visionModel2 = try? VNCoreMLModel(for: model2!) else {
            print("Error: could not create Vision model")
            return NSError(domain: "VNClassificationObservation", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model file is missing"])
        }
                
        
        self.request = VNCoreMLRequest(model: visionModel, completionHandler: self.requestDidComplete)
        self.request.imageCropAndScaleOption = .scaleFill

        self.requests = VNCoreMLRequest(model: visionModel2, completionHandler:self.visionRequestDidComplete)
        self.requests?.imageCropAndScaleOption = .scaleFill
        
        
//
//        let objectRecognition = VNCoreMLRequest(model: visionModel2, completionHandler: { (request, error) in
//            if let predictions = request.results as? [VNRecognizedObjectObservation] {
//
//                DispatchQueue.main.async{
//                    self.previewView.predictedObjects = predictions
//                }
//
//                self.isInferencing = false
//            } else {
//                self.isInferencing = false
//            }
//            self.semaphore.signal()
//            // Old code commented out
//        })
//        self.requests = [objectRecognition]
//
        return error
    }
    
    func visionRequestDidComplete(request: VNRequest, error: Error?) {
        if let predictions = request.results as? [VNRecognizedObjectObservation] {
            self.predictions = predictions
            DispatchQueue.main.async {
                self.previewView.predictedObjects = predictions
                self.isInferencing = false
            }
        } else {
            self.isInferencing = false
        }
        semaphore.signal()
    }
    
    // MARK: - Doing inference
    typealias Prediction = (String, Double)
    
    func predict(pixelBuffer: CVPixelBuffer) {
        // Measure how long it takes to predict a single video frame. Note that
        // predict() can be called on the next frame while the previous one is
        // still being processed. Hence the need to queue up the start times.
        startTimes.append(CACurrentMediaTime())
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        try? handler.perform([self.request])
    }
    
    func requestDidComplete(request: VNRequest, error: Error?) {
        if let observations = request.results as? [VNClassificationObservation] {
            
            // The observations appear to be sorted by confidence already, so we
            // take the top 5 and map them to an array of (String, Double) tuples.
            let top5 = observations.prefix(through: 1)
                .map { ($0.identifier, Double($0.confidence)) }
            
            DispatchQueue.main.async{
                self.show(results: top5)
            }
            semaphore.signal()
            
        }
    }
    
    func show(results: [Prediction]) {
        var s: [String] = []
        for (i, pred) in results.enumerated() {
            s.append(String(format: "%d: %@ (%3.2f%%)", i + 1, pred.0, pred.1 * 100))
        }
        predictionLabel.text = s.joined(separator: "\n\n")
        if  startTimes.count != 0
        {
            let elapsed = CACurrentMediaTime() - startTimes.remove(at: 0)
            // let fps = self.measureFPS()
            timeLabel.text = String(format: "Elapsed time %.5f s", elapsed)
        }
    }
    
    func measureFPS() -> Double {
        // Measure how many frames were actually delivered per second.
        framesDone += 1
        let frameCapturingElapsed = CACurrentMediaTime() - frameCapturingStartTime
        let currentFPSDelivered = Double(framesDone) / frameCapturingElapsed
        if frameCapturingElapsed > 1 {
            framesDone = 0
            frameCapturingStartTime = CACurrentMediaTime()
        }
        return currentFPSDelivered
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let value = UIInterfaceOrientation.portrait.rawValue
        UIDevice.current.setValue(value, forKey: "orientation")
        self.previewView.session?.start()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.previewView.session?.stop()
    }
    
    @IBAction func handleSwipeDown(_ sender: Any) {
        self.panelView.isUserInteractionEnabled = false
        self.captureButton.isUserInteractionEnabled = true
        UIView.animate(withDuration: 0.2) {
            self.panelView.transform = CGAffineTransform(translationX: 0, y: self.panelView.frame.height)
        }
    }
    
    @IBAction func handleSwipeUp(_ sender: Any) {
        self.panelView.isUserInteractionEnabled = true
        self.captureButton.isUserInteractionEnabled = false
        UIView.animate(withDuration: 0.2) {
            self.panelView.transform = CGAffineTransform(translationX: 0, y: 0)
        }
    }
    
    @IBAction func handleCapture(_ sender: UIButton) {
        if let session = self.previewView.session as? CKFVideoSession {
            if session.isRecording {
                sender.backgroundColor = UIColor.red.withAlphaComponent(0.5)
                session.stopRecording()
            } else {
                sender.backgroundColor = UIColor.red
                session.record({ (url) in
                    self.performSegue(withIdentifier: "Preview", sender: url)
                    usleep(200000) 
                }) { (_) in
                    //
                }
            }
        }
    }
    
    //    @IBAction func handlePhoto(_ sender: Any) {
    //        guard let window = UIApplication.shared.keyWindow else {
    //            return
    //        }
    //
    //        let vc = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "Photo")
    //        UIView.transition(with: window, duration: 0.5, options: .transitionFlipFromLeft, animations: {
    //            window.rootViewController = vc
    //        }, completion: nil)
    //    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    func predictUsingVision(pixelBuffer: CVPixelBuffer) {
        guard let request = self.requests else { fatalError() }
        // vision framework configures the input size of image following our model's input configuration automatically
//        self.semaphore.wait()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        try? handler.perform([request])
    }
}

extension VideoViewController: VideoCaptureDelegate {
    
    func videoCapture(didCaptureVideoFrame pixelBuffer: CVPixelBuffer?, timestamp: CMTime) {
        print("BackEnd")
        if let pixelBuffer = pixelBuffer {
            // For better throughput, perform the prediction on a background queue
            // instead of on the VideoCapture queue. We use the semaphore to block
            // the capture queue and drop frames when Core ML can't keep up.
            //let exifOrientation = self.exifOrientationFromDaeviceOrientation()
            DispatchQueue.global(qos: .default).async
            {
                self.semaphore.wait()
                self.predict(pixelBuffer: pixelBuffer)
            }
            DispatchQueue.global(qos: .background).async
            {
                self.semaphore.wait()
                self.predictUsingVision(pixelBuffer: pixelBuffer)
            }
        }
    }
    
    public func exifOrientationFromDeviceOrientation() -> CGImagePropertyOrientation {
        let curDeviceOrientation = UIDevice.current.orientation
        let exifOrientation: CGImagePropertyOrientation
        
        switch curDeviceOrientation {
        case UIDeviceOrientation.portraitUpsideDown:  // Device oriented vertically, home button on the top
            exifOrientation = .left
        case UIDeviceOrientation.landscapeLeft:       // Device oriented horizontally, home button on the right
            exifOrientation = .left
        case UIDeviceOrientation.landscapeRight:      // Device oriented horizontally, home button on the left
            exifOrientation = .left
        case UIDeviceOrientation.portrait:            // Device oriented vertically, home button on the bottom
            exifOrientation = .left
        default:
            //        exifOrientation = .up
            exifOrientation = .left
            
        }
        return exifOrientation
    }
    
    func depthvideoCapture(distance:String) {
        let distancevalue = (distance as NSString).floatValue
        DispatchQueue.main.async {
            self.zoomLabel.text = "Depth: " + (String)(distancevalue) + " m"
            self.semaphore.signal()
        }
    }
}

