//
//  ViewController.swift
//  Replay
//
//  Created by Rajiv Singh and Naveen Pitchandi on 8/24/17.

//  Copyright 2017 VMware, Inc. All Rights Reserved.

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
    let media = "https://munkitest.prowarehouse.nl/replay/PWH-Movie.m4v"
    var player: AVPlayer? = nil
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
        
        guard let media = UserDefaults.standard.string(forKey: "mediaURL") else {
            playbackStatus = .unplayable
            self.statusLabel?.text = "No media preference for playback"
            return
        }
        
        guard let url = URL(string: media) else {
            playbackStatus = .unplayable
            self.statusLabel?.text = "No media specified for playback"
            return
        }
        
        let playableKey = "playable"
        var asset = AVURLAsset.init(url: url, options: [AVURLAssetAllowsCellularAccessKey : false])
        
        if asset.isDownloaded() {
            // Asset was already downloaded before. So we recreate it from the local URL.
            if let localAssetURL = asset.downloadPath() {
                asset = AVURLAsset.init(url: localAssetURL)
            }
        } else {
            // Asset isn't downloaded yet. Set its resource loader so that we can export it later when its finished.
            asset.resourceLoader.setDelegate(self, queue: DispatchQueue.main)
        }
        
        asset.loadValuesAsynchronously(forKeys: [playableKey], completionHandler: {
            DispatchQueue.main.async {
                
                var error: NSError? = nil
                let status = asset.statusOfValue(forKey: playableKey, error: &error)
                switch status {
                case .loaded:
                    // Sucessfully loaded. Continue processing.
                    self.statusLabel?.text = "Player initialized"
                    self.playbackStatus = .initialized
                    self.startPlayer(forAsset: asset)
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
    
    func startPlayer(forAsset asset: AVURLAsset?) -> Void {
        
        guard let mediaAsset = asset else {
            self.playbackStatus = .unplayable
            self.statusLabel?.text = "Media asset not present"
            return
        }
        
        let playerItem = AVPlayerItem.init(asset: mediaAsset)
        
        if let playerViewController = self.presentedViewController as? AVPlayerViewController {
            self.playbackStatus = .playing
            playerViewController.player?.replaceCurrentItem(with: playerItem)
            playerViewController.player?.restart()
        }else {
            // Create a new AVPlayerViewController and pass it a reference to the player.
            self.player = AVPlayer.init(playerItem: playerItem)
            self.player?.actionAtItemEnd = .none
            
            if let controller = constructPlayerViewController(player: self.player) {
                // Modally present the player and call the player's play() method when complete.
                self.present(controller, animated: true) {
                    self.playbackStatus = .playing
                    controller.player?.play()
                }
            }
        }
    }
    
    func resumePlayer(player: AVPlayer?) -> Void {
        
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
    
    func constructPlayerViewController(player: AVPlayer?) -> AVPlayerViewController? {
        
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
            self.player?.restart()
            return
        }
        
        if asset.isExportable == false {
            // Asset is not exportable. We continue playing on network.
            self.player?.restart()
            return
        }
        
        let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
        
        exporter?.outputURL = asset.downloadPath(create: true)
        exporter?.outputFileType = AVFileTypeQuickTimeMovie
        
        exporter?.exportAsynchronously(completionHandler: {
            DispatchQueue.main.async {
                if exporter?.status == .completed {
                    // Asset exported successfully. We configure the player with this downloaded  asset and play it again.
                    self.initPlayer()
                }else {
                    // Asset export failed. Restart the media.
                    self.player?.restart()
                }
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
}

// MARK:
// MARK: Extensions

extension ViewController : AVAssetResourceLoaderDelegate {
    // We don't really have anything to do here.
}

extension ViewController : AVPlayerViewControllerDelegate {
    func playerViewController(_ playerViewController: AVPlayerViewController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
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
        
        let filename = "media.mov"
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

