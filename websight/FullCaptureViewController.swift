//
//  FullCaptureViewController.swift
//  websight
//
//  Created by Evan Nemetz on 8/27/20.
//  Copyright © 2020 Evan Nemetz. All rights reserved.
//

import Foundation
import UIKit
import Vision

class FullCaptureViewController: UIViewController, UIImagePickerControllerDelegate & UINavigationControllerDelegate, UITextViewDelegate {
    
    var textField = UITextView()
    var imageView = UIImageView()
    let addPhotoButton = UIButton()
    let instructionView = UILabel()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        weak var cameraView = DetectionViewController()
        cameraView?.captureSession.stopRunning()
        instructionView.text = "Select an image to extract text from"
        view.addSubview(instructionView)
        view.addSubview(imageView)
        
        //view.addSubview(addPhotoButton)
        view.addSubview(textField)
        setUpUI()
        
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        let cameraView = DetectionViewController()
        cameraView.captureSession.stopRunning()
    }
    
    @objc func addPhotoButtonTapped(sender: UITapGestureRecognizer) {
        print("In photo tap")
        let vc = UIImagePickerController()
        vc.sourceType = .photoLibrary
        vc.allowsEditing = true
        vc.delegate = self
        present(vc, animated: true)

    }
    
    //Sets up the UI components
    private func setUpUI() {
        let tapGR = UITapGestureRecognizer(target: self, action: #selector(self.addPhotoButtonTapped))
        imageView.addGestureRecognizer(tapGR)
        imageView.isUserInteractionEnabled = true
        imageView.image = UIImage(named: "ScanImageDefault")
        imageView.layer.cornerRadius = 20
        imageView.layer.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        imageView.bottomAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        imageView.widthAnchor.constraint(equalToConstant: 250).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 250).isActive = true
        
        //Add photo button contraints
//        addPhotoButton.setTitle("Scan photo", for: .normal)
//        addPhotoButton.backgroundColor = .systemBlue
//        addPhotoButton.layer.cornerRadius = 10
//
//        addPhotoButton.translatesAutoresizingMaskIntoConstraints = false
//        addPhotoButton.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
//        addPhotoButton.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 50).isActive = true
//        addPhotoButton.widthAnchor.constraint(equalToConstant: 200).isActive = true
//        addPhotoButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
//
//        addPhotoButton.addTarget(self, action: #selector(addPhotoButtonTapped), for: .touchUpInside)
//        view.bringSubviewToFront(addPhotoButton)
        
        //Textfield Contraints
        textField.backgroundColor = .black
        textField.textColor = .white
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        textField.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        textField.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 25).isActive = true
        textField.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0).isActive = true
        textField.font = UIFont(name: "Helvetica" , size: 20)
        textField.textAlignment = .center
        textField.delegate = self
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        guard let image = info[.editedImage] as? UIImage else {
            return
        }
        setUpImageView(image: image)
        detectText(image: image)
        
        dismiss(animated: true)
    }
    
    func detectText(image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        let requestHandler = VNImageRequestHandler(cgImage: cgImage)
        
        let request = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        do {
            // Perform the text-recognition request.
            try requestHandler.perform([request])
        } catch {
            print("Unable to perform the requests: \(error).")
        }
        
        
    }
    
    func recognizeTextHandler(request: VNRequest?, error: Error?) {
        
        guard let observations =
                request?.results as? [VNRecognizedTextObservation] else {
            return
        }
        let recognizedStrings = observations.compactMap { observation in
            // Return the string of the top VNRecognizedText instance.
            return observation.topCandidates(1).first?.string
        }
        
        processStrings(recognizedStrings: recognizedStrings)
        
        // Process the recognized strings.
        print(recognizedStrings)
        
    
    
        
    }
    
    func setUpImageView(image: UIImage) {
        DispatchQueue.main.async {
            if self.imageView.image == UIImage(named: "ScanImageDefault") {
                self.imageView.bottomAnchor.constraint(equalTo: self.view.topAnchor, constant: 325).isActive = true
                self.imageView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor).isActive = true
                self.imageView.widthAnchor.constraint(equalToConstant: 250).isActive = true
                self.imageView.heightAnchor.constraint(equalToConstant: 250).isActive = true
                self.imageView.image = image
            } else {
                self.imageView.image = image
            }
            
        }
    }
    
    func processStrings(recognizedStrings: [String]) {
//        var text = ""
//
//        for string in recognizedStrings {
//            text = "" + string
//            print(string)
//        }
        
        DispatchQueue.main.async {
            self.textField.text = recognizedStrings.joined(separator: " ")
        }
    }
    
    func getDocumentDirectory() -> URL{
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if(text == "\n") {
                textView.resignFirstResponder()
                return false
            }
            return true
        }
    
}
