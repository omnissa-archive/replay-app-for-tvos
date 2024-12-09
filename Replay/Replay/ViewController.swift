//
//  ViewController.swift
//  Replay
//
//  Created by Rajiv Singh and Naveen Pitchandi on 8/24/17.

//  Copyright 2017 Omnissa, LLC. All Rights Reserved.

//This product is licensed to you under the BSD-2 license (the "License").  You may not use this product except in compliance with the BSD-2 License.

//This product may include a number of subcomponents with separate copyright notices and license terms. Your use of these subcomponents is subject to the terms and conditions of the subcomponent's license, as noted in the LICENSE file.

import UIKit
import AVFoundation
import AVKit

enum PlaybackState {
    case unknown
    case initializing
    case initialized
    case playing
    case paused
    case stopped
    case unplayable
}

class ViewController: UIViewController {
    
    // URL of the Video
    var urlArray: [String] = ["http://techslides.com/demos/sample-videos/small.mp4", "https://media.w3.org/2010/05/sintel/trailer.mp4"]
    var player: AVQueuePlayer? = nil
    var playbackStatus : PlaybackState = .unknown
    
    @IBOutlet var statusLabel : UILabel? = nil
    
    lazy var spinner = UIActivityIndicatorView.init(activityIndicatorStyle: .whiteLarge)
    
    // MARK:
    // MARK: View life cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        registerNotifications()
        initAudioSession()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if playbackStatus == .unknown {
            playbackStatus = .initializing
            initPlayer()
        }else if playbackStatus == .playing {
            self.statusLabel?.text = "Player interrupted"
        }
    }
    
    // MARK:
    // MARK: memory management
    
    deinit {
        deregisterNotifications()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK:
    // MARK: Initializations
    
    func initAudioSession() -> Void {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(AVAudioSessionCategoryPlayback)
        }
        catch {
            print("Setting category to AVAudioSessionCategoryPlayback failed.")
        }
    }
    
    func initPlayer() -> Void {
        
        if urlArray.isEmpty {
            playbackStatus = .unplayable
            self.statusLabel?.text = "No media specified for playback"
            return
        }
        
        let asset = assets(forMediaURLs: urlArray)
        
        guard let currentAssetPlaying = asset.first else {
            playbackStatus = .unplayable
            self.statusLabel?.text = "Could not create Assets from the supplied media URL's"
            return
        }
        
        let playableKey = "playable"
        
        // In future, we should load all assets at once and add to player queue only ones which are playable.
        currentAssetPlaying.loadValuesAsynchronously(forKeys: [playableKey], completionHandler: {
            DispatchQueue.main.async {
                var error: NSError? = nil
                let status = currentAssetPlaying.statusOfValue(forKey: playableKey, error: &error)
                switch status {
                case .loaded:
                    // Sucessfully loaded. Continue processing.
                    self.statusLabel?.text = "Player initialized"
                    self.playbackStatus = .initialized
                    self.startPlayer(forAssets: asset)
                    break
                case .failed:
                    // Handle error
                    self.playbackStatus = .unplayable
                    self.statusLabel?.text = "Failed to initialize the player. Error: \(error?.localizedDescription ?? "")"
                    break
                case .cancelled:
                    // Terminate processing
                    self.playbackStatus = .unplayable
                    self.statusLabel?.text = "Initializing player was cancelled. Error: \(error?.localizedDescription ?? "")"
                    break
                default:
                    // Handle all other cases
                    self.playbackStatus = .unplayable
                    self.statusLabel?.text = "Unknown error while initilizing the player"
                    break
                }
            }
        })
    }
    
    // MARK:
    // MARK: Playback
    
    func startPlayer(forAssets asset: [AVURLAsset]) -> Void {
        
        if asset.isEmpty {
            self.playbackStatus = .unplayable
            self.statusLabel?.text = "Media asset not present"
            return
        }
        
        let playerItemArray = playerItemArrayCollection(forAsset: asset)
        if playerItemArray.isEmpty {
            self.playbackStatus = .unplayable
            self.statusLabel?.text = "Media asset not present"
            return
        }
        
        // Create a new AVPlayerViewController and pass it a reference to the player.
        self.player = AVQueuePlayer.init(items: playerItemArray)
        self.player?.actionAtItemEnd = .none
        if let controller = constructPlayerViewController(player: self.player) {
            // Modally present the player and call the player's play() method when complete.
            self.present(controller, animated: true) {
                self.playbackStatus = .playing
                controller.player?.play()
            }
        }
    }
    
    func resumePlayer(player: AVQueuePlayer?) -> Void {
        guard (self.playbackStatus == .playing || self.playbackStatus == .paused || self.playbackStatus == .stopped) else {
            return
        }
        
        guard player != nil else {
            return
        }
        
        if let playerViewController = self.presentedViewController as? AVPlayerViewController {
            playerViewController.player?.play()
        }else {
            if let controller = constructPlayerViewController(player: player) {
                // Modally present the player and call the player's play() method when complete.
                self.present(controller, animated: true) {
                    self.playbackStatus = .playing
                    controller.player?.play()
                }
            }
        }
    }
    
    func constructPlayerViewController(player: AVQueuePlayer?) -> AVPlayerViewController? {
        guard player != nil else {
            return nil
        }
        
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.delegate = self
        controller.player = player
        return controller
    }
    
    // MARK:
    // MARK: AVPlayer notifications
    
    func registerNotifications() -> Void {
        NotificationCenter.default.addObserver(self, selector: #selector(playerItemDidReachEnd(notification:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: self.player?.currentItem)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive(notification:)), name: .UIApplicationDidBecomeActive, object: nil)
    }
    
    func deregisterNotifications() -> Void {
        NotificationCenter.default.removeObserver(self)
    }
    
    func playerItemDidReachEnd(notification: NSNotification) -> Void {
        
        guard notification.object as? AVPlayerItem  == self.player?.currentItem else {
            return
        }
        
        guard let asset = self.player?.currentItem?.asset as? AVURLAsset else {
            return
        }
        
        if asset.isDownloaded() {
            // Asset was already downloaded. We play it again.
            self.player?.playNextItem()
            return
        }
        
        if asset.isExportable == false {
            self.player?.playNextItem()
            return
        }
        
        let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
        
        exporter?.outputURL = asset.downloadPath(create: true)
        exporter?.outputFileType = AVFileTypeQuickTimeMovie
        exporter?.exportAsynchronously(completionHandler: {
            DispatchQueue.main.async {
                self.player?.playNextItem()
                return
            }
        })
    }
    
    func applicationDidBecomeActive(notification: Notification) -> Void {
        self.resumePlayer(player: self.player)
    }
    
    // MARK:
    // MARK: Spinner
    
    func showSpinner(inView parentView: UIView) -> Void {
        spinner.center = parentView.center
        parentView.addSubview(spinner)
        spinner.startAnimating()
    }
    
    func hideSpinner() -> Void {
        spinner.stopAnimating()
        spinner.removeFromSuperview()
    }
    
    func assets(forMediaURLs mediaURLs: [String]) -> [AVURLAsset] {
        var assetArray = [AVURLAsset]()
        
        for media in urlArray {
            guard let url = URL.init(string: media) else {
                continue
            }
            
            var asset = AVURLAsset.init(url: url, options: [AVURLAssetAllowsCellularAccessKey : false])
            if asset.isDownloaded() {
                // Asset was already downloaded before. So we recreate it from the local URL.
                if let localAssetURL = asset.downloadPath() {
                    asset = AVURLAsset.init(url: localAssetURL)
                }
            }else {
                // Asset isn't downloaded yet. Set its resource loader so that we can export it later when its finished.
                asset.resourceLoader.setDelegate(self, queue: DispatchQueue.main)
            }
            assetArray.append(asset)
        }
        
        return assetArray
    }
    
    func playerItemArrayCollection(forAsset asset: [AVURLAsset]) -> [AVPlayerItem]{
        var playerItemArray = [AVPlayerItem]()
        for mediaAsset in asset{
            let playerItemTemp = AVPlayerItem.init(asset: mediaAsset)
            playerItemArray.append(playerItemTemp)
        }
        return playerItemArray
    }
    
    func isLastItemPlayed(asset: AVURLAsset) -> Bool {
        let lastURLOfMedia : String = self.urlArray.last!
        if(asset.url.absoluteString.range(of: lastURLOfMedia) != nil){
            return true
        }
        else{
            return false
        }
    }
    
    
}

