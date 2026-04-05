import Dependencies
import Domain
import StandardOutput

extension StandardOutputKey: DependencyKey {
    public static let liveValue: any StandardOutput = PrintStandardOutput()
}
