import Foundation

public struct QuotaWarningEvent: Sendable, Equatable {
    public var provider: AgentKind
    public var providerName: String
    public var bucketName: String
    public var remainingPercentage: Double
    public var resetAt: Date?

    public init(
        provider: AgentKind,
        providerName: String,
        bucketName: String,
        remainingPercentage: Double,
        resetAt: Date? = nil
    ) {
        self.provider = provider
        self.providerName = providerName
        self.bucketName = bucketName
        self.remainingPercentage = remainingPercentage
        self.resetAt = resetAt
    }

    public var message: String {
        "\(providerName) quota is down to \(Int(remainingPercentage.rounded()))% (\(bucketName)). Use it carefully."
    }
}

public enum QuotaWarning {
    public static func events(
        in snapshots: [QuotaSnapshot],
        thresholdRemainingPercentage: Double
    ) -> [QuotaWarningEvent] {
        let threshold = min(max(thresholdRemainingPercentage, 0), 100)
        return snapshots.flatMap { snapshot in
            snapshot.buckets.compactMap { bucket in
                guard !bucket.unlimited,
                      bucket.remainingPercentage <= threshold else { return nil }
                return QuotaWarningEvent(
                    provider: snapshot.provider,
                    providerName: snapshot.displayName,
                    bucketName: bucket.name,
                    remainingPercentage: bucket.remainingPercentage,
                    resetAt: bucket.resetAt
                )
            }
        }
    }
}
