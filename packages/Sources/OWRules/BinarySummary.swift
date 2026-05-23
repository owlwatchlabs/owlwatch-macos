import Foundation
import OWBinary

/// Compact, rule-queryable view of a parsed Mach-O / Universal
/// binary. Built once per unique executable path during snapshot
/// capture so rules iterating the `binary` source pay one parse cost
/// for many rules.
///
/// The summary collapses across slices: `architectures` carries every
/// slice's arch name; `linkedDylibs` and `rpaths` dedupe across
/// slices; `hasRWXSegment` is `true` if *any* segment in *any* slice
/// has the rwx bits; `maxSectionEntropy` is the maximum entropy
/// across every section in every slice. Rules that need per-slice
/// granularity will get a richer source in a later milestone — for
/// M13.2 the "any slice" semantics catch the common malware patterns.
public struct BinarySummary: Sendable, Equatable, Hashable {
    public let path: String
    public let isUniversal: Bool
    public let sliceCount: Int
    public let architectures: [String]
    public let linkedDylibs: [String]
    public let rpaths: [String]
    public let hasRWXSegment: Bool
    public let maxSectionEntropy: Double

    public init(
        path: String,
        isUniversal: Bool,
        sliceCount: Int,
        architectures: [String],
        linkedDylibs: [String],
        rpaths: [String],
        hasRWXSegment: Bool,
        maxSectionEntropy: Double
    ) {
        self.path = path
        self.isUniversal = isUniversal
        self.sliceCount = sliceCount
        self.architectures = architectures
        self.linkedDylibs = linkedDylibs
        self.rpaths = rpaths
        self.hasRWXSegment = hasRWXSegment
        self.maxSectionEntropy = maxSectionEntropy
    }
}

extension BinarySummary {
    /// Build a `BinarySummary` from a parsed `BinaryFile`. Computes
    /// the RWX-segment flag by walking every segment in every slice;
    /// computes entropy by reading `OWBinary.sectionEntropies(of:)`
    /// — bounded cost since the entropy pass is mmap-backed and
    /// O(file size).
    static func make(from binary: BinaryFile) -> BinarySummary {
        var hasRWX = false
        for slice in binary.slices {
            for command in slice.loadCommands {
                if case .segment(let segment) = command {
                    let initial = segment.initialProtection
                    if initial.contains(.write) && initial.contains(.execute) {
                        hasRWX = true
                    }
                }
            }
            if hasRWX { break }
        }

        let dylibNames = binary.linkedDylibs.map { $0.name }
        var rpathSet: Set<String> = []
        for slice in binary.slices {
            for command in slice.loadCommands {
                if case .rpath(let path) = command {
                    rpathSet.insert(path)
                }
            }
        }

        let entropies = (try? OWBinary.sectionEntropies(of: binary)) ?? []
        let maxEntropy = entropies.map { $0.entropy }.max() ?? 0.0

        return BinarySummary(
            path: binary.url.path,
            isUniversal: binary.isUniversal,
            sliceCount: binary.slices.count,
            architectures: binary.slices.map { $0.architecture.name },
            linkedDylibs: dylibNames,
            rpaths: Array(rpathSet).sorted(),
            hasRWXSegment: hasRWX,
            maxSectionEntropy: maxEntropy
        )
    }
}
