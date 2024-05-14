//
//  ViewController.swift
//  artest
//
//  Created by 张裕阳 on 2022/9/22.
//

import Foundation
import UIKit
import ARKit
import NearbyInteraction
import MultipeerConnectivity
import RealityKit
import SwiftUI
import SceneKit
import SceneKit.ModelIO

@available(iOS 16.0, *)
class ViewController: UIViewController, NISessionDelegate, ARSessionDelegate, ARSCNViewDelegate {
    // scene
    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var panelView: UIView!
    
    // labels
    @IBOutlet weak var deviceLable: UILabel!
    @IBOutlet weak var infoLabel: UILabel!
    @IBOutlet weak var lightingIntensityLabel: UILabel!
    @IBOutlet weak var motionLabel: UILabel!
    @IBOutlet weak var featureLabel: UILabel!
    
    // button
    @IBOutlet weak var flashlightButton: UIButton!
    @IBOutlet weak var panelButton: UIButton!
    
    let coachingOverlayView = ARCoachingOverlayView()
    
    // Nearby Interaction
    var niSession: NISession?
    var peerDiscoveryToken: NIDiscoveryToken?
    var sharedTokenWithPeers = false
    var currentState: DistanceDirectionState = .unknown
    enum DistanceDirectionState {
        case unknown, closeUpInFOV, notCloseUpInFOV, outOfFOV
    }
    
    // Multipeer Connectivity
    var mpc: MPCSession?
    var connectedPeer: MCPeerID?
    var peerDisplayName: String?
    var peerSessionIDs = [MCPeerID: String]()
    var sessionIDObservation: NSKeyValueObservation?
    
    // Conditional variables
    var alreadyAdd = false
    var couldDetect = true
    private var isRecording = false
    private var isPanelShowing = false
    private var isFirstFrame = false
    private var detectTimeInterval = 0
    
    // ARKit & mathematical variables
    var camera: ARCamera?
    var currentFrame: ARFrame?
    var peerWorldTransFromARKit: simd_float4x4?
    var anchorFromPeer: ARAnchor?
    var eularAngle: simd_float3?
    var peerEulerangle: simd_float3?
    var peerDirection: simd_float3?
    var peerDistance: Float?
    
    // Data collection variables
    private let featureQueue = DispatchQueue(label: "feature")
    private let collectorQUeue = DispatchQueue(label: "collector")
    private let saveQueue = DispatchQueue(label: "save")

    private var frameNum: Int = 0
    private let dataCollector = DataCollector()
    private var featureSensor: FeatureSensor?
    private var envCollector: EnvDataCollector?
    private var cmManager: CMManager!
    private var timeStampAlignment: TimeStampAlignment!
    
