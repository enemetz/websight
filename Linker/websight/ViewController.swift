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
    
    //Tracks seen items
    let numberTracker = StringTracker()
    let captureSession = AVCaptureSession()
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .portrait }
    //Sets up the camera and preview layer
    //MARK: setupCamera
    func setupCamera() {
       //let captureSession = AVCaptureSession()
    
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
            captureDevice.videoZoomFactor = 2
            captureDevice.autoFocusRangeRestriction = .near
            captureDevice.unlockForConfiguration()
        } catch {
            print("Could not set zoom level due to error: \(error)")
                return
        }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        view.layer.addSublayer(previewLayer)
        previewLayer.frame = view.layer.bounds
        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(dataOutput)
        previewLayer.videoGravity = .resizeAspectFill
        

        let layer = CAShapeLayer()
        layer.path = UIBezierPath(rect: CGRect(x: 64, y: 500, width: 160, height: 300)).cgPath
        layer.cornerRadius = 5
        layer.borderColor = UIColor.red.cgColor
        layer.borderWidth = 3
        view.layer.insertSublayer(layer, above: previewLayer)
        
        instructionLabel.text = "Aim the camera at a URL"
        
        captureSession.startRunning()
    }
    
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
            
            // ROI changed, update transform.
            //setupOrientationAndTransform()
            
            // Update the cutout to match the new ROI.
            DispatchQueue.main.async {
                // Wait for the next run cycle before updating the cutout. This
                // ensures that the preview layer already has its new orientation.
                //self.updateCutout()
            }
        }
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
    
    override func viewWillAppear(_ animated: Bool) {
        AppDelegate.AppUtility.lockOrientation(UIInterfaceOrientationMask.portrait, andRotateTo: UIInterfaceOrientation.portrait)
            }
    
    override func viewWillDisappear(_ animated: Bool) {
            AppDelegate.AppUtility.lockOrientation(UIInterfaceOrientationMask.all)

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
    



