import SwiftUI

struct CredentialInsightsCard: View {
    let credentials: [LoginCredential]
    let onTapCredentials: () -> Void

    @State private var exclusionList = ExclusionListService.shared
    @State private var engine = ConcurrentAutomationEngine.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            readinessBar
            insightGrid
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(readinessBorderColor.opacity(0.15), lineWidth: 0.5)
                )
        )
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(NeonTheme.neonCyan)
                    Text("Credential Intel")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NeonTheme.textPrimary)
                }
                Text("Operational intelligence from \(credentials.count) credentials")
                    .font(.system(size: 10))
                    .foregroundStyle(NeonTheme.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("READY")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(NeonTheme.textTertiary)
                Text("\(eligibleCount)/\(credentials.count)")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(eligibleCount > 0 ? NeonTheme.neonGreen : NeonTheme.neonOrange)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.3), value: eligibleCount)
            }
        }
    }

    private var readinessBar: some View {
        NeonProgressBar(
            progress: credentials.isEmpty ? 0 : Double(eligibleCount) / Double(credentials.count),
            segments: readinessSegments,
            height: 4
        )
    }

    private var insightGrid: some View {
        let columns: [GridItem] = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]

        return LazyVGrid(columns: columns, spacing: 8) {
            insightPill(
                icon: "scope",
                count: untestedCount,
                label: "Untested",
                color: untestedCount > 0 ? NeonTheme.neonCyan : NeonTheme.textTertiary,
                action: onTapCredentials
            )
            insightPill(
                icon: "clock.badge.exclamationmark.fill",
                count: tempDisabledCount,
                label: "Temp Disabled",
                color: tempDisabledCount > 0 ? NeonTheme.neonOrange : NeonTheme.textTertiary,
                action: onTapCredentials
            )
            insightPill(
                icon: "lock.slash.fill",
                count: exclusionList.permCount,
                label: "Perm Excluded",
                color: exclusionList.permCount > 0 ? NeonTheme.neonRed : NeonTheme.textTertiary,
                action: onTapCredentials
            )
            insightPill(
                icon: "person.slash.fill",
                count: exclusionList.noAccountCount,
                label: "No Account",
                color: exclusionList.noAccountCount > 0 ? NeonTheme.neonIndigo : NeonTheme.textTertiary,
                action: onTapCredentials
            )
            insightPill(
                icon: "checkmark.seal.fill",
                count: successCount,
                label: "Confirmed",
                color: successCount > 0 ? NeonTheme.neonGreen : NeonTheme.textTertiary,
                action: onTapCredentials
            )
            insightPill(
                icon: "arrow.right.circle.fill",
                count: eligibleCount,
                label: "Next Run",
                color: eligibleCount > 0 ? NeonTheme.neonGreen : NeonTheme.neonOrange,
                action: onTapCredentials
            )
        }
    }

    private func insightPill(icon: String, count: Int, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(count)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                        .contentTransition(.numericText())
                    Text(label)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(NeonTheme.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(color.opacity(0.06), in: .rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var untestedCount: Int {
        credentials.filter { $0.isEnabled && $0.totalAttempts == 0 }.count
    }

    private var tempDisabledCount: Int {
        credentials.filter { $0.lastOutcome == "tempDisabled" }.count
    }

    private var successCount: Int {
        credentials.filter { $0.lastOutcome == "success" || $0.lastOutcome == "tempDisabled" }.count
    }

    private var eligibleCount: Int {
        credentials.filter { cred in
            cred.isEnabled && !exclusionList.isFullyExcluded(email: cred.username)
        }.count
    }

    private var readinessSegments: [ProgressSegment] {
        guard !credentials.isEmpty else { return [ProgressSegment(fraction: 1.0, color: NeonTheme.textTertiary)] }
        let total = Double(credentials.count)
        let eligible = Double(eligibleCount)
        let excluded = Double(exclusionList.totalCount)
        let rest = total - eligible - excluded

        var segs: [ProgressSegment] = []
        if eligible > 0 { segs.append(ProgressSegment(fraction: eligible / total, color: NeonTheme.neonGreen)) }
        if rest > 0 { segs.append(ProgressSegment(fraction: rest / total, color: NeonTheme.neonOrange)) }
        if excluded > 0 { segs.append(ProgressSegment(fraction: excluded / total, color: NeonTheme.neonRed)) }
        return segs.isEmpty ? [ProgressSegment(fraction: 1.0, color: NeonTheme.textTertiary)] : segs
    }

    private var readinessBorderColor: Color {
        if eligibleCount > 0 { return NeonTheme.neonGreen }
        if credentials.isEmpty { return NeonTheme.cardBorder }
        return NeonTheme.neonOrange
    }
}
