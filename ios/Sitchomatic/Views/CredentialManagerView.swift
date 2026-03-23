import SwiftUI

struct CredentialManagerView: View {
    @State private var credentials: [LoginCredential] = PersistenceService.shared.loadCredentials()
    @State private var showAddSheet: Bool = false
    @State private var newUsername: String = ""
    @State private var newPassword: String = ""
    @State private var bulkText: String = ""
    @State private var showBulkImport: Bool = false
    @State private var searchText: String = ""
    @State private var exclusionList = ExclusionListService.shared

    private var filteredCredentials: [LoginCredential] {
        guard !searchText.isEmpty else { return credentials }
        return credentials.filter { $0.username.localizedStandardContains(searchText) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                credentialStatsHeader
                credentialListSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(NeonTheme.trueBlack)
        .navigationTitle("Credentials")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(NeonTheme.trueBlack, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .searchable(text: $searchText, prompt: "Search credentials")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showAddSheet = true } label: {
                        Label("Add Single", systemImage: "plus")
                    }
                    Button { showBulkImport = true } label: {
                        Label("Bulk Import", systemImage: "doc.text")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(NeonTheme.neonGreen)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            addCredentialSheet
        }
        .sheet(isPresented: $showBulkImport) {
            bulkImportSheet
        }
    }

    private var credentialStatsHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                statPill(value: "\(credentials.count)", label: "Total", color: NeonTheme.textPrimary)
                statPill(value: "\(credentials.filter(\.isEnabled).count)", label: "Enabled", color: NeonTheme.neonGreen)
                statPill(value: "\(credentials.filter { !$0.isEnabled }.count)", label: "Disabled", color: NeonTheme.textTertiary)
                statPill(value: "\(credentials.filter { $0.totalAttempts > 0 }.count)", label: "Tested", color: NeonTheme.neonCyan)
            }
            let multiPwCount = credentials.filter { $0.hasMultiplePasswords }.count
            if multiPwCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "key.2.on.ring")
                        .font(.system(size: 9))
                        .foregroundStyle(NeonTheme.neonCyan)
                    Text("\(multiPwCount) multi-password emails • Phased testing active")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(NeonTheme.neonCyan)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
    }

    private func statPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(NeonTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var credentialListSection: some View {
        LazyVStack(spacing: 8) {
            ForEach(filteredCredentials) { cred in
                credentialRow(cred)
            }
        }
    }

    private func credentialRow(_ cred: LoginCredential) -> some View {
        let isExcluded = exclusionList.isFullyExcluded(email: cred.username)
        let permSites = exclusionList.permExcludedSites(for: cred.username)
        let isNoAccount = exclusionList.isNoAccount(email: cred.username)

        return HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: cred.statusIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(credStatusColor(cred))
                    .frame(width: 28, height: 28)
                    .background(credStatusColor(cred).opacity(0.1), in: .rect(cornerRadius: 8))
                if isExcluded {
                    Image(systemName: "nosign")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 12, height: 12)
                        .background(NeonTheme.neonRed, in: Circle())
                        .offset(x: 3, y: 3)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(cred.username)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isExcluded ? NeonTheme.textTertiary : NeonTheme.textPrimary)
                        .lineLimit(1)
                    if isExcluded {
                        Text(isNoAccount ? "NO ACC" : "EXCLUDED")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(isNoAccount ? NeonTheme.neonIndigo : NeonTheme.neonRed, in: .capsule)
                    } else if !permSites.isEmpty {
                        Text(permSites.map(\.rawValue).joined(separator: ",").uppercased())
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(NeonTheme.neonOrange, in: .capsule)
                    }
                }
                HStack(spacing: 8) {
                    if cred.hasMultiplePasswords {
                        Text("\(cred.passwordCount)pw")
                            .foregroundStyle(NeonTheme.neonCyan)
                    }
                    Text("\(cred.totalAttempts) attempts")
                        .foregroundStyle(NeonTheme.textTertiary)
                    if cred.successCount > 0 {
                        Text("\(cred.successCount) success")
                            .foregroundStyle(NeonTheme.neonGreen)
                    }
                    if cred.failCount > 0 {
                        Text("\(cred.failCount) fail")
                            .foregroundStyle(NeonTheme.neonRed)
                    }
                    if let outcome = cred.lastOutcome {
                        Text(outcomeShortName(outcome))
                            .foregroundStyle(outcomeColorFromString(outcome))
                    }
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { cred.isEnabled },
                set: { newValue in
                    if let idx = credentials.firstIndex(where: { $0.id == cred.id }) {
                        credentials[idx].isEnabled = newValue
                        PersistenceService.shared.saveCredentials(credentials)
                    }
                }
            ))
            .labelsHidden()
            .tint(NeonTheme.neonGreen)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(NeonTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
        )
        .contextMenu {
            Button {
                UIPasteboard.general.string = cred.username
            } label: {
                Label("Copy Username", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                if let idx = credentials.firstIndex(where: { $0.id == cred.id }) {
                    credentials.remove(at: idx)
                    PersistenceService.shared.saveCredentials(credentials)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var addCredentialSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("USERNAME / EMAIL")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(NeonTheme.textTertiary)
                    TextField("Enter username", text: $newUsername)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(NeonTheme.textPrimary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(12)
                        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("PASSWORD")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(NeonTheme.textTertiary)
                    SecureField("Enter password", text: $newPassword)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(NeonTheme.textPrimary)
                        .padding(12)
                        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
                }

                Spacer()
            }
            .padding(20)
            .background(NeonTheme.surfaceBackground)
            .navigationTitle("Add Credential")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeonTheme.surfaceBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddSheet = false }
                        .foregroundStyle(NeonTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let cred = LoginCredential(username: newUsername, password: newPassword)
                        credentials.append(cred)
                        PersistenceService.shared.saveCredentials(credentials)
                        newUsername = ""
                        newPassword = ""
                        showAddSheet = false
                    }
                    .disabled(newUsername.isEmpty || newPassword.isEmpty)
                    .foregroundStyle(newUsername.isEmpty || newPassword.isEmpty ? NeonTheme.textTertiary : NeonTheme.neonGreen)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var bulkImportSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FORMAT: username:password (one per line)\nSame email with different passwords = auto-grouped for phased testing")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(NeonTheme.textTertiary)
                    TextEditor(text: $bulkText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(NeonTheme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 200)
                        .padding(12)
                        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NeonTheme.cardBorder, lineWidth: 0.5))
                }
                Spacer()
            }
            .padding(20)
            .background(NeonTheme.surfaceBackground)
            .navigationTitle("Bulk Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeonTheme.surfaceBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showBulkImport = false }
                        .foregroundStyle(NeonTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        importBulk()
                        showBulkImport = false
                    }
                    .foregroundStyle(NeonTheme.neonGreen)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func credStatusColor(_ cred: LoginCredential) -> Color {
        guard cred.isEnabled else { return NeonTheme.textTertiary }
        guard let outcome = cred.lastOutcome else { return NeonTheme.neonGreen }
        return outcomeColorFromString(outcome)
    }

    private func outcomeShortName(_ raw: String) -> String {
        switch raw {
        case "success": "Success"
        case "noAccount": "No ACC"
        case "permDisabled": "Perm Disabled"
        case "tempDisabled": "Temp Disabled"
        case "unsure": "Needs Review"
        case "error": "Error Found"
        default: raw
        }
    }

    private func outcomeColorFromString(_ raw: String) -> Color {
        switch raw {
        case "success": NeonTheme.neonGreen
        case "noAccount": NeonTheme.neonIndigo
        case "permDisabled": NeonTheme.neonRed
        case "tempDisabled": NeonTheme.neonOrange
        case "unsure": NeonTheme.neonPurple
        case "error": NeonTheme.neonYellow
        default: NeonTheme.textSecondary
        }
    }

    private func importBulk() {
        let lines = bulkText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        var emailPasswordMap: [String: [String]] = [:]
        var emailOrder: [String] = []

        for line in lines {
            let parts = line.components(separatedBy: ":")
            guard parts.count >= 2 else { continue }
            let username = parts[0].trimmingCharacters(in: .whitespaces)
            let password = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            guard !username.isEmpty, !password.isEmpty else { continue }

            let key = username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if emailPasswordMap[key] == nil {
                emailPasswordMap[key] = []
                emailOrder.append(key)
            }
            if !(emailPasswordMap[key]?.contains(password) ?? false) {
                emailPasswordMap[key]?.append(password)
            }
        }

        for key in emailOrder {
            guard let passwords = emailPasswordMap[key], !passwords.isEmpty else { continue }

            if let existingIdx = credentials.firstIndex(where: { $0.username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == key }) {
                for pw in passwords {
                    credentials[existingIdx].addPassword(pw)
                }
                credentials[existingIdx].password = credentials[existingIdx].passwords[0]
            } else {
                let cred = LoginCredential(
                    username: passwords.isEmpty ? key : key,
                    password: passwords[0],
                    passwords: passwords
                )
                credentials.append(cred)
            }
        }

        PersistenceService.shared.saveCredentials(credentials)
        bulkText = ""
    }
}
