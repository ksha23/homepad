import Foundation
import HomePadCore

/// What Now Playing follows, and where transport goes.
extension AudioMediaService {
    /// What Now Playing follows, held through track changes by `FocusHold`.
    var focus: Focus? {
        _ = holdRevision
        return focusHold.resolve(rawFocus, localIsPlaying: activeSource?.isPlaying == true, at: Date())
    }

    /// The focus rules before the hold: local audio while it plays, then a speaker
    /// the person chose to control, then the active Music Assistant player or
    /// Spotify when that is the source, then whatever is loaded locally.
    var rawFocus: Focus? {
        if let source = activeSource, source.isPlaying { return .local }
        if let remoteTargetID { return .remote(remoteTargetID) }
        if musicSource == .musicAssistant, let player = musicAssistant.activePlayer { return .remote(player.id) }
        if musicSource == .spotify, spotify.playback?.item != nil { return .spotify }
        if activeSource?.nowPlaying != nil { return .local }
        return nil
    }

    /// Where transport goes when nothing is in focus: the Music Assistant speaker,
    /// Spotify, or this iPad.
    var transportTarget: Focus? {
        if let focus { return focus }
        if musicSource == .musicAssistant, let target = musicAssistant.targetPlayer { return .remote(target.id) }
        if musicSource == .spotify, spotify.isReady { return .spotify }
        return activeSource == nil ? nil : .local
    }

    /// What plays in focus, before the hold smooths it.
    var liveNowPlaying: NowPlaying? {
        switch focus {
        case .local:
            var item = activeSource?.nowPlaying
            item?.outputName = musicOutputName
            return item
        case .remote(let id):
            return remotePlayers.nowPlaying(on: id)
        case .spotify:
            return spotify.nowPlaying
        case nil:
            return nil
        }
    }
}
