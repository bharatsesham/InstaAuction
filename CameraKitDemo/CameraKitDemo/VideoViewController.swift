//
//  This file is responsible for controlling the camera UI and the camera preview.
//  Created by Avinash Parasurampuram on 09/01/2020.
//  Modified by Bharat Sesham, Avinash Parasurampuram
//

import UIKit

import CameraKit
import AVKit
import Vision
import CoreMedia
import CoreMotion
import CoreLocation

// This class handles the video preview the user sees after he/she is done recording the video. Handles dismiss/save
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

// This class handles the instructions the user sees on the screen, also initiates the object detection and car side detection
// models.
class VideoViewController: UIViewController, CKFSessionDelegate, CLLocationManagerDelegate{

    func didChangeValue(session: CKFSession, value: Any, key: String) {
        // No change here
    }

    let locationManager = CLLocationManager()

    @IBOutlet weak var directionLabel: UILabel!
    @IBOutlet weak var infoLabel: UILabel!
    @IBOutlet weak var captureButton: UIButton!

    var request: VNCoreMLRequest!
    var vision_request: VNCoreMLRequest?
    var predictions: [VNRecognizedObjectObservation] = []
    let semaphore = DispatchSemaphore(value: 1)
    var isRecording = false
    var predictedSide = "Init"


    // This function displays the general info like "Car Not Found", "Left side Detected" etc..(positioned towards left
    func displayInfo(value: String, key: String){
        if self.foundCar == false {
            self.infoLabel.textColor = UIColor.black
            self.infoLabel.font = self.directionLabel.font.withSize(15)
            if self.isRecording == false{
                self.infoLabel.text = "Car not found."
            }
        }
        else {
            if key == "angle"{
                self.infoLabel.textColor = UIColor.black
                self.infoLabel.text = "Info: " + (String)(value) + " detected."
                self.infoLabel.font = self.infoLabel.font.withSize(15)
            }
        }
    }

    // This function displays the instructions like "Move towards right", "Move Slow" etc..(positioned towards right
    func displayInstruction(value: Float, key: String){
        // Instruction if car is not found.
        if self.foundCar == false {
            self.directionLabel.textColor = UIColor.black
            self.directionLabel.font = self.directionLabel.font.withSize(15)
            if self.isRecording == false{
                self.directionLabel.text = "Point the camera towards a car."
            }
        }
        else{
            // When car is found - check for the recording status.
            // If not recording - Advice to go to the front of the car.
            if self.isRecording == false {
                self.directionLabel.textColor = UIColor.black
                self.directionLabel.font = self.directionLabel.font.withSize(15)
                if self.predictedSide != "Front"{
                    self.directionLabel.text = "Move to the front of the car and start recording."
                }
                else {
                    self.directionLabel.text = "Please start recording."
                }
            }
            else {
                var canMove = false
                if key == "depth"{
                    self.directionLabel.textColor = UIColor.black
                    self.directionLabel.font = self.directionLabel.font.withSize(15)
                    // The numbers 12, 1 and 10 are not magic numbers. The app works best with these values set up when it tries to detect the car
                    if value > 12 {
                        self.directionLabel.text = "Distance is either too close or too far -"// + value.description
                    }
                    // Checking if the user is too close to the car
                    else if value < 1 {
                        self.directionLabel.text = "Instruction: Move away from the automobile" //+ value.description
                    }
                    else if value > 10 {
                        self.directionLabel.text = "Instruction: Move closer to the automobile"// + value.description
                    }
                    else{
                        canMove = true
                    }
                }

                if canMove == true{ // If recording
                    self.directionLabel.textColor = UIColor.blue
                    self.directionLabel.text = "Instruction: Please continue moving towards the right"
                }
        }
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
          if let nvc = segue.destination as? UINavigationController, let vc = nvc.children.first as? VideoPreviewViewController {
            vc.url = sender as? URL
        }
    }


    @IBOutlet weak var previewView: CKFPreviewView! {
        didSet {
            // No change here
        }
    }

    var car_side_det_model: MLModel? = nil
    var car_recog_model: MLModel? = nil
    var foundCar = false

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.landscapeLeft
    }

