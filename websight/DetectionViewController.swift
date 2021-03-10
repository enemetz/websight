//
//  DetectionViewController.swift
//  websight
//
//  Created by Evan Nemetz on 2/16/21.
//  Copyright © 2021 Evan Nemetz. All rights reserved.
//

import UIKit
import Vision
import AVFoundation
import SafariServices
import CoreLocation
import MapKit
import MessageUI
import CallKit

class DetectionViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, MFMailComposeViewControllerDelegate {
    var previewView: PreviewView!
    //Text recognition request
    var request: VNRecognizeTextRequest!
    //Region of interest initial; Gets changed later
    var regionOfInterest = CGRect()
    var textOrientation = CGImagePropertyOrientation.up
    var maskLayer = CAShapeLayer()
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
    public let captureSession = AVCaptureSession()
    public var previewLayer = AVCaptureVideoPreviewLayer()
    let zoomButton = UIButton(type: .custom)
    var buttonCounter = 0
    var didDetectCall: Bool!
    var roiView: UIView!
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .portrait }
    //Sets up the camera and preview layer
    //MARK: setupCamera
    func setupCamera() {
        //captureSession.beginConfiguration()
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
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        view.layer.insertSublayer(previewLayer, at: 0)
        previewLayer.frame = view.layer.bounds
        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(dataOutput)
        dataOutput.alwaysDiscardsLateVideoFrames = true
        previewLayer.videoGravity = .resizeAspectFill
    
        
        calculateRegionOfInterest()
        DispatchQueue.main.async {
            let parentWidth = self.view.bounds.size.width
            let parentHeight = self.view.bounds.size.height
            var convertRect = self.regionOfInterest
            print(parentWidth)

            
            print(self.regionOfInterest.size.width)
            convertRect.origin.x = convertRect.origin.x * parentWidth
            convertRect.origin.y *= parentHeight
            convertRect.size.width = (convertRect.size.width * parentWidth) + 10
            convertRect.size.height *= parentHeight
            print("size is \(self.regionOfInterest)")
            print("ConvertRect: \(convertRect)")
            self.roiView = UIView(frame: convertRect)
            self.roiView.layer.borderWidth = 3
            self.roiView.layer.cornerRadius = 8
            self.roiView.layer.borderColor = UIColor.systemTeal.cgColor
            self.view.addSubview(self.roiView)
            self.view.bringSubviewToFront(self.roiView)
        }
        
        

        captureSession.startRunning()
    }
    
    
    //MARK: Region of interest
    func calculateRegionOfInterest() {
            // In landscape orientation the desired ROI is specified as the ratio of
            // buffer width to height. When the UI is rotated to portrait, keep the
            // vertical size the same (in buffer pixels). Also try to keep the
            // horizontal size the same up to a maximum ratio.
            let desiredHeightRatio = 0.12
            let desiredWidthRatio = 0.7
        let maxPortraitWidth = 0.75
            
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
            //DispatchQueue.main.async {
                // Wait for the next run cycle before updating the cutout. This
                // ensures that the preview layer already has its new orientation.
            //}
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
    //MARK: Email ActionSheet
    func emailAlert(sureURL: String) {
        successfulScan()
        previewLayer.isHidden = true
        let generator = UIImpactFeedbackGenerator(style: .medium)
        let pasteboard = UIPasteboard()
        //self.captureSession.stopRunning()
        var mailActionSheet: UIAlertController!
        if(UIDevice.current.userInterfaceIdiom == UIUserInterfaceIdiom.pad) {
            mailActionSheet = UIAlertController(title: "Email found", message: "Would you like to copy to clipboard, email \(sureURL), or share?", preferredStyle: .alert)
        } else {
            mailActionSheet = UIAlertController(title: "Email found", message: "Would you like to copy to clipboard, email \(sureURL), or share?", preferredStyle: .actionSheet)
        }
        DispatchQueue.main.async {
            
            
            
            let copyAction = UIAlertAction(title: "Copy to clipboard", style: .default) { (UIAlertAction) in
                pasteboard.string = sureURL
                let vibration = UINotificationFeedbackGenerator()
                vibration.notificationOccurred(.success)
//                self.captureSession.startRunning()
                //self.previewLayer.isHidden = false
                self.instructionLabel.text = "Copied email"
                self.instructionLabel.textColor = .systemGreen
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self.instructionLabel.textColor = .black
                    self.instructionLabel.text = "Aim camera at a URL, email, address, or phone number"
                }
                
            }
            
            let emailAction = UIAlertAction(title: "Email", style: .default) { (UIAlertAction) in
                if MFMailComposeViewController.canSendMail() {
//                self.captureSession.stopRunning()
                    self.previewLayer.isHidden = true
                let mail = MFMailComposeViewController()
                mail.mailComposeDelegate = self
                mail.setToRecipients([sureURL])
                //mail.setMessageBody("", isHTML: true)
                
                self.present(mail, animated: true)
                }
//                self.captureSession.startRunning()
                //self.previewLayer.isHidden = false
            }
            
            
            
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { (UIAlertAction) in
//                self.captureSession.startRunning()
                self.previewLayer.isHidden = false
            }
            mailActionSheet.addAction(copyAction)
            mailActionSheet.addAction(emailAction)
            if(UIDevice.current.userInterfaceIdiom == UIUserInterfaceIdiom.phone) {
                let shareAction = UIAlertAction(title: "Share", style: .default) { (UIAlertAction) in
                    let items = [sureURL]
                    let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
//                            self.captureSession.stopRunning()
                            self.previewLayer.isHidden = true
                            self.present(ac, animated: true)
                                   //When share sheet is presented, capture session stops, and the completion handler starts it when share sheet is hidden
                            ac.completionWithItemsHandler = { activity, success, items, error in
//                                self.captureSession.startRunning()
                                self.previewLayer.isHidden = false
                    }
                }
                let config = UIImage.SymbolConfiguration(weight: .semibold)
                let shareIcon = UIImage(systemName: "square.and.arrow.up", withConfiguration: config)
                shareAction.setValue(shareIcon?.withRenderingMode(.automatic), forKey: "image")
                shareAction.setValue(kCMTextMarkupAlignmentType_Left, forKey: "titleTextAlignment")
                mailActionSheet.addAction(shareAction)
            }
            //mailActionSheet.addAction(shareAction)
            mailActionSheet.addAction(cancelAction)
            
            let config = UIImage.SymbolConfiguration(weight: .semibold)
            let envelope = UIImage(systemName: "envelope", withConfiguration: config)
            let clipboard = UIImage(systemName: "doc.on.doc", withConfiguration: config)
            
            
            
            copyAction.setValue(clipboard?.withRenderingMode(.automatic), forKey: "image")
            copyAction.setValue(kCMTextMarkupAlignmentType_Left, forKey: "titleTextAlignment")
            emailAction.setValue(envelope?.withRenderingMode(.automatic), forKey: "image")
            emailAction.setValue(kCMTextMarkupAlignmentType_Left, forKey: "titleTextAlignment")
            self.present(mailActionSheet, animated: true, completion: {
                generator.impactOccurred()
                
            })
            
//            self.captureSession.startRunning()
            //self.previewLayer.isHidden = false
            
        }
    }
    
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        
        switch result.rawValue {
        case MFMailComposeResult.cancelled.rawValue:
            print("")
        default:
            self.dismiss(animated: true, completion: nil)
        }
        // Dismiss the mail compose view controller.
        self.dismiss(animated: true, completion: nil)
    }
    
    //MARK: Maps ActionSheet
    func mapsAlert(sureURL: String) {
        successfulScan()
        previewLayer.isHidden = true
        
        print("seen your house")
        var mapSheet: UIAlertController!
        let geocoder = CLGeocoder()
        let locationString = sureURL
        let pasteBoard = UIPasteboard.general
        if(UIDevice.current.userInterfaceIdiom == UIUserInterfaceIdiom.pad) {
            //generator.notificationOccurred(.success)
            mapSheet = UIAlertController(title: "Address Detected", message: "Would you like to copy the address, Get directions to \(sureURL) in maps, or share?", preferredStyle: .alert)
        } else {
            mapSheet = UIAlertController(title: "Address Detected", message: "Would you like to copy the address, Get directions to \(sureURL) in maps, or share?", preferredStyle: .actionSheet)
            
            
        }
        
        
        DispatchQueue.main.async {
            
            let copyAction = UIAlertAction(title: "Copy to clipboard", style: .default) { (UIAlertAction) in
                
                pasteBoard.string = sureURL
                
//                self.captureSession.startRunning()
                //self.previewLayer.isHidden = false
                self.instructionLabel.text = "Copied address"
                self.instructionLabel.textColor = .systemGreen
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self.instructionLabel.textColor = .black
                    self.instructionLabel.text = "Aim camera at a URL, email, address, or phone number"
                }
                //self.instructionLabel.text = "Copied address"
            }
            //Cancel action
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: { (UIAlertAction) in
//                self.captureSession.startRunning()
                self.previewLayer.isHidden = false
            })
            //Share sheet action
            
            //Map action to open address in maps
            let mapAction = UIAlertAction(title: "Get Directions in Maps", style: .default) { (UIAlertAction) in
                geocoder.geocodeAddressString(locationString) { (placemarks, error) in
                    if let error = error {
                        print(error.localizedDescription)
                    } else {
                        if let location = placemarks?.first?.location {
                           
                            let coordinate = CLLocationCoordinate2DMake(location.coordinate.latitude,location.coordinate.longitude)
                            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate, addressDictionary:nil))
                            mapItem.name = "Target location"
                            mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey : MKLaunchOptionsDirectionsModeDriving])
                            /*if let url = URL(string: urlString) {
                                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                            } */
                        }
                    }
                }
