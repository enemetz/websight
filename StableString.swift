//
//  StableString.swift
//  websight
//
//  Created by Evan Nemetz on 7/29/19.
//  Copyright © 2019 Evan Nemetz. All rights reserved.
//

import Foundation

extension String {
    func regexMatch(string: String) {
        let range = NSRange(location: 0, length: string.utf16.count)
        let regex = try! NSRegularExpression(pattern: "((?:http|https)://)?(?:www\\.)?[\\w\\d\\-_]+\\.\\w{2,3}(\\.\\w{2})?(/(?<=/)(?:[\\w\\d\\-./_]+)?)?")
        if(regex.firstMatch(in: string, options: [], range: range) != nil) {
                
        }
    }
    var isValidURL: Bool {
        let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        if let match = detector.firstMatch(in: self, options: [], range: NSRange(location: 0, length: self.utf16.count)) {
            // it is a link, if the match covers the whole string
            return match.range.length == self.utf16.count
        } else {
            return false
        }
        
    }
    
    var isValidAddress: Bool {
        let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)
        if let match = detector.firstMatch(in: self, options: [], range: NSRange(location: 0, length: self.utf16.count)) {
            return match.range.length == self.utf16.count
        } else {
            return false
        }
        
        
        
    }
    
    var isValidPhone: Bool {
       let regularExpressionForPhone = #"""
       (?x)                    # Verbose regex, allows comments
       (?:\+1-?)?                # Potential international prefix, may have -
       [(]?                    # Potential opening (
       \b(\w{3})                # Capture xxx
       [)]?                    # Potential closing )
       [\ -./]?                # Potential separator
       (\w{3})                    # Capture xxx
       [\ -./]?                # Potential separator
       (\w{4})\b                # Capture xxxx
       """#
        
       let testPhone = NSPredicate(format:"SELF MATCHES %@", regularExpressionForPhone)
       print(testPhone.evaluate(with: self))
       return testPhone.evaluate(with: self)
    }
    
    var isValidEmail: Bool {
       let regularExpressionForEmail = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
       let testEmail = NSPredicate(format:"SELF MATCHES %@", regularExpressionForEmail)
       return testEmail.evaluate(with: self)
    }
    
}
class StringTracker {
    var frameIndex: Int64 = 0

    typealias StringObservation = (lastSeen: Int64, count: Int64)
    
    // Dictionary of seen strings. Used to get stable recognition before
    // displaying anything.
    var seenStrings = [String: StringObservation]()
    var bestCount = Int64(0)
    var bestString = ""

    func logFrame(strings: [String]) {
        for string in strings {
            if seenStrings[string] == nil {
                seenStrings[string] = (lastSeen: Int64(0), count: Int64(-1))
            }
            seenStrings[string]?.lastSeen = frameIndex
            seenStrings[string]?.count += 1
            print("Seen \(string) \(seenStrings[string]?.count ?? 0) times")
        }
    
        var obsoleteStrings = [String]()

        // Go through strings and prune any that have not been seen in while.
        // Also find the (non-pruned) string with the greatest count.
        for (string, obs) in seenStrings {
            // Remove previously seen text after 30 frames (~1s).
            if obs.lastSeen < frameIndex - 30 {
                obsoleteStrings.append(string)
            }
            
            // Find the string with the greatest count.
            let count = obs.count
            if !obsoleteStrings.contains(string) && count > bestCount {
                bestCount = Int64(count)
                bestString = string
            }
        }
        // Remove old strings.
        for string in obsoleteStrings {
            seenStrings.removeValue(forKey: string)
        }
        
        frameIndex += 1
    }
    
    func getStableString() -> String? {
        // Require the recognizer to see the same string at least 10 times.
        if bestCount >= 9 {
            return bestString
        } else {
            return nil
        }
    }
    
    func reset(string: String) {
        seenStrings.removeValue(forKey: string)
        bestCount = 0
        bestString = ""
    }
    
    
}