    // Custom UI components
    private let recordingButton: UIButton = {
        let button = UIButton()
        button.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        button.layer.cornerRadius = 40
        button.backgroundColor = .white
        
        let circleLayer = CALayer()
        circleLayer.backgroundColor = UIColor.green.cgColor
        circleLayer.cornerRadius = 20
        circleLayer.frame = CGRect(x: 20, y: 20, width: 40, height: 40)
        
        button.layer.addSublayer(circleLayer)
        button.addTarget(self, action: #selector(ViewController.hitRecordingButton), for: .touchUpInside)
        return button
    }()
    private let projectButton: UIButton = {
        let button = UIButton()
        button.frame = CGRect(x: 0, y: 0,
                              width: 120, height: 50)
        button.layer.cornerRadius = 10
        button.backgroundColor = .white
        button.setTitleColor(.black, for: .normal)
        button.setTitle("Files", for: .normal)
        button.addTarget(self, action: #selector(ViewController.projectMenu), for: .touchUpInside)
        return button
    }()
    private let deleteAllDataButton: UIButton = {
        let button = UIButton()
        button.frame = CGRect(x: 0, y: 0, width: 150, height: 30)
        button.layer.cornerRadius = 10
        button.backgroundColor = .white
        button.setTitleColor(.black, for: .normal)
        button.setTitle("Delete Data", for: .normal)
        button.addTarget(self, action: #selector(ViewController.clearTempFolder), for: .touchUpInside)
        return button
    }()
    private let clearARObjButton: UIButton = {
        let button = UIButton()
        button.frame = CGRect(x: 0, y: 0, width: 80, height: 30)
        button.layer.cornerRadius = 10
        button.backgroundColor = .white
        button.setTitleColor(.black, for: .normal)
        button.setTitle("Clear", for: .normal)
        button.addTarget(self, action: #selector(ViewController.removeAllAnchorsYouCreated), for: .touchUpInside)
        return button
    }()
    private let lightSensorSwitch: UISwitch = {
        let sw = UISwitch()
        sw.frame = CGRect(x: 0, y: 0, width: 80, height: 40)
        sw.isOn = true
        return sw
    }()
    private let lightSensorLabel: UILabel = {
        let label = UILabel()
        label.frame = CGRect(x: 0,
                             y: 0,
                             width: 80,
                             height: 40)
        label.textColor = .black
        label.backgroundColor = .white
        label.layer.cornerRadius = 10
        return label
    }()
    private let featurePointLabel: UILabel = {
        let label = UILabel()
        label.frame = CGRect(x: 0,
                             y: 0,
                             width: 250,
                             height: 40)
        label.textColor = .black
        label.backgroundColor = .white
        label.layer.cornerRadius = 10
        return label
    }()
    
    private var circleLayer: CALayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        startup()
        ScanConfig.viewportsize = view.bounds.size
        envCollector = EnvDataCollector(vc: self)
        featureSensor = FeatureSensor(featurePointNum: 0, viewController: self)
        timeStampAlignment = TimeStampAlignment()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        //make sure support arworldtracking
        guard ARWorldTrackingConfiguration.isSupported else {
            Logger.shared.debugPrint("Error 1: This device doesn't support AR world tracking function")
            fatalError("do not support ar world tracking")
        }
        
        //set ARSession
        //niSession?.setARSession(sceneView.session)
        
        //set delegate
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = false
        sceneView.autoenablesDefaultLighting = true
//        sceneView.allowsCameraControl = true
        //start ar session
        
        // 设置AR世界跟踪方式
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.isCollaborationEnabled = true
        configuration.environmentTexturing = .automatic
        configuration.planeDetection = .horizontal
        configuration.isLightEstimationEnabled = true
        
        if ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth]) {
            ScanConfig.supportLidar = true
            Logger.shared.debugPrint("This device supports Lidar.")
        }
        else {
            Logger.shared.debugPrint("This device doesn't support Lidar.")
        }
        // 启动AR会话
        sceneView.session.run(configuration)
        
        Logger.shared.debugPrint("AR session started.")
        
        //show feature points in ar experience, usually not used
        //sceneView.debugOptions = ARSCNDebugOptions.showFeaturePoints
        
        // 自动辅助界面
        setupCoachingOverlay()
        
        
        //disable idletimer cause user may not touch screen for a long time
        // 防止熄屏
        UIApplication.shared.isIdleTimerDisabled = true
        
        // AR会话ID发送给同伴
        sessionIDObservation = observe(\.sceneView.session.identifier, options: [.new]) { object, change in
            print("SessionID changed to: \(change.newValue!)")
            // Tell all other peers about your ARSession's changed ID, so
            // that they can keep track of which ARAnchors are yours.
            guard let multipeerSession = self.mpc else { return }
            self.sendARSessionIDTo(peers: multipeerSession.connectedPeers)
        }
        
        let serialQueue = DispatchQueue(label: "serialQueue")
        
        // UI
        self.view.addSubview(recordingButton)
        self.view.addSubview(projectButton)
        self.view.addSubview(deleteAllDataButton)
        self.view.addSubview(clearARObjButton)
//        self.view.addSubview(lightSensorSwitch)
//        self.view.addSubview(featurePointLabel)
//        self.view.addSubview(lightSensorLabel)
        
        circleLayer = recordingButton.layer.sublayers?.first(where: { $0 is CALayer }) as? CALayer
        
        // IMU 采集
        cmManager = CMManager(viewController: self)
        cmManager.startJudgingMotionState()
        
        // 进入 frame didupdate 主循环
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        //suspend session
        sceneView.session.pause()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // https://stackoverflow.com/questions/24084941/how-to-get-device-width-and-height
        recordingButton.frame = CGRect(x: UIScreen.main.bounds.size.width/2-40,
                                       y: UIScreen.main.bounds.size.height*3/4,
                                       width: 80, height: 80)
        recordingButton.addSinkAnimation()
        projectButton.frame = CGRect(x: 280,
                                     y: UIScreen.main.bounds.size.height*3/4,
                                     width: 80, height: 40)
        projectButton.addSinkAnimation()
        deleteAllDataButton.frame = CGRect(x: 30,
                                           y: 80,
                                           width: 150,
                                           height: 40)
        deleteAllDataButton.addSinkAnimation()
        clearARObjButton.frame = CGRect(x: 280,
                                        y: 80,
                                        width: 80,
                                        height: 40)
        clearARObjButton.addSinkAnimation()
        lightSensorSwitch.frame = CGRect(x: 30,
                                         y: 100,
                                         width: 80,
                                         height: 40)
        lightSensorLabel.frame = CGRect(x: 80,
                                        y: 100,
                                        width: 100,
                                        height: 40)
        featurePointLabel.frame = CGRect(x: 40,
                                         y: 160,
                                         width: 250,
                                         height: 40)
        panelButton.addSinkAnimation()
        panelView.layer.cornerRadius = 30
    }
    
    
    func startup() {
        //create Session
        if niSession == nil {
            niSession = NISession()
            print("create NIsession")
            
            //set a delegate
            niSession?.delegate = self
            sharedTokenWithPeers = false
        }
        
        if mpc == nil {
            startupMPC()
            currentState = .unknown
        }
        
        if mpc != nil && connectedPeer != nil {
            startupNI()
        }
    }
    
    func startupMPC() {
        if mpc == nil {
            #if targetEnvironment(simulator)
            mpc = MPCSession(service: "zyy-artest",
                             identity: "zyy-artest.simulator",
                             maxPeers: 1)
            #else
            mpc = MPCSession(service: "zyy-artest",
                             identity: "zyy-artest.realdevice",
                             maxPeers: 1)
            #endif
            mpc?.peerConnectedHandler = connectedToPeer
            mpc?.peerDisConnectedHandler = disconnectedToPeer
            mpc?.peerDataHandler = dataReceiveHandler
        }
        mpc?.invalidate()
        mpc?.start()
    }
    
    func startupNI() {
        //create a session
        if let mytoken = niSession?.discoveryToken {
            //share your token
            if !sharedTokenWithPeers {
                shareTokenWithPeers(token: mytoken)
                print("share token!")
            }
            
            //make sure have peerToken
            guard let peerToken = peerDiscoveryToken else {
                return
            }
            
            // set config
            let configuration = NINearbyPeerConfiguration(peerToken: peerToken)
            configuration.isCameraAssistanceEnabled = false
        
            //run session
            niSession?.run(configuration)
            print("welldone")
            
            
        } else {
            fatalError("Could not catch your token.")
        }
    }
    
    //handler of connection
    func connectedToPeer(peer: MCPeerID) {
        guard let myToken = niSession?.discoveryToken else {
            fatalError("Can not find your token while connecting")
        }
        if connectedPeer != nil {
            fatalError("already connected")
        }
        if !sharedTokenWithPeers {
            shareTokenWithPeers(token: myToken)
        }
        connectedPeer = peer
        peerDisplayName = peer.displayName
        DispatchQueue.main.async {
            self.deviceLable.text = "Peer's Name:" + peer.displayName
        }
    }
    
    //handle to disconnect
    func disconnectedToPeer(peer: MCPeerID) {
        if connectedPeer == peer {
            connectedPeer = nil
            sharedTokenWithPeers = false
        }
    }
    
    //share token
    func shareTokenWithPeers(token: NIDiscoveryToken) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            fatalError("cannot encode your token")
        }
        self.mpc?.sendDataToAllPeers(data: data)
        sharedTokenWithPeers = true
    }
    
    //put new anchor into node
    // 一旦点击 渲染方法
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if let name = anchor.name, name.hasPrefix(Constants.ObjectName) {
            node.addChildNode(loadModel())
            return
        }
        if let participantAnchor = anchor as? ARParticipantAnchor {
            DispatchQueue.main.async {
                print("did add participant")
            }
//            node.addChildNode(loadModel())
            return
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        
    }
    
    // worldmap的生成和发送
    func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData) {
        guard let multipeerSession = mpc else { return }
        if !multipeerSession.connectedPeers.isEmpty {
            
            // encodeData of collaborativeData
            guard let encodedData = try? NSKeyedArchiver.archivedData(withRootObject: data, requiringSecureCoding: true)
            else { fatalError("Unexpectedly failed to encode collaboration data.") }

            
            // Use reliable mode if the data is critical, and unreliable mode if the data is optional.
            let dataIsCritical = data.priority == .critical
            multipeerSession.sendDataToAllPeers(data: encodedData)
        } else {
            // 未匹配时
//            print("Deferred sending collaboration to later because there are no peers.")
        }
    }
    
    //NISessionDelegate Monitoring NearbyObjects
    // NI主循环
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        DispatchQueue(label: "serialQueue").async {
            if self.couldDetect == true {
                
                guard let peerToken = self.peerDiscoveryToken else {
                    fatalError("don't have peer token")
                }
                let nearbyOject = nearbyObjects.first { (obj) -> Bool in
                    return obj.discoveryToken == peerToken
                }
                guard let nearbyObjectUpdate = nearbyOject else {
                    return
                }
                self.visualisationUpdate(with: nearbyObjectUpdate)
            }
        }
        //当处理数据时停止实时测量
    }
    
    // 处理NI链接中断的逻辑
    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        guard let peerToken = peerDiscoveryToken else {
            fatalError("don't have peer token")
        }
        // Find the right peer.
        let peerObj = nearbyObjects.first { (obj) -> Bool in
            return obj.discoveryToken == peerToken
        }
        if peerObj == nil {
            return
        }
        currentState = .unknown
        switch reason {
        case .peerEnded:
            // The peer token is no longer valid.
            peerDiscoveryToken = nil
            // The peer stopped communicating, so invalidate the session because
            // it's finished.
            session.invalidate()
            // Restart the sequence to see if the peer comes back.
            startup()
            // Update the app's display.
            infoLabel.text = "Peer Ended"
        case .timeout:
            // The peer timed out, but the session is valid.
            // If the configuration is valid, run the session again.
            if let config = session.configuration {
                session.run(config)
            }
            infoLabel.text = "Peer Timeout"
        default:
            fatalError("Unknown and unhandled NINearbyObject.RemovalReason")
        }
    }
    
    // Main update in the
    // AR主循环
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // 特征检测
        featureSensor!.featureCounter(frame, frame.timestamp)
        
        if isRecording {
            // 获取初始帧
            if !isFirstFrame {
                isFirstFrame = true
                timeStampAlignment.AR_First_Stamp = frame.timestamp
            }
            // 数据采集
            guard let arkitData = StoredData.peerPosInARKit,
                  let niData = StoredData.peerPosInNI,
                  let distance = StoredData.distance,
                  let poseDataAR = StoredData.peerPoseInARKit else { return }
            collectorQUeue.async { [self] in
                dataCollector.collectData(arkitData, niData, poseDataAR, frame, distance, frame.timestamp)
            }
        }
    }
    
    // ARSessionDelegate Monitoring NearbyObjects
    // 同伴当成anchor 同伴anchor生成时调用
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let participantAnchor = anchor as? ARParticipantAnchor {
                
                //messageLabel.displayMessage("Established joint experience with a peer.")
                peerWorldTransFromARKit = participantAnchor.transform
                guard let camT = camera?.transform else {
                    return
                }
                let peerCamTransFromARKit = participantAnchor.transform * camT
                StoredData.peerPosInARKit = peerCamTransFromARKit.columns.3
                StoredData.peerPoseInARKit = poseCalculateInARKit(peerCamTransFromARKit)
            }
        }
    }
    
    // 同伴当成anchor 同伴anchor更新时调用
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let participantAnchor = anchor as? ARParticipantAnchor {
                //messageLabel.displayMessage("Established joint experience with a peer.")
                peerWorldTransFromARKit = participantAnchor.transform
                guard let camT = camera?.transform else {
                    return
                }
                let peerCamTransFromARKit = camT.inverse * participantAnchor.transform
                StoredData.peerPosInARKit = peerCamTransFromARKit.columns.3
            }
        }
    }
    
    // handler to connect
    var mapProvider: MCPeerID?
    // handler to data receive
    
    // 接受数据的方法
    func dataReceiveHandler(data: Data, peer: MCPeerID) {
        // worldmap
        if let collaborationData = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARSession.CollaborationData.self, from: data) {
            sceneView.session.update(with: collaborationData)
        }
        // NI会话的钥匙
        if let discoverytoken = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) {
            // 建立NI链接
            peerDidShareDiscoveryToken(peer: peer, token: discoverytoken)
        }
        // peer的AR物体转换到我的坐标系下
        if let pos = try? JSONDecoder().decode(simd_float4.self, from: data) {
            guard let camTrans = camera?.transform else { print("no cam")
                return }
            if abs(pos.w - 100) < 1 {
                // nothing
            }
            else {
                guard let direction = peerDirection else { couldDetect = true; return }
                guard let distance = peerDistance else { couldDetect = true; return }
                let peerPos = alignDistanceWithNI(distance: distance, direction: direction)
                //算法1 使用两次位姿旋转矩阵
                //let Pos = coordinateAlignment(direction: direction, distance: distance, myCam: cam, peerEuler: peerEulerangle!, pos: pos)
                //使用NI库自带的peer位姿矩阵 和 peercam坐标系坐标 求解世界坐标系坐标
                guard let peerT = peerWorldTransFromARKit else { couldDetect = true; return }
                let peerTrans: simd_float4x4 = simd_float4x4(peerT.columns.0,
                                                         peerT.columns.1,
                                                         peerT.columns.2,
                                                         Constants.weight * peerT.columns.3 + (1 - Constants.weight) * peerPos)
                guard let anchor = anchorFromPeer else { couldDetect = true; return}
                let objPos = camTrans * peerTrans * pos
                let objTrans = simd_float4x4(anchor.transform.columns.0,
                                             anchor.transform.columns.1,
                                             anchor.transform.columns.2,
                                             objPos)
                let newAnchor = ARAnchor(name: Constants.ObjectName, transform: objTrans)
                //算法结束 添加ar实体
                addAnchor(anchor: newAnchor)
                couldDetect = true
                if let e = optimizeAnchorPos(with: anchor), e != nil {
                    let originOffset = e
                    let x_column = simd_float4(1, 0, 0, 0)
                    let y_column = simd_float4(0, 1, 0, 0)
                    let z_column = simd_float4(0, 0, 1, 0)
                    //构造列主序矩阵
                    sceneView.session.setWorldOrigin(relativeTransform: simd_float4x4(columns: (x_column,y_column,z_column,originOffset)))
                }
            }
        }
        // 收到了peer创建的ARanchor
        if let anchor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARAnchor.self, from: data) {
            anchorFromPeer = anchor
        }
        // 暂时没用
        if let eulerangle = try? JSONDecoder().decode(simd_float3.self, from: data) {
            peerEulerangle = eulerangle
            //resetWorldOrigin(with: eularangle, and: peerEulerangle)
        }
    }
    
    // 重建世界坐标系
    func resetWorldOrigin(with myEuler: simd_float3, and peerEuler: simd_float3) {
        let newWorldTransform = correctPose(with: peerEuler, using: myEuler)
        sceneView.session.setWorldOrigin(relativeTransform: newWorldTransform)
    }
    
    // 手动添加anchor的函数
    func addAnchor(anchor: ARAnchor) {
        sceneView.session.add(anchor: anchor)
    }
    
    //receive peer token
    func peerDidShareDiscoveryToken(peer: MCPeerID, token: NIDiscoveryToken) {
        if connectedPeer != peer {
            fatalError("receive token from unexpected token")
        }
        peerDiscoveryToken = token
        //create a config
        startupNI()
    }
    
    //handling interruption and suspension
    func sessionWasSuspended(_ session: NISession) {
        infoLabel.text = "Session was suspended"
    }
    
    func sessionSuspensionEnded(_ session: NISession) {
        if let config = self.niSession?.configuration {
            session.run(config)
        } else {
            // Create a valid configuration.
            startup()
        }
    }
    
    //Hit test function
    // 点击逻辑
    @IBAction func handleTap(_ sender: UITapGestureRecognizer) {
        if sender.state == .ended {
            let location = sender.location(in: sceneView)
            guard let arRayCastQuery = sceneView
                .raycastQuery(from: location,
                              allowing: .estimatedPlane,
                              alignment: .horizontal)
            else {
                return
            }
            guard let result = sceneView.session.raycast(arRayCastQuery).first
            else {
                return
            }
            // 点机位置放置AR锚点
            let anchor = ARAnchor(name: Constants.ObjectName, transform: result.worldTransform)
            sceneView.session.add(anchor: anchor)
            
            // AR物体加密 传输
            guard let anchorData = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
            else { fatalError("can't encode anchor") }
            //send anchor data
            self.mpc?.sendDataToAllPeers(data: anchorData)
            
            // 暂时没用
            guard let cam = camera else { return }
            guard let eulerData = try? JSONEncoder().encode(cam.eulerAngles) else { fatalError("dont have your cam") }
            self.mpc?.sendDataToAllPeers(data: eulerData)
            // 世界坐标 - 相机坐标
            let pos = cam.transform.inverse * result.worldTransform.columns.3
            guard let posData = try? JSONEncoder().encode(pos) else { fatalError("cannot encode simd_float3x3") }
            self.mpc?.sendDataToAllPeers(data: posData)
        }
    }
    
    // 手电调用
    @IBAction func flashlight(_ sender: Any) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
                let alertController = UIAlertController(title: "Flashlight not supported", message: nil, preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: "Understand", style: .default, handler: nil))
                present(alertController, animated: true)
                return
            }
            
            do {
                try device.lockForConfiguration()
                let torchOn = !device.isTorchActive
                try device.setTorchModeOn(level: 1.0)
                device.torchMode = torchOn ? .on : .off
                device.unlockForConfiguration()
            } catch {
                let alertController = UIAlertController(title: "Flashlight is not supported", message: nil, preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: "Understand", style: .default, handler: nil))
                present(alertController, animated: true)
            }
    }
    
    // 环境面板弹出
    @IBAction func popupPanel(_ sender: Any) {
        if isPanelShowing {
            UIView.animate(withDuration: 0.5, delay: 0.0, options: .curveEaseIn, animations: {
                self.panelView.frame = CGRect(x: -250, y: 250, width: 250, height: 200)
            })
            panelButton.setTitle("Panel->", for: .normal)
            isPanelShowing = false
        } else {
            UIView.animate(withDuration: 0.5, delay: 0.0, options: .curveEaseIn, animations: {
                self.panelView.frame = CGRect(x: 0, y: 250, width: 250, height: 200)
            })
            panelButton.setTitle("<-Panel", for: .normal)
            isPanelShowing = true
        }
    }
    
    
    @IBAction func shareSession(_ sender: Any) {
        sceneView.session.getCurrentWorldMap(completionHandler: {
            worldmap, error in
            guard let map = worldmap else { print("Error: \(error!.localizedDescription)"); return }
            guard let data = try? NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true) else {
                fatalError("Cannot archive world map!")
            }
            self.mpc?.sendDataToAllPeers(data: data)
        })
    }
    
    //get distance&direction state
    func getDistanceDirectionState(from nearbyObject: NINearbyObject) -> DistanceDirectionState {
        if nearbyObject.distance == nil && nearbyObject.direction == nil {
            return .unknown
        }
        let isNearby = nearbyObject.distance.map(isNearby(_:)) ?? false
        let directionAvailable = nearbyObject.direction != nil
        if isNearby && directionAvailable {
            return .closeUpInFOV
        }
        if !isNearby && directionAvailable {
            return .notCloseUpInFOV
        }
        return .outOfFOV
    }
    
    func isNearby(_ distance: Float) -> Bool {
        return distance < Constants.distanceThereshold
    }
    
    //load object model
    func loadModel() -> SCNNode {
        guard let usdzURL = Bundle.main.url(forResource: "NTU_Buildings_Map", withExtension: "usdz") else {
            return SCNNode(geometry: SCNSphere(radius: 0.1))
        }
        let mdlAsset = MDLAsset(url: usdzURL)
        mdlAsset.loadTextures()
        let asset = mdlAsset.object(at: 0) // extract first object
        let assetNode = SCNNode(mdlObject: asset)
        
        assetNode.rotation = SCNVector4Make(0, 1, 0, .pi / 2)
        
        assetNode.simdScale = simd_float3(0.05, 0.05, 0.05)
        
        return assetNode
    }
    
    //update visualization information
    func visualisationUpdate(with peer: NINearbyObject) {
        // Animate into the next visuals.
        guard let direction = peer.direction else { return }
        peerDirection = direction
        guard let distance = peer.distance else { return }
        peerDistance = distance
        let camVec = alignDistanceWithNI(distance: distance, direction: direction)
        StoredData.peerPosInNI = camVec.normalize()
        StoredData.distance = distance
    }
    @IBAction func projMenu(_ sender: Any) {
        let swiftUIView = ProjectView()
        let hostingController = UIHostingController(rootView: swiftUIView)
        DispatchQueue.main.async {
            self.present(hostingController, animated: true, completion: nil)
        }
    }
    
    //use button to reset tracking
    @IBAction func resetTracking(_ sender: UIButton?) {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        sceneView.session.run(configuration, options: [.removeExistingAnchors, .resetTracking])
    }
    
    //use coachingoverlayview to reset tracking
    @IBAction func resetTracking() {
        guard let configuration = sceneView.session.configuration as? ARWorldTrackingConfiguration else { print("A configuration is required"); return }
        configuration.planeDetection = [.horizontal, .vertical]
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    @IBAction func removeAllAnchorsYouCreated(_ sender: UIButton?) {
        guard let frame = sceneView.session.currentFrame else { return }
        for anchor in frame.anchors {
            guard let anchorSessionID = anchor.sessionIdentifier else { continue }
            if anchorSessionID.uuidString == sceneView.session.identifier.uuidString {
                sceneView.session.remove(anchor: anchor)
            }
        }
    }
    
    private func removeAllAnchorsOriginatingFromARSessionWithID(_ identifier: String) {
        guard let frame = sceneView.session.currentFrame else { return }
        for anchor in frame.anchors {
            guard let anchorSessionID = anchor.sessionIdentifier else { continue }
            if anchorSessionID.uuidString == identifier {
                sceneView.session.remove(anchor: anchor)
            }
        }
    }
    
    private func sendARSessionIDTo(peers: [MCPeerID]) {
        guard let multipeerSession = mpc else { return }
        let idString = sceneView.session.identifier.uuidString
        let command = "SessionID:" + idString
        // 将字符串类型转为data
        if let commandData = command.data(using: .utf8) {
            multipeerSession.sendDataToAllPeers(data: commandData)
        }
    }
}