//                self.captureSession.startRunning()
                //self.previewLayer.isHidden = false
            }
            let generator = UIImpactFeedbackGenerator(style: .medium)
            //generator.impactOccurred()
            mapSheet.addAction(copyAction)
            mapSheet.addAction(mapAction)
            if(UIDevice.current.userInterfaceIdiom == UIUserInterfaceIdiom.phone) {
                let shareAction = UIAlertAction(title: "Share", style: .default) { (UIAlertAction) in
                    let items = [sureURL]
                    let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
//                                   self.captureSession.stopRunning()
                    self.previewLayer.isHidden = true
                                   self.present(ac, animated: true)
                                   //When share sheet is presented, capture session stops, and the completion handler starts it when share sheet is hidden
                                   ac.completionWithItemsHandler = { activity, success, items, error in
//                                       self.captureSession.startRunning()
                                    self.previewLayer.isHidden = false
                                   }
                }
                let config = UIImage.SymbolConfiguration(weight: .semibold)
                let shareIcon = UIImage(systemName: "square.and.arrow.up", withConfiguration: config)
                shareAction.setValue(shareIcon?.withRenderingMode(.automatic), forKey: "image")
                shareAction.setValue(kCMTextMarkupAlignmentType_Left, forKey: "titleTextAlignment")
                mapSheet.addAction(shareAction)
            }
            mapSheet.addAction(cancelAction)
            let config = UIImage.SymbolConfiguration(weight: .semibold)
            let mapIcon = UIImage(systemName: "map", withConfiguration: config)
            
            let clipboard = UIImage(systemName: "doc.on.doc", withConfiguration: config)
            //adds the symbol to copy
            copyAction.setValue(clipboard?.withRenderingMode(.automatic), forKey: "image")
            copyAction.setValue(kCMTextMarkupAlignmentType_Left, forKey: "titleTextAlignment")
            
            mapAction.setValue(mapIcon?.withRenderingMode(.automatic), forKey: "image")
            mapAction.setValue(kCMTextMarkupAlignmentType_Left, forKey: "titleTextAlignment")
