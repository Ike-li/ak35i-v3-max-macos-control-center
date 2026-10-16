import Accelerate
import Foundation

/// Latest mono audio, filled from the capture thread and read per frame.
protocol AudioSampleSource: AnyObject, Sendable {
    func latestSamples() -> (samples: [Float], sampleRate: Double)
}

/// Band levels (0…1) of the latest audio window: 16 log-spaced bands from
/// 40 Hz to 16 kHz, peak amplitude per band on a −60…0 dBFS scale.
struct SpectrumAnalyzer {
    static let windowLength = 2048
    static let bandCount = 16
    private static let log2n = vDSP_Length(11)
    private static let edges = (0...bandCount).map { 40 * pow(16_000.0 / 40, Double($0) / Double(bandCount)) }

    private let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: windowLength, isHalfWindow: false)

    static func band(containing frequency: Double) -> Int? {
        (0..<bandCount).first { edges[$0] <= frequency && frequency < edges[$0 + 1] }
    }

    func bands(samples: [Float], sampleRate: Double) -> [Double] {
        let count = Self.windowLength
        guard samples.count >= count, let setup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2)) else {
            return Array(repeating: 0, count: Self.bandCount)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        let windowed = vDSP.multiply(Array(samples.suffix(count)), window)
        var real = [Float](repeating: 0, count: count / 2)
        var imaginary = [Float](repeating: 0, count: count / 2)
        var powers = [Float](repeating: 0, count: count / 2)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: count / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(count / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &powers, 1, vDSP_Length(count / 2))
            }
        }

        let binWidth = sampleRate / Double(count)
        return (0..<Self.bandCount).map { band in
            // Bin 0 also carries the packed Nyquist term, so it is skipped.
            let bins = (1..<count / 2).filter {
                let frequency = Double($0) * binWidth
                return Self.edges[band] <= frequency && frequency < Self.edges[band + 1]
            }
            let peak = bins.map { Double(powers[$0]) }.max() ?? 0
            // zrip doubles the DFT and the Hann window halves a tone: A = |X| · 2 / N.
            let amplitude = peak.squareRoot() * 2 / Double(count)
            guard amplitude > 0 else { return 0 }
            return min(max((20 * log10(amplitude) + 60) / 60, 0), 1)
        }
    }
}

/// Bars rise at once and fall by 15 % per frame so the lights do not flicker.
struct MusicMeter {
    private var levels: [Double] = []

    mutating func update(_ bands: [Double]) -> [Double] {
        if levels.count != bands.count { levels = Array(repeating: 0, count: bands.count) }
        levels = zip(bands, levels).map { max($0, $1 * 0.85) }
        return levels
    }
}

/// Each key belongs to the band under its centre; a band lights its column
/// from the bottom row up, green at the bottom to red at the top.
enum MusicVisualizer {
    private static let rowsFromBottom = Array(Set(KeyboardLayout.keys.map(\.y))).sorted(by: >)

    static func band(of key: KeyboardKey) -> Int {
        let position = (Double(key.x) + Double(key.width) / 2 - 30) / 740
        return min(max(Int(position * Double(SpectrumAnalyzer.bandCount)), 0), SpectrumAnalyzer.bandCount - 1)
    }

    static func frame(bands: [Double]) -> [UInt8: RGBColor] {
        let rows = Double(rowsFromBottom.count)
        return Dictionary(uniqueKeysWithValues: KeyboardLayout.keys.map { key in
            let row = rowsFromBottom.firstIndex(of: key.y) ?? 0
            let level = band(of: key) < bands.count ? bands[band(of: key)] : 0
            // Half a row of headroom keeps a decaying meter from leaving the bottom row lit.
            guard level * rows >= Double(row) + 0.5 else { return (key.light, RGBColor(red: 0, green: 0, blue: 0)) }
            return (key.light, RGBColor(hue: (1.0 / 3) * (1 - Double(row) / (rows - 1))))
        })
    }
}
