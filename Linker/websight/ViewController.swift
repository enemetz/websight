//
//  ViewController.swift
//  Linker
//
//  Created by Evan Nemetz on 7/11/19.
//  Copyright © 2019 Evan Nemetz. All rights reserved.
//

import UIKit
import Vision
import AVFoundation
import SafariServices

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    var previewView: PreviewView!
    //Text recognition request
    var request: VNRecognizeTextRequest!
    //Region of interest initial; Gets changed later

    var regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
    var textOrientation = CGImagePropertyOrientation.up
    var maskLayer = CAShapeLayer()
    //Unused label
    let instructionLabel = UILabel()
    var frameView: UIView!
    var currentOrientation = UIDeviceOrientation.portrait
    var bufferAspectRatio: Double!
    var uiRotationTransform = CGAffineTransform.identity
    var roiToGlobalTransform = CGAffineTransform.identity
    var visionToAVFTransform = CGAffineTransform.identity
    var bottomToTopTransform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1)
    let layer = CAShapeLayer()
    //Tracks seen items
    let numberTracker = StringTracker()
    let captureSession = AVCaptureSession()
    var previewLayer = AVCaptureVideoPreviewLayer()
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .portrait }
    //Sets up the camera and preview layer
    //MARK: setupCamera
    func setupCamera() {
        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .back) else {return}
        
        guard let input = try? AVCaptureDeviceInput(device: captureDevice) else {return}
        captureSession.addInput(input)
        if captureDevice.supportsSessionPreset(.hd4K3840x2160) {
            captureSession.sessionPreset = AVCaptureSession.Preset.hd4K3840x2160
            bufferAspectRatio = 3840.0 / 2160.0
        } else {
                captureSession.sessionPreset = AVCaptureSession.Preset.hd1920x1080
                bufferAspectRatio = 1920.0 / 1080.0
        }
        do {
            try captureDevice.lockForConfiguration()
            captureDevice.videoZoomFactor = 1
            captureDevice.autoFocusRangeRestriction = .near
            captureDevice.unlockForConfiguration()
        } catch {
            print("Could not set zoom level due to error: \(error)")
                return
        }
        
        //let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        view.layer.insertSublayer(previewLayer, at: 0)
        previewLayer.frame = view.layer.bounds
        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(dataOutput)
        dataOutput.alwaysDiscardsLateVideoFrames = true
        previewLayer.videoGravity = .resizeAspectFill
        print("\(regionOfInterest)")
        
        calculateRegionOfInterest()
        let parentWidth = view.bounds.size.width
        let parentHeight = view.bounds.size.height
        var convertRect = regionOfInterest
        convertRect.origin.x *= parentWidth
        convertRect.origin.y *= parentHeight
        convertRect.size.width *= parentWidth
        convertRect.size.height *= parentHeight
        
        let roiView = UIView(frame: convertRect)
        roiView.layer.borderWidth = 3
        roiView.layer.borderColor = UIColor.systemBlue.cgColor
        view.addSubview(roiView)
        view.bringSubviewToFront(roiView)
        
        /*layer.borderWidth = 3
        layer.backgroundColor = UIColor.clear.cgColor
        layer.borderColor = UIColor.systemBlue.cgColor
        layer.path = UIBezierPath(roundedRect: CGRect(x: 64, y: 64, width: 500, height: 300), cornerRadius: 10).cgPath
        view.layer.insertSublayer(layer, above: previewLayer)*/
        instructionLabel.text = "Aim the camera at a URL"
        
        captureSession.startRunning()
    }
    
    
    //MARK: Region of interest
    func calculateRegionOfInterest() {
            // In landscape orientation the desired ROI is specified as the ratio of
            // buffer width to height. When the UI is rotated to portrait, keep the
            // vertical size the same (in buffer pixels). Also try to keep the
            // horizontal size the same up to a maximum ratio.
            let desiredHeightRatio = 0.15
            let desiredWidthRatio = 0.6
            let maxPortraitWidth = 0.8
            
            // Figure out size of ROI.
            let size: CGSize
            if currentOrientation.isPortrait || currentOrientation == .unknown {
                size = CGSize(width: min(desiredWidthRatio * bufferAspectRatio, maxPortraitWidth), height: desiredHeightRatio / bufferAspectRatio)
            } else {
                size = CGSize(width: desiredWidthRatio, height: desiredHeightRatio)
            }
            // Make it centered.
            regionOfInterest.origin = CGPoint(x: (1 - size.width) / 2, y: (1 - size.height) / 2)
            regionOfInterest.size = size
            print("\(regionOfInterest)")
            // ROI changed, update transform.
            setupOrientationAndTransform()
            
            
            // Update the cutout to match the new ROI.
            DispatchQueue.main.async {
                // Wait for the next run cycle before updating the cutout. This
                // ensures that the preview layer already has its new orientation.
            }
        }
    

    //MARK: Orientation
    func setupOrientationAndTransform() {
        // Recalculate the affine transform between Vision coordinates and AVF coordinates.
        
        // Compensate for region of interest.
        let roi = regionOfInterest
        roiToGlobalTransform = CGAffineTransform(translationX: roi.origin.x, y: roi.origin.y).scaledBy(x: roi.width, y: roi.height)
        
        // Compensate for orientation (buffers always come in the same orientation).
        switch currentOrientation {
        case .landscapeLeft:
            textOrientation = CGImagePropertyOrientation.up
            uiRotationTransform = CGAffineTransform.identity
        case .landscapeRight:
            textOrientation = CGImagePropertyOrientation.down
            uiRotationTransform = CGAffineTransform(translationX: 1, y: 1).rotated(by: CGFloat.pi)
        case .portraitUpsideDown:
            textOrientation = CGImagePropertyOrientation.left
            uiRotationTransform = CGAffineTransform(translationX: 1, y: 0).rotated(by: CGFloat.pi / 2)
        default: // We default everything else to .portraitUp
            textOrientation = CGImagePropertyOrientation.right
            uiRotationTransform = CGAffineTransform(translationX: 0, y: 1).rotated(by: -CGFloat.pi / 2)
        }
        
        // Full Vision ROI to AVF transform.
        visionToAVFTransform = roiToGlobalTransform.concatenating(bottomToTopTransform).concatenating(uiRotationTransform)
    }
    //MARK: Capture Output
    //Capures every frame and does a text recognition request
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        //print("Hello ", Date())
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    request.recognitionLevel = .fast
                    request.usesLanguageCorrection = false
                    // Only run on the region of interest for maximum speed.
                    request.regionOfInterest = regionOfInterest
                    let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: textOrientation, options: [:])
                    do {
                        try requestHandler.perform([request])
                    } catch {
                        print(error)
                    }
                }
    }
    //MARK: Text Detection
    //Handles detected text
    func detectedTextHandler(request: VNRequest?, error: Error?) {
      var urls = [String]()
        guard let results = request!.results as? [VNRecognizedTextObservation] else {
                    print("No text was found")
                    return
                }
        
        let maxCandidate = 1
        for result in results {
            //Iterates through results and if the result matches regex then opens
            //matched result in safari
            if let observation = result as? VNRecognizedTextObservation {
                for text in observation.topCandidates(maxCandidate) {
                    let range = NSRange(location: 0, length: text.string.utf16.count)
                    let regex = try! NSRegularExpression(pattern: "(?i)https?://(?:www\\.)?\\S+(?:/|\\b)")

                    if let sureURL = numberTracker.getStableString() {
                        if(regex.firstMatch(in: text.string, options: [], range: range) != nil) {
                            if let url = URL(string: sureURL) {
                                    DispatchQueue.main.async {UIApplication.shared.open(url)
                                }
                            }
                        }
                            numberTracker.reset(string: sureURL)
                    }
                    
                    //print(observation.boundingBox)
                    if(regex.firstMatch(in: text.string, options: [], range: range) != nil) {
                        urls.append(text.string)
                        //if let url = URL(string: text.string) {
                            //DispatchQueue.main.async {UIApplication.shared.open(url)
                          //  }
                        //}
                        print(text.string)
                    } else {
                        print("Detected: ", text.string)
                    }
                }
            }
        }
        numberTracker.logFrame(strings: urls)
    }
    
    //MARK: ViewDidLoad
    override func viewDidLoad() {
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        request = VNRecognizeTextRequest(completionHandler: detectedTextHandler)
        super.viewDidLoad()
        //previewView.session = captureSession
        
        // Do any additional setup after loading the view.
        //let regionOfInterest = CGRect(x: 0, y: 0, width: 10, height: 20)
        maskLayer.backgroundColor = UIColor.clear.cgColor
        maskLayer.fillRule = .evenOdd
        //frameView.layer.mask = maskLayer
        
        request.recognitionLevel = VNRequestTextRecognitionLevel.fast
        request.revision = VNRecognizeTextRequestRevision1
        request.usesLanguageCorrection = false
        request.regionOfInterest = regionOfInterest
        
        setupCamera()
        //calculateRegionOfInterest()
        
        
        
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        // Only change the current orientation if the new one is landscape or
        // portrait. You can't really do anything about flat or unknown.
        let deviceOrientation = UIDevice.current.orientation
        if deviceOrientation.isPortrait || deviceOrientation.isLandscape {
            currentOrientation = deviceOrientation
        }
        
        // Handle device orientation in the preview layer.
        if let videoPreviewLayerConnection = previewLayer.connection {
            if let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation) {
                videoPreviewLayerConnection.videoOrientation = newVideoOrientation
            }
        }
        
        // Orientation changed: figure out new region of interest (ROI).
        calculateRegionOfInterest()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        //AppDelegate.AppUtility.lockOrientation(UIInterfaceOrientationMask.portrait, andRotateTo: UIInterfaceOrientation.portrait)
            }
    
    override func viewWillDisappear(_ animated: Bool) {
            //AppDelegate.AppUtility.lockOrientation(UIInterfaceOrientationMask.all)

        }
}

extension AVCaptureVideoOrientation {
 init?(deviceOrientation: UIDeviceOrientation) {
     switch deviceOrientation {
     case .portrait: self = .portrait
     case .portraitUpsideDown: self = .portraitUpsideDown
     case .landscapeLeft: self = .landscapeRight
     case .landscapeRight: self = .landscapeLeft
     default: return nil
         }
     }
 }
    