extension ViewController {
    // 采集按钮触发
    @objc func hitRecordingButton() {
        isRecording.toggle()
        if isRecording {
            ScanConfig.fileURL = getRecordingDirectory()
            ScanConfig.isRecording = true
            circleLayer?.backgroundColor = UIColor.red.cgColor
            Logger.shared.debugPrint("Start Recording.")
            cmManager.startRecording()
        } else {
            ScanConfig.isRecording = false
            Logger.shared.debugPrint("End Recording.")
            circleLayer?.backgroundColor = UIColor.green.cgColor
            cmManager.endRecording()
        }
    }
    
    // files列表读取
    @objc func projectMenu() {
//        let swiftUIView = ProjectView()
//        let hostingController = UIHostingController(rootView: swiftUIView)
//        DispatchQueue.main.async {
//            self.present(hostingController, animated: true, completion: nil)
//        }
        let dirPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let path = dirPath.absoluteString.replacingOccurrences(of: "file://", with: "shareddocuments://")
        let url = URL(string: path)!
        UIApplication.shared.open(url)
    }
    
    // 清除所有采集文件
    @objc func clearTempFolder() {
        let queue = DispatchQueue(label: "delete")
        queue.async {
            let fileMgr = FileManager.default
            let currentPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
            do {
                let directoryContents = try fileMgr.contentsOfDirectory(atPath: currentPath)
                for path in directoryContents {
                    let combinedPath = currentPath + "/" + path
                    try fileMgr.removeItem(atPath: combinedPath)
                }
            } catch let error {
                print("Error: \(error.localizedDescription)")
            }
        }
    }
    
    
    func updateCMFirstStamp(_ timeStamp: TimeInterval) {
        timeStampAlignment.CM_First_Stamp = timeStamp
    }
}

struct Constants {
    static let ObjectName = "Object"
    static let distanceThereshold: Float = 0.4
    static let frameNum: Int = 2
    static let weight: Float = 0.9
}
