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
    var request: VNRecognizeTextRequest!
    let regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
    var textOrientation = CGImagePropertyOrientation.up
    var maskLayer = CAShapeLayer()
    let instructionLabel = UILabel()
    var frameView: UIView?
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .portrait }
    
    func setupCamera() {
       let captureSession = AVCaptureSession()
    
        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .back) else {return}
        
        guard let input = try? AVCaptureDeviceInput(device: captureDevice) else {return}
        captureSession.addInput(input)
        if captureDevice.supportsSessionPreset(.hd4K3840x2160) {
            captureSession.sessionPreset = AVCaptureSession.Preset.hd4K3840x2160
                } else {
                    captureSession.sessionPreset = AVCaptureSession.Preset.hd1920x1080
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
        //captureSession.startRunning()
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        view.layer.addSublayer(previewLayer)
        previewLayer.frame = view.frame
        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(dataOutput)
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        
        /*let rectLayer = CALayer()
        rectLayer.frame = regionOfInterest
        rectLayer.borderColor = UIColor.blue.cgColor
        rectLayer.cornerRadius = 10
        rectLayer.borderWidth = 10 */
        
        instructionLabel.text = "Aim the camera at a URL"
        
        captureSession.startRunning()
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        //print("Hello ", Date())
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    // Configure for running in real-time.
                    request.recognitionLevel = .fast
                    // Language correction won't help recognizing phone numbers. It also
                    // makes recognition slower.
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
    

    func detectedTextHandler(request: VNRequest?, error: Error?) {
      
        
        guard let results = request?.results, results.count > 0 else {
                print("No text found")
                return
            }
        
        
        let maxCandidate = 1
        for result in results {
            
            if let observation = result as? VNRecognizedTextObservation {
                for text in observation.topCandidates(maxCandidate) {
                    let range = NSRange(location: 0, length: text.string.utf16.count)
                    let regex = try! NSRegularExpression(pattern: "(?i)https?://(?:www\\.)?\\S+(?:/|\\b)")

                    if(regex.firstMatch(in: text.string, options: [], range: range) != nil) {
                        if let url = URL(string: text.string) {
                            DispatchQueue.main.async {UIApplication.shared.open(url)
                            }
                        }
                        print(text.string)
                    } else {
                        print("Detected: ", text.string)
                    }
                    
                  
                }
            }
        }
    }
    
    
    override func viewDidLoad() {
        request = VNRecognizeTextRequest(completionHandler: detectedTextHandler)
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        //let regionOfInterest = CGRect(x: 0, y: 0, width: 10, height: 20)
        request.recognitionLevel = VNRequestTextRecognitionLevel.fast
        request.revision = VNRecognizeTextRequestRevision1
        request.usesLanguageCorrection = false
        setupCamera()
        
        
       
    }
    
    override func viewDidAppear(_ animated: Bool) {
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
    }

}

