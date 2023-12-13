//
//  Metadata.swift
//  ScanKit
//
//  Created by 张裕阳 on 2023/3/14.
//

import Foundation
import UIKit

class DeviceInfo: Codable {
    private var id: String
    private var type: String
    private var name: String
    
    internal init(id: String, type: String, name: String) {
        self.id = id
        self.type = type
        self.name = name
    }
}

class UserInfo: Codable {
    private var name: String
    
    internal init(name: String) {
        self.name = name
    }
}

class SceneInfo: Codable {
    private var description: String
    private var type: String
    private var gpsLocation: [Double]
    
    internal init(description: String, type: String, gpsLocation: [Double]) {
        self.description = description
        self.type = type
        self.gpsLocation = gpsLocation
    }
}

class StreamInfo: Codable {
    private var id: String
    private var type: String
    private var encoding: String
    private var frequency: Int
    private var numberOfFrames: Int
    private var fileExtension: String
    
    internal init(id: String, type: String, encoding: String, frequency: Int, numberOfFrames: Int, fileExtension: String) {
        self.id = id
        self.type = type
        self.encoding = encoding
        self.frequency = frequency
        self.numberOfFrames = numberOfFrames
        self.fileExtension = fileExtension
    }
}

class CameraStreamInfo: StreamInfo {
    private var resolution: [Int]
    private var intrinsics: [Float]?
    private var extrinsics: [Float]?
    
    internal init(id: String, type: String, encoding: String, frequency: Int, numberOfFrames: Int, fileExtension: String, resolution: [Int], intrinsics: [Float]?, extrinsics: [Float]?) {
        self.resolution = resolution
        self.intrinsics = intrinsics
        self.extrinsics = extrinsics
        super.init(id: id, type: type, encoding: encoding, frequency: frequency, numberOfFrames: numberOfFrames, fileExtension: fileExtension)
    }
    
    required init(from decoder: Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }
    
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(resolution, forKey: .resolution)
        try container.encode(intrinsics, forKey: .intrinsics)
        try container.encode(extrinsics, forKey: .extrinsics)
    }
    
    enum CodingKeys: String, CodingKey {
        case resolution
        case intrinsics
        case extrinsics
    }
}

class Metadata: Encodable {
    private var device: DeviceInfo
    private var user: UserInfo
    private var scene: SceneInfo
    private var streams: [StreamInfo]
    private var numberOfFiles: Int
    private var depthConfidenceAvaliable: Bool
    private var cameraOrientationQuaternionFormat: String
    private var cameraOrientationEulerAnglesFormat: String
    private var depthUnit: String
    private var depthConfidenceValueRange: [Int]
    
    init(username: String, userInputDescription: String, sceneType: String, gpsLocation: [Double],
         streams: [StreamInfo], numberOfFiles: Int) {
        
        let deviceId = UIDevice.current.identifierForVendor?.uuidString
        let modelName = Helper.getDeviceModelCode()
        let deviceName = UIDevice.current.name
        
        device = .init(id: deviceId!, type: modelName, name: deviceName)
        user = .init(name: username)
        scene = .init(description: userInputDescription, type: sceneType, gpsLocation: gpsLocation)
        
        self.streams = streams
        self.numberOfFiles = numberOfFiles
        self.depthConfidenceAvaliable = true
        self.cameraOrientationQuaternionFormat = "wxyz"
        self.cameraOrientationEulerAnglesFormat = "xyz"
        self.depthConfidenceValueRange = [0, 2]
        self.depthUnit = "m"
    }
    
    func display() {
        print(self.getJsonEncoding())
    }
    
    func writeToFile(filepath: String) {
        try! self.getJsonEncoding().write(toFile: filepath, atomically: true, encoding: .utf8)
    }
    
    func getJsonEncoding() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.keyEncodingStrategy = .convertToSnakeCase
        
        let data = try! encoder.encode(self)
        return String(data: data, encoding: .utf8)!
    }
}

