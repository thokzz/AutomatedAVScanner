import AVFoundation
import AppKit

class AudioCueManager: NSObject {
    static let shared = AudioCueManager()
    private var player: AVAudioPlayer?
    private let audioQueue = DispatchQueue(label: "com.drivescanner.audioqueue", qos: .userInitiated)
    
    // Track playback attempts and successes
    private var currentlyAttemptingPlayback = false
    private var lastPlaybackAttempt: Date? = nil
    private var recentlyPlayedCues = [String: Date]()
    
    // Specific check for Monterey
    private let isMonterey: Bool = {
        if #available(macOS 12.0, *) {
            if #available(macOS 13.0, *) {
                return false // Ventura or newer
            }
            return true // Monterey specifically
        }
        return false // Older than Monterey
    }()
    
    enum Cue: String {
        case driveDetected = "driveisdetected"
        case driveEjected = "driveisejected"
        case driveSafeToRemove = "safedrive" // Using shorter name always for consistency
        
        var displayName: String {
            switch self {
            case .driveDetected: return "Drive Detected"
            case .driveEjected: return "Drive Ejected"
            case .driveSafeToRemove: return "Drive Safe To Remove"
            }
        }
        
        var filename: String {
            return self.rawValue
        }
    }
    
    private var isPlaying = false
    private var playbackCompletionTimer: Timer?

    func play(_ cue: Cue) {
        // Prevent rapid repeated plays of the same cue
        let now = Date()
        let cueKey = cue.rawValue
        
        if let lastPlayed = recentlyPlayedCues[cueKey],
           now.timeIntervalSince(lastPlayed) < 3.0 {
            print("🔊 Skipping duplicate play of \(cue.displayName) (played recently)")
            return
        }
        
        // Update last attempt timestamp
        lastPlaybackAttempt = now
        recentlyPlayedCues[cueKey] = now
        
        // Use a more reliable approach for Monterey
        if isMonterey && cue == .driveSafeToRemove {
            print("⚠️ Monterey detected: Using fallback sound for \(cue.displayName)")
            playMontereyFallbackSound()
            return
        }
        
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Avoid concurrent playback attempts
            if self.currentlyAttemptingPlayback {
                print("🔊 Another audio playback in progress, waiting...")
                
                // Wait with timeout
                let waitStartTime = Date()
                while self.currentlyAttemptingPlayback &&
                      Date().timeIntervalSince(waitStartTime) < 2.0 {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                
                // If still attempting playback after waiting, use system sound as fallback
                if self.currentlyAttemptingPlayback {
                    print("⚠️ Audio system busy too long")

                    // Only fallback if it hasn’t already played once
                    if !self.recentlyPlayedCues.keys.contains(cueKey) {
                        print("🔊 Trying fallback system sound")
                        self.playSystemSound()
                    } else {
                        print("⏳ Skipping fallback sound (already played once)")
                    }

                    return
                }

            }
            
            self.currentlyAttemptingPlayback = true
            
            // Ensure any existing player is stopped
            if self.isPlaying {
                self.forceStopCurrentPlayback()
            }
            
            // Attempt to play the sound file
            do {
                // Get the URL for the sound file with proper fallbacks
                if let url = self.getSoundFileURL(for: cue) {
                    print("🎵 Attempting to play: \(url.path)")
                    
                    // Initialize player
                    self.player = try AVAudioPlayer(contentsOf: url)
                    self.player?.delegate = self
                    self.player?.volume = 1.0
                    self.player?.prepareToPlay()
                    
                    // Attempt playback
                    let playStarted = self.player?.play() ?? false
                    print("🎵 Play result: \(playStarted ? "started" : "failed")")
                    
                    // Set isPlaying state
                    self.isPlaying = playStarted
                    
                    // Fallback to system sound if playback failed
                    if !playStarted {
                        self.playSystemSound()
                    } else {
                        // Ensure playback completion is detected (safety fallback)
                        DispatchQueue.main.async {
                            self.schedulePlaybackCompletionTimer()
                        }
                    }
                } else {
                    print("⚠️ Sound file not found for: \(cue.filename)")
                    self.playSystemSound()
                }
            } catch {
                print("❌ Failed to initialize player: \(error.localizedDescription)")
                self.playSystemSound()
            }
            
            // Reset attempt state after a delay to prevent race conditions
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.currentlyAttemptingPlayback = false
            }
        }
    }
    
    private func getSoundFileURL(for cue: Cue) -> URL? {
        // For Monterey, always try the shorter filename first
        if isMonterey && cue == .driveSafeToRemove {
            if let url = Bundle.main.url(forResource: "safedrive", withExtension: "mp3"),
               FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        
        // Then try the standard filename
        if let url = Bundle.main.url(forResource: cue.filename, withExtension: "mp3"),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        
        // For driveSafeToRemove, check both possible filenames
        if cue == .driveSafeToRemove {
            let alternateNames = ["driveisnowsafetoberemoved", "safedrive", "safe_to_remove"]
            for name in alternateNames {
                if let url = Bundle.main.url(forResource: name, withExtension: "mp3"),
                   FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }
        
        return nil
    }
    
    private func playMontereyFallbackSound() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Try playing a reliable system sound
            let sound = NSSound(named: NSSound.Name("Ping"))
            let started = sound?.play() ?? false
            
            if !started {
                // If system sound failed, try NSBeep
                NSSound.beep()
            }
            
            print("🔊 Monterey fallback sound played")
            
            // Make sure we reset playback state after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.isPlaying = false
                self.currentlyAttemptingPlayback = false
            }
        }
    }
    
    private func playSystemSound() {
        DispatchQueue.main.async {
            NSSound.beep()
            print("🔊 Used system beep as fallback")
        }
    }
    
    private func forceStopCurrentPlayback() {
        // Safely stop any current playback
        if let existingPlayer = player {
            existingPlayer.stop()
            print("🛑 Forced stop of current audio playback")
        }
        
        // Reset state to avoid deadlocks
        isPlaying = false
        invalidateCompletionTimer()
    }
    
    private func schedulePlaybackCompletionTimer() {
        invalidateCompletionTimer() // Clear any existing timer
        
        // Create safety timeout to ensure playback state is reset
        playbackCompletionTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            if self.isPlaying {
                print("⏱️ Playback completion timeout triggered")
                self.isPlaying = false
            }
            
            self.playbackCompletionTimer = nil
        }
    }
    
    private func invalidateCompletionTimer() {
        playbackCompletionTimer?.invalidate()
        playbackCompletionTimer = nil
    }
}

// MARK: - AVAudioPlayerDelegate for completion tracking
extension AudioCueManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("🔊 Audio cue finished playing successfully: \(flag)")
        isPlaying = false
        invalidateCompletionTimer()
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("❌ Audio decoding error: \(error?.localizedDescription ?? "unknown error")")
        isPlaying = false
        invalidateCompletionTimer()
        playSystemSound()
    }
}
