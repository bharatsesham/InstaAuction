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
    
    @IBOutlet weak var directionLabel: UILabel!
    @IBOutlet weak var zoomLabel: UILabel!

    @IBOutlet weak var captureButton: UIButton!
    

    @IBOutlet weak var predictionLabel: UILabel!
    @IBOutlet weak var timeLabel: UILabel!
    
    var request: VNCoreMLRequest!
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
    
    func displayInfo(value: String, key: String){
        if self.foundCar == false {
            self.zoomLabel.textColor = UIColor.red
            self.zoomLabel.font = self.directionLabel.font.withSize(15)
            self.zoomLabel.text = "Car not found."
        }
        else {
            if key == "angle"{
                self.zoomLabel.textColor = UIColor.black
                self.zoomLabel.text = "Info: " + (String)(value) + " detected."
                self.zoomLabel.font = self.zoomLabel.font.withSize(15)
                }
        }
    }
    
    
    func displayInstruction(value: Float, key: String){
        // Instruction if car is not found.
        if self.foundCar == false {
            self.directionLabel.textColor = UIColor.red
            self.directionLabel.font = self.directionLabel.font.withSize(15)
            self.directionLabel.text = "Point the camera towards a car."
        }
        else{
            // When car is found.
//            if let session = self.previewView.session as? CKFVideoSession {
//                if session.isRecording {
//                }
            
            
            var canMove = false
            if key == "depth"{
                self.directionLabel.textColor = UIColor.red
                self.directionLabel.font = self.directionLabel.font.withSize(15)

                if value > 10 {
                self.directionLabel.text = "Distance is either too close or too far."
                }
                // Checking if the user is too close to the car, change 1 accordingly
                else if value < 1 {     // Add & condition based on angle
                    self.directionLabel.text = "Instruction: Move away from the automobile"
                }
                else if value > 5.5 {   // Add & condition based on angle
    //                self.directionLabel.text = "Instruction: " + (String)(value) + " detected."
                    self.directionLabel.text = "Instruction: Move closer to the automobile"
                }
                else{
                    canMove = true
                }
            }
            //            Add Speed
            if canMove == true{ // If recording
                self.directionLabel.textColor = UIColor.green
                self.directionLabel.text = "Instruction: Continue moving towards the right"
            }
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
    var foundCar = false

    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.landscapeLeft
    }
    
    override var shouldAutorotate: Bool {
        return false
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        zoomLabel.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi/2))
        directionLabel.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi/2))

        let value = UIInterfaceOrientation.portrait.rawValue
        UIDevice.current.setValue(value, forKey: "orientation")
        
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
        return error
    }
    
    func visionRequestDidComplete(request: VNRequest, error: Error?) {
        self.foundCar = false
        if let predictions = request.results as? [VNRecognizedObjectObservation] {
            for prediction in predictions {
                if (prediction.label == "bottle") {         // Change to car
                    self.foundCar = true
                    break
                }
            }
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
            let top5 = observations.prefix(through: 0)
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
            self.displayInfo(value: pred.0, key: "angle")
            s.append(String(format: "%d: %@ (%3.2f%%)", i + 1, pred.0, pred.1 * 100))
        }
//        predictionLabel.text = s.joined(separator: "\n\n")
//        if  startTimes.count != 0
//        {
//            let elapsed = CACurrentMediaTime() - startTimes.remove(at: 0)
//            timeLabel.text = String(format: "Elapsed time %.5f s", elapsed)
//        }
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
    
    
    func rotate(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
//            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
//                return nil
//            }
            var newPixelBuffer: CVPixelBuffer?
            let error = CVPixelBufferCreate(kCFAllocatorDefault,
                                            CVPixelBufferGetHeight(pixelBuffer),
                                            CVPixelBufferGetWidth(pixelBuffer),
                                            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                            nil,
                                            &newPixelBuffer)
            guard error == kCVReturnSuccess else {
                return nil
            }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
            let context = CIContext(options: nil)
            context.render(ciImage, to: newPixelBuffer!)
            return newPixelBuffer
        }
    
}

extension VideoViewController: VideoCaptureDelegate {
    
    func videoCapture(didCaptureVideoFrame pixelBuffer: CVPixelBuffer?, timestamp: CMTime) {
        if let pixelBuffer = pixelBuffer {
            // For better throughput, perform the prediction on a background queue
            // instead of on the VideoCapture queue. We use the semaphore to block
            // the capture queue and drop frames when Core ML can't keep up.
            //let exifOrientation = self.exifOrientationFromDaeviceOrientation()

            DispatchQueue.global(qos: .background).async
            {
                self.semaphore.wait()
                self.predictUsingVision(pixelBuffer: pixelBuffer)
                
//                self.predictUsingVision(pixelBuffer: self.rotate(pixelBuffer)!)
            }
            DispatchQueue.global(qos: .default).async
            {
                self.semaphore.wait()
                self.predict(pixelBuffer: pixelBuffer)
            }
        }
    }
    
    
    func depthvideoCapture(distance:String) {
        let distancevalue = (distance as NSString).floatValue
        DispatchQueue.main.async {
            self.displayInstruction(value: distancevalue, key: "depth")
            self.semaphore.signal()
        }
    }
}