//            self.captureSession.stopRunning()
            self.previewLayer.isHidden = true
            self.present(mapSheet, animated: true, completion: {
                generator.impactOccurred()
                
            })
           
        }
    }
    
    //MARK: CallAlert
    //MARK: Add actionsheet
    //Handles detected text
    //Open actionsheet then if call option is selected, then open URL
    func callAlert(sureURL: String) {
        //Get rid of tell:// from function call
        successfulScan()
        var phoneNum = ""
        let generator = UIImpactFeedbackGenerator(style: .medium)
        for x in sureURL {
            if x.isNumber {
                phoneNum += String(x)
            }
        }
        
        if let url = URL(string: "tel://" + phoneNum) {
            self.captureSession.stopRunning()
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
                generator.impactOccurred()
            }
            let notificationCenter = NotificationCenter.default
            notificationCenter.addObserver(self, selector: #selector(appMovedToBackground), name: UIApplication.didBecomeActiveNotification, object: nil)
            
            //DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: {
                //self.captureSession.startRunning()
            //})
        }
        
        
            
    }
    //MARK: Sucessful scan
    func successfulScan() {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.25) {
                self.roiView.layer.borderColor = UIColor.systemGreen.cgColor
            }
            
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            UIView.animate(withDuration: 0.25) {
                self.roiView.layer.borderColor = UIColor.systemTeal.cgColor
            }
            //self.roiView.layer.borderColor = UIColor.systemTeal.cgColor
        }
    }
    
    //MARK: URL Popup
    func alertPopUp(sureURL: String) {
        successfulScan()
        previewLayer.isHidden = true
        //Medium haptic when popup occurs
        let generator = UIImpactFeedbackGenerator(style: .medium)
        //For writing to clipboard
        let pasteBoard = UIPasteboard.general
        //If device is an iPad, use alert instead of actionsheet
        if(UIDevice.current.userInterfaceIdiom == UIUserInterfaceIdiom.pad) {
            let alert = UIAlertController(title: "Website found", message: "Go to \(sureURL)?", preferredStyle: .alert)
            
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: { (UIAlertAction) in
                //self.captureSession.startRunning()
                self.previewLayer.isHidden = false
            })
            let copyAction = UIAlertAction(title: "Copy to clipboard", style: .default, handler: { (UIAlertAction) in
            
                pasteBoard.string = sureURL
                self.instructionLabel.textAlignment = .center
                self.instructionLabel.textColor = UIColor.systemGreen
                self.instructionLabel.text = "Copied URL"
                //Haptic when link is copied
                let vibration = UINotificationFeedbackGenerator()
                vibration.notificationOccurred(.success)
                //self.captureSession.startRunning()
                self.previewLayer.isHidden = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self.instructionLabel.textColor = .black
                    self.instructionLabel.text = "Aim camera at a URL, email, phone number, or address"
                }
            })
            
            let siteAction = UIAlertAction(title: "Open link in Safari", style: .default, handler: { (UIAlertAction) in
                
                if(sureURL.hasPrefix("http://") || sureURL.hasPrefix("https://")) {
                    if let url = URL(string: sureURL) {
                            DispatchQueue.main.async {UIApplication.shared.open(url)
                        }
                    }
                }else if let url = URL(string: "https://" + sureURL) {
                        print("in second loop")
                    DispatchQueue.main.async {UIApplication.shared.open(url)
                    }
                }
                //self.captureSession.startRunning()
                self.previewLayer.isHidden = false
            })
            let config = UIImage.SymbolConfiguration(weight: .semibold)
            let clipboard = UIImage(systemName: "doc.on.doc", withConfiguration: config)
            let safari = UIImage(systemName: "safari", withConfiguration: config)
            
            
            siteAction.setValue(safari?.withRenderingMode(.automatic), forKey: "image")
            siteAction.setValue(kCMTextMarkupAlignmentType_Left, forKey: "titleTextAlignment")
    
            //adds the symbol to copy
            copyAction.setValue(clipboard?.withRenderingMode(.automatic), forKey: "image")
            copyAction.setValue(kCMTextMarkupAlignmentType_Left, forKey: "titleTextAlignment")
            alert.addAction(copyAction)
            alert.addAction(siteAction)
            alert.addAction(cancelAction)
            DispatchQueue.main.async {
                //self.captureSession.stopRunning()
                self.previewLayer.isHidden = true
                self.present(alert, animated: true)
            }
        } else {
            
        DispatchQueue.main.async {
            //self.captureSession.stopRunning()
            self.previewLayer.isHidden = false
            let alert = UIAlertController(title: "Website found", message: "Would you like to copy URL, go to \(sureURL), or share?", preferredStyle: .actionSheet)
            let copyAction = UIAlertAction(title: "Copy to clipboard", style: .default, handler: { (UIAlertAction) in
            
                pasteBoard.string = sureURL
                self.instructionLabel.textAlignment = .center
                self.instructionLabel.textColor = UIColor.systemGreen
                self.instructionLabel.text = "Copied URL"
                //Haptic when link is copied
                let vibration = UINotificationFeedbackGenerator()
                vibration.notificationOccurred(.success)
                self.captureSession.startRunning()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self.instructionLabel.textColor = .black
                    self.instructionLabel.text = "Aim camera at a URL, email, phone number, or address"
                }
            })
            //comfigures symbol size
            let config = UIImage.SymbolConfiguration(weight: .semibold)
            let clipboard = UIImage(systemName: "doc.on.doc", withConfiguration: config)
            let safari = UIImage(systemName: "safari", withConfiguration: config)
            //adds the symbol to copy
            copyAction.setValue(clipboard?.withRenderingMode(.automatic), forKey: "image")
            copyAction.setValue(kCMTextMarkupAlignmentType_Left, forKey: "titleTextAlignment")
        
            //Site action button
            let siteAction = UIAlertAction(title: "Open link in Safari", style: .default, handler: { (UIAlertAction) in
                
                if(sureURL.hasPrefix("http://") || sureURL.hasPrefix("https://")) {
                    if let url = URL(string: sureURL) {
                            DispatchQueue.main.async {UIApplication.shared.open(url)
                        }
                    }
                }else if let url = URL(string: "https://" + sureURL) {
                        print("in second loop")
                    DispatchQueue.main.async {UIApplication.shared.open(url)
                    }
                }
                //self.captureSession.startRunning()
                self.previewLayer.isHidden = false
            })
            siteAction.setValue(safari?.withRenderingMode(.automatic), forKey: "image")
            siteAction.setValue(kCMTextMarkupAlignmentType_Left, forKey: "titleTextAlignment")
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: { (UIAlertAction) in
                //self.captureSession.startRunning()
                self.previewLayer.isHidden = false
            })
            
            let shareAction = UIAlertAction(title: "Share", style: .default, handler: { (UIAlertAction) in
                var items: [URL]
                if(!sureURL.hasPrefix("http://") || !sureURL.hasPrefix("https://")) {
                    let newURL = "https://" + sureURL
                    items = [URL(string: newURL)!]
                } else {
                    items = [URL(string: sureURL)!]
                }
                //share sheet controller
                let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
                //self.captureSession.stopRunning()
                self.previewLayer.isHidden = false
                self.present(ac, animated: true)
                //When share sheet is presented, capture session stops, and the completion handler starts it when share sheet is hidden
                ac.completionWithItemsHandler = { activity, success, items, error in
                    //self.captureSession.startRunning()
                    self.previewLayer.isHidden = false
                }
                //self.captureSession.startRunning()
            })
        
            let shareIcon = UIImage(systemName: "square.and.arrow.up", withConfiguration: config)
            shareAction.setValue(shareIcon?.withRenderingMode(.automatic), forKey: "image")
            shareAction.setValue(kCMTextMarkupAlignmentType_Left, forKey: "titleTextAlignment")
            
            alert.addAction(copyAction)
            alert.addAction(siteAction)
            alert.addAction(shareAction)
            alert.addAction(cancelAction)
            
            self.present(alert, animated: true, completion: {
                generator.impactOccurred()
            })
        }
        }
    }
    //Test
    //MARK: Text Detection
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
                    let regex = try! NSRegularExpression(pattern: "((?:http|https)://)?(?:www\\.)?[\\w\\d\\-_]+\\.\\w{2,3}(\\.\\w{2})?(/(?<=/)(?:[\\w\\d\\-./_]+)?)?")
                    //Old regex: (?i)https?://(?:www\\.)?\\S+(?:/|\\b)
                    //If the same URL is seen multiple times, it checks if the URL
                    //Matches the Regular Expression, if it does, opens detected URL in safari
                    if let sureURL = numberTracker.getStableString() {
                        let tokenString = sureURL.components(separatedBy: " ")
                        if(sureURL.isValidAddress) {
                            mapsAlert(sureURL: sureURL)
                        }
                        
                        for item in tokenString {
                            if(item.isValidAddress) {
                                mapsAlert(sureURL: item)
                            }
                            
                            if(item.isValidEmail && item.contains("@")){
                                emailAlert(sureURL: item)
                            }
                            
                            if(item.isValidPhone) {
                                print("Found Phone Number")
                                callAlert(sureURL: item)
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                            }
                            
                            if(item.isValidURL && !item.contains("@")){
                                
                                if(item.hasPrefix("http://")) {
                                    alertPopUp(sureURL: item)
                                } else if(item.hasPrefix("https://")) {
                                    alertPopUp(sureURL: item)
                                } else {
                                    alertPopUp(sureURL: item)
                                }
                                print("Valid url: \(item)")
                            }
                            
                        }
                        numberTracker.reset(string: sureURL)
                        

                            
                    }
                    //print(observation.boundingBox)
                    if(text.string.isValidAddress) {
                        urls.append(text.string)
                    }
                    if(text.string.isValidPhone) {
                        urls.append(text.string)
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
        //Logs seen URLs
        numberTracker.logFrame(strings: urls)
    }
    //MARK: Zoom Button Action
    @objc func buttonAction(sender: UIButton!) {
        //buttonCounter counts the amount of times the zoom button is pressed
        //Every second press it will go back to 1x zoom, otherwise will go to 2x zoom
        buttonCounter += 1
        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .back) else {return}
        if(buttonCounter % 2 == 0) {
            zoomButton.setTitle("2x", for: .normal)
            do {
                try captureDevice.lockForConfiguration()
                captureDevice.videoZoomFactor = 1
                captureDevice.autoFocusRangeRestriction = .near
                captureDevice.unlockForConfiguration()
            } catch {
                print("Could not set zoom level due to error: \(error)")
                    return
            }
        } else {
            zoomButton.setTitle("1x", for: .normal)
            do {
                try captureDevice.lockForConfiguration()
                captureDevice.videoZoomFactor = 2
                captureDevice.autoFocusRangeRestriction = .near
                captureDevice.unlockForConfiguration()
            } catch {
                print("Could not set zoom level due to error: \(error)")
                    return
            }
        }
    }
    
    //MARK: ViewDidLoad
    override func viewDidLoad() {
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        super.viewDidLoad()
        request = VNRecognizeTextRequest(completionHandler: detectedTextHandler)
        
        // Do any additional setup after loading the view.
        maskLayer.backgroundColor = UIColor.clear.cgColor
        maskLayer.fillRule = .evenOdd
        //Sets the text request settings
        request.recognitionLevel = VNRequestTextRecognitionLevel.fast
        if #available(iOS 14.0, *) {
            request.revision = VNRecognizeTextRequestRevision2
        } else {
            // Fallback on earlier versions
            request.revision = VNRecognizeTextRequestRevision1
        }
        request.usesLanguageCorrection = true
        request.regionOfInterest = regionOfInterest
        
        //Sets up camera after vision requests
        setupCamera()
        
        //Zoom button setup and constraints
        view.addSubview(zoomButton)
        zoomButton.translatesAutoresizingMaskIntoConstraints = false
        zoomButton.setTitle("2x", for: .normal)
        zoomButton.backgroundColor = UIColor.black
        zoomButton.setTitleColor(.white, for: .normal)
        zoomButton.layer.borderWidth = 3
        zoomButton.layer.borderColor = UIColor.white.cgColor
        zoomButton.clipsToBounds = true
        zoomButton.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        zoomButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -150).isActive = true
        zoomButton.widthAnchor.constraint(equalToConstant: 50).isActive = true
        zoomButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        zoomButton.layer.cornerRadius = 25
        zoomButton.addTarget(self, action: #selector(buttonAction), for: .touchUpInside)
        view.bringSubviewToFront(zoomButton)
        
        //User directions label setup and constraints
        
        view.addSubview(instructionLabel)
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0
        instructionLabel.lineBreakMode = .byWordWrapping
//        instructionLabel.shadowColor = .black
//        instructionLabel.layer.shadowColor = UIColor.black.cgColor
//        instructionLabel.layer.shadowRadius = 3.0
//        instructionLabel.layer.shadowOpacity = 1.0
//        instructionLabel.layer.shadowOffset = CGSize(width: 4, height: 4)
        instructionLabel.layer.masksToBounds = false
        instructionLabel.text = "Aim the camera at a URL, email, phone number, or address."
        instructionLabel.textColor = .black
        instructionLabel.font = .systemFont(ofSize: 18)
        instructionLabel.backgroundColor = .white
        instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        instructionLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 100).isActive = true
        instructionLabel.textAlignment = .center
//        instructionLabel.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
//        instructionLabel.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        instructionLabel.heightAnchor.constraint(equalToConstant: 60).isActive = true
        instructionLabel.widthAnchor.constraint(equalToConstant: 300).isActive = true
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.layer.cornerRadius = 30
        instructionLabel.layer.masksToBounds = true

        
        
        
    }
    
    @objc func appMovedToBackground() {
        print("App moved to background!")

        captureSession.startRunning()
    }
    
    //MARK: ViewWillTransition
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
    //MARK: ViewWillAppear
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        print("Coming back")
        //captureSession.beginConfiguration()
        //captureSession.addInput(inputs[0])
        previewLayer.isHidden = false
        captureSession.startRunning()
    }
    
    //MARK: ViewWillDisappear
    //Tries to stop running when the view will go away, not working for some reason
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DispatchQueue.main.async {
            self.captureSession.stopRunning()
            
        }
        previewLayer.isHidden = true
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        print("Live view gone")
        print("capture session is running after gone: \(captureSession.isRunning)")
        
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("We back")
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
