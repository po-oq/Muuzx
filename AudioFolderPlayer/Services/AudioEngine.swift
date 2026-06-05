import Foundation

protocol AudioEngine: AnyObject {
    var currentTimeSec: Double { get }
    var durationSec: Double { get }
    func load(url: URL)
    func play()
    func pause()
    func seek(toSec seconds: Double)
    /// 再生が末尾まで到達したときに呼ばれる
    var onPlaybackEnded: (() -> Void)? { get set }
}