// MARK:
// MARK: Extensions

extension AVQueuePlayer {
    func playNextItem(){
        let currentItem = self.currentItem
        self.advanceToNextItem()
        
        if let item = currentItem {
            item.seek(to: kCMTimeZero)
            if self.canInsert(item, after: nil){
                self.insert(item, after: nil)
            }
        }
    }
}
extension ViewController : AVAssetResourceLoaderDelegate {
    // We don't really have anything to do here.
}

extension ViewController : AVPlayerViewControllerDelegate {
    func playerViewController(_ playerViewController: AVPlayerViewController, shouldPresent proposal: AVContentProposal, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        self.present(playerViewController, animated: true) {
            completionHandler(true)
        }
    }
}

extension AVPlayer {
    func restart() -> Void {
        self.pause()
        self.seek(to: kCMTimeZero)
        self.play()
    }
}

extension AVURLAsset {
    
    func isDownloaded() -> Bool {
        
        // First check if media is present at asset's URL. This could be the case if asset was created locally.
        let mediaExists = FileManager.init().fileExists(atPath: self.url.path)
        if mediaExists == false {
            // Media is not present at asset's URL. Derive the download path to check if its present there instead.
            if let downloadedAssetURL = self.downloadPath() {
                let mediaExists = FileManager.init().fileExists(atPath: downloadedAssetURL.path)
                return mediaExists
            }
        }else {
            // Media is present at asset's URL. This means asset was created out of the locally stored media. Thus, it is already downloaded.
            return true
        }
        
        return false
    }
    
    func downloadPath(create: Bool = false) -> URL? {
        
        let urlData = self.url.absoluteString.data(using: .utf8)
        let base64EncodedString = urlData?.base64EncodedString()
        
        guard let urlDirectory = base64EncodedString else {
            return nil
        }
        
        guard let documentsDirectory: URL = FileManager.init().urls(for: FileManager.SearchPathDirectory.cachesDirectory, in: FileManager.SearchPathDomainMask.userDomainMask).last else {
            return nil
        }
        
        let directoryURL = documentsDirectory.appendingPathComponent(urlDirectory)
        
        if create {
            do {
                try FileManager.init().createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            }catch let error as NSError {
                print("Failed to create asset’s download path with error: \(error.localizedDescription)")
            }
        }
        let fileExtension = ".mov"
        let filename = "\(urlDirectory)\(fileExtension)"
        let mediaURL = directoryURL.appendingPathComponent(filename)
        return mediaURL
    }
}

extension String {
    func sha512() -> String? {
        if let stringData = self.data(using: String.Encoding.utf8) {
            if let hash = stringData.sha512() {
                return hash.base64EncodedString()
            }
        }
        return nil
    }
}

extension Data {
    func sha512() -> Data? {
        
        var hash = [UInt8](repeating: 0,  count: Int(CC_SHA512_DIGEST_LENGTH))
        self.withUnsafeBytes {
            _ = CC_SHA512($0, CC_LONG(self.count), &hash)
        }
        return Data(bytes: hash)
        
    }
}