    override var shouldAutorotate: Bool {
        return false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        directionLabel.frame.size.height = 275
        directionLabel.frame.size.width = 100

        // Set-up for location tracker. This will help us track the speed of the user.
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()

        infoLabel.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi/2))
        directionLabel.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi/2))

        let value = UIInterfaceOrientation.portrait.rawValue
        UIDevice.current.setValue(value, forKey: "orientation")

        car_side_det_model = resnet_train_final().model
        car_recog_model = YOLOv3TinyNew().model


        let session = CKFVideoSession()
        let videoDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera], mediaType: .video, position: .back).devices.first
        do {
            try videoDevice!.lockForConfiguration()
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
        setUpModels()

    }

    // Setting up both the car detection and car side detection models
    func setUpModels() -> NSError?{

        let error: NSError! = nil

        guard let carSideDetectModel = try? VNCoreMLModel(for: car_side_det_model!) else {
            print("Error: could not create Vision model")
            return NSError(domain: "VNClassificationObservation", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model file is missing"])
        }

        self.request = VNCoreMLRequest(model: carSideDetectModel, completionHandler: self.requestDidComplete)
        self.request.imageCropAndScaleOption = .scaleFill

        guard let carRecognitionModel = try? VNCoreMLModel(for: car_recog_model!) else {
            print("Error: could not create Vision model")
            return NSError(domain: "VNClassificationObservation", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model file is missing"])
        }

        self.vision_request = VNCoreMLRequest(model: carRecognitionModel, completionHandler:self.visionRequestDidComplete)
        self.vision_request?.imageCropAndScaleOption = .scaleFill
        return error
    }

    // Callback that receives the results for car side detection model
    func requestDidComplete(request: VNRequest, error: Error?) {
        if let observations = request.results as? [VNClassificationObservation] {

            // The observations appear to be sorted by confidence already, so we
            // take the top 5 and map them to an array of (String, Double) tuples.
            let top5 = observations.prefix(through: 0)
                .map { ($0.identifier, Double($0.confidence)) }

            // Show the results on the main thread
            DispatchQueue.main.async{
                self.show(results: top5)
            }
            semaphore.signal()
        }
    }

    // Callback that receives the results for the car detection model
    func visionRequestDidComplete(request: VNRequest, error: Error?) {
        self.foundCar = false
        if let predictions = request.results as? [VNRecognizedObjectObservation] {
            for prediction in predictions {
                if (prediction.label == "car") {
                    self.foundCar = true
                    break
                }
            }

            // Show the results on the main thread
            DispatchQueue.main.async {
                // Draw the bounding boxes based on the predictions
                self.previewView.predictedObjects = predictions
            }
        }
        semaphore.signal()
    }

    typealias Prediction = (String, Double)

    // Predict using the pixel buffer for the car side detection model
    func predict(pixelBuffer: CVPixelBuffer) {
        // Measure how long it takes to predict a single video frame. Note that
        // predict() can be called on the next frame while the previous one is
        // still being processed. Hence the need to queue up the start times.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        try? handler.perform([self.request])
    }

    // Show the results
    func show(results: [Prediction]) {
        var s: [String] = []
        for (i, pred) in results.enumerated() {
            self.predictedSide = pred.0
            self.displayInfo(value: pred.0, key: "angle")
            s.append(String(format: "%d: %@ (%3.2f%%)", i + 1, pred.0, pred.1 * 100))
        }
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

    // Handle the record button operations
    @IBAction func handleCapture(_ sender: UIButton) {
        if let session = self.previewView.session as? CKFVideoSession {
            if session.isRecording {
                sender.backgroundColor = UIColor.red.withAlphaComponent(0.5)
                self.isRecording = false
                session.stopRecording()
            } else {
                sender.backgroundColor = UIColor.red
                self.isRecording = true
                session.record({ (url) in
                    self.performSegue(withIdentifier: "Preview", sender: url)
                    usleep(200000)
                }) { (_) in
                    self.infoLabel.text = "Error in Recording"
                }
            }
        }
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    func predictUsingVision(pixelBuffer: CVPixelBuffer) {
        guard let request = self.vision_request else { fatalError() }
        // vision framework configures the input size of image following our model's input configuration automatically
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        try? handler.perform([request])
    }

    // Calculating the speed at which the user moves.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {

        let location = locations[locations.count - 1]

        let res_speed = location.speed
        let formatted_speed = (String)(format:"%.2f",res_speed)

        DispatchQueue.main.async{
            if(formatted_speed > "1"){
                self.infoLabel.text = "Go slow!!"
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Error in location")
    }

}

extension VNRecognizedObjectObservation {
    var label: String? {
        return self.labels.first?.identifier
    }
}

// This extension receives the camera output buffer and depth.
extension VideoViewController: VideoCaptureDelegate {

    func videoCapture(didCaptureVideoFrame pixelBuffer: CVPixelBuffer?, timestamp: CMTime) {
        if let pixelBuffer = pixelBuffer {
            // For better throughput, perform the prediction on a background queue
            // instead of on the VideoCapture queue. We use the semaphore to block
            // the capture queue and drop frames when Core ML can't keep up.

            DispatchQueue.global(qos: .background).async
            {
                self.semaphore.wait()
                self.predictUsingVision(pixelBuffer: pixelBuffer)
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


