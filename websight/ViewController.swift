//
//  ViewController.swift
//  websight
//
//  Created by Evan Nemetz on 7/11/19.
//  Copyright © 2019 Evan Nemetz. All rights reserved.
//
import UIKit
import Vision
import AVFoundation
import SafariServices
import CoreLocation
import MapKit
import MessageUI
import CallKit

class ViewController: UITabBarController{
    
    let currentOrientation = UIDeviceOrientation.portrait
    let firstViewController = DetectionViewController()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        firstViewController.tabBarItem = UITabBarItem(title: "Live Scan", image: UIImage(systemName: "doc.text.viewfinder"), tag: 0)

        let secondViewController = FullCaptureViewController()

        secondViewController.tabBarItem = UITabBarItem(title: "Image Scan", image: UIImage(systemName: "photo"), tag: 1)

        let tabBarList = [firstViewController, secondViewController]
        
        setViewControllers(tabBarList, animated: true)
        

        //self.viewControllers = tabBarList
        
        
        
        
        
    }
    
    override func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        print("Selected Index :\(self.selectedIndex)")
        if(self.selectedIndex == 1) {
            firstViewController.dismiss(animated: true)
            firstViewController.captureSession.stopRunning()
            
        }
        
        

//        } else {
//            fuck.previewLayer.isHidden = false
//        }
    }
    
    
    override open var shouldAutorotate: Bool {
       return false
    }

    // Specify the orientation.
    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
       return .portrait
    }
}
