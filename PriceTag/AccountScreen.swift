//
//  AccountScreen.swift
//  PriceTag
//
//  The sign-in sheet: sign in or create an account, wait for approval, see who you are.
//

import SwiftUI

/// The small button on the Library screen that opens the account sheet.
struct AccountChip: View {
    @EnvironmentObject var auth: AuthStore
    @State private var showing = false

    private var title: String {
        switch auth.state {
        case .unknown:          return "Account"
        case .signedOut:        return "Sign in"
        case .pending:          return "Waiting for approval"
        case .removed:          return "Account"
        case .active(let who):  return who.name
        }
    }

    private var tint: Color {
        switch auth.state {
        case .active:   return Color.green
        case .pending:  return Color.orange
        default:        return Color.white.opacity(0.8)
        }
    }

    var body: some View {
        Button(action: { showing = true }) {
            Text(title)
                .font(pt(12, .medium))
                .foregroundColor(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.ptInset)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) { AccountSheet() }
    }
}

/// A password row to match `FieldRow`.
private struct PasswordRow: View {
    @Binding var text: String
    var last: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Password")
                    .font(pt(14))
                    .foregroundColor(Color.white.opacity(0.5))
                    .frame(width: 78, alignment: .leading)
                SecureField("", text: $text, prompt:
                    Text("6 or more characters").foregroundColor(Color.white.opacity(0.28))
                )
                .font(pt(15, .medium))
                .foregroundColor(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            if !last {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            }
        }
    }
}

struct AccountSheet: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var sync: SyncEngine
    @State private var unsentWarning = false
    @Environment(\.dismiss) private var dismiss

    @State private var creating = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            Color.ptBG.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Account")
                            .font(pt(34, .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Button("Done") { dismiss() }
                            .font(pt(15, .semibold))
                            .foregroundColor(.ptAccent)
                    }
                    .padding(.top, 8)

                    content

                    if let problem = auth.message {
                        Text(problem)
                            .font(pt(13))
                            .foregroundColor(Color.red.opacity(0.9))
                    }
                    if let note = auth.notice {
                        Text(note)
                            .font(pt(13))
                            .foregroundColor(Color.green.opacity(0.9))
                    }

                    Text("Signing in is optional for now. Your signs on this phone are not shared yet, and the app works the same without an account.")
                        .font(pt(12))
                        .foregroundColor(.ptDim)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { auth.message = nil; auth.notice = nil }
        .alert("Some changes have not synced", isPresented: $unsentWarning) {
            Button("Sign out anyway", role: .destructive) {
                Task { _ = await sync.signOut(force: true) }
            }
            Button("Stay signed in", role: .cancel) {}
        } message: {
            Text("\(sync.pendingChanges) change(s) on this phone could not be sent yet. Signing out now loses them.")
        }
    }

    private func signOut() {
        Task {
            let done = await sync.signOut()
            if !done { unsentWarning = true }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch auth.state {
        case .unknown:
            VStack(alignment: .leading, spacing: 12) {
                if auth.busy {
                    ProgressView().tint(.white)
                    Text("Checking your account…").font(pt(14)).foregroundColor(.ptMid)
                } else {
                    Text("Could not check your account yet.").font(pt(14)).foregroundColor(.ptMid)
                    PillButton(title: "Try again", filled: true) { Task { await auth.refresh() } }
                    PillButton(title: "Sign out") { signOut() }
                }
            }
        case .signedOut:
            signedOutForm
        case .pending:
            statusCard(
                title: "Waiting for approval",
                text: "An admin at \(Backend.businessName) has to let you in. Ask them to open the app and approve you, then tap Check again.")
        case .removed:
            statusCard(
                title: "No access",
                text: "An admin removed this account from \(Backend.businessName). Ask them if that is a mistake.")
        case .active(let who):
            activeCard(who)
        }
    }

    // MARK: Signed out

    private var signedOutForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $creating) {
                Text("Sign in").tag(false)
                Text("Create account").tag(true)
            }
            .pickerStyle(.segmented)

            CardGroup {
                if creating {
                    FieldRow(label: "Name", text: $name, placeholder: "As coworkers know you")
                }
                FieldRow(label: "Email", text: $email, placeholder: "you@example.com", keyboard: .emailAddress)
                PasswordRow(text: $password, last: true)
            }

            if auth.busy {
                ProgressView().tint(.white).frame(maxWidth: .infinity)
            } else {
                PillButton(title: creating ? "Create account" : "Sign in", filled: true) {
                    Task {
                        if creating {
                            await auth.signUp(email: email, password: password, name: name)
                        } else {
                            await auth.signIn(email: email, password: password)
                        }
                    }
                }
            }

            if creating {
                Text("After you create an account, an admin at \(Backend.businessName) has to approve you before you can use the shared Library.")
                    .font(pt(12))
                    .foregroundColor(.ptDim)
            }
        }
    }

    // MARK: Signed in

    private func statusCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            CardGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(pt(17, .semibold)).foregroundColor(.white)
                    Text(text).font(pt(14)).foregroundColor(.ptMid)
                    if let address = auth.email {
                        Text(address).font(pt(12)).foregroundColor(.ptDim)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            if auth.busy {
                ProgressView().tint(.white).frame(maxWidth: .infinity)
            } else {
                PillButton(title: "Check again", filled: true) { Task { await auth.refresh() } }
            }
            PillButton(title: "Sign out") { signOut() }
        }
    }

    private func activeCard(_ who: Account) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            CardGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Overline(text: Backend.businessName)
                    Text(who.name).font(pt(20, .semibold)).foregroundColor(.white)
                    Text(who.isAdmin ? "Admin" : "Member").font(pt(14)).foregroundColor(.ptMid)
                    if let address = auth.email {
                        Text(address).font(pt(12)).foregroundColor(.ptDim)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            SyncSection()
            if who.isAdmin {
                PeopleSection()
            }
            PillButton(title: "Sign out") { signOut() }
        }
    }
}

/// Whether the Library is in step with the shared one.
private struct SyncSection: View {
    @EnvironmentObject var sync: SyncEngine

    private var line: String {
        switch sync.status {
        case .syncing:
            return "Syncing…"
        case .offline:
            return "Offline. Changes are kept here and sent when you are back online."
        case .problem(let text):
            return text
        case .idle:
            guard let when = sync.lastSynced else { return "Not synced yet." }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "Synced " + formatter.localizedString(for: when, relativeTo: Date()) + "."
        }
    }

    private var isProblem: Bool {
        if case .problem = sync.status { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Overline(text: "Shared Library")
            CardGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Text(line)
                        .font(pt(14))
                        .foregroundColor(isProblem ? Color.orange : Color.white.opacity(0.7))
                    if sync.pendingChanges > 0 {
                        Text("\(sync.pendingChanges) change(s) waiting to be sent.")
                            .font(pt(12)).foregroundColor(.ptDim)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            if sync.status != .syncing {
                PillButton(title: "Sync now") { Task { await sync.sync() } }
            }
        }
        .padding(.top, 4)
    }
}

/// Admins only: let people in, remove them, and choose who else is an admin.
private struct PeopleSection: View {
    @EnvironmentObject var auth: AuthStore
    @State private var confirmRemove: AuthStore.Person?

    private func rows(_ status: String) -> [AuthStore.Person] {
        return auth.people.filter { $0.status == status }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Overline(text: "People")
                .padding(.top, 8)

            if !rows("pending").isEmpty {
                group("Waiting for approval", rows("pending"))
            }
            group("In \(Backend.businessName)", rows("active"))
            if !rows("removed").isEmpty {
                group("Removed", rows("removed"))
            }
        }
        .task { await auth.loadPeople() }
        .alert("Remove this person?", isPresented: Binding(
            get: { confirmRemove != nil },
            set: { if !$0 { confirmRemove = nil } }
        ), presenting: confirmRemove) { person in
            Button("Remove", role: .destructive) { Task { await auth.remove(person) } }
            Button("Cancel", role: .cancel) {}
        } message: { person in
            Text("\(person.name) loses access to the shared Library straight away. You can let them back in later.")
        }
    }

    private func group(_ title: String, _ people: [AuthStore.Person]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(pt(12, .medium)).foregroundColor(.ptDim)
            CardGroup {
                ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                    row(person)
                    if index < people.count - 1 {
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                    }
                }
            }
        }
    }

    private func row(_ person: AuthStore.Person) -> some View {
        let isMe = person.userID == auth.myID
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name + (isMe ? " (you)" : ""))
                    .font(pt(15, .medium)).foregroundColor(.white)
                Text(person.status == "active" ? (person.role == "admin" ? "Admin" : "Member") : person.status.capitalized)
                    .font(pt(12)).foregroundColor(.ptDim)
            }
            Spacer()
            if isMe {
                EmptyView()
            } else if person.status == "pending" || person.status == "removed" {
                Button(person.status == "pending" ? "Approve" : "Let back in") {
                    Task { await auth.approve(person) }
                }
                .font(pt(13, .semibold)).foregroundColor(.ptAccent)
                if person.status == "pending" {
                    Button("Decline") { Task { await auth.remove(person) } }
                        .font(pt(13)).foregroundColor(.ptMid)
                }
            } else {
                Menu {
                    if person.role == "admin" {
                        Button("Make member") { Task { await auth.setRole(person, to: .member) } }
                    } else {
                        Button("Make admin") { Task { await auth.setRole(person, to: .admin) } }
                    }
                    Button("Remove", role: .destructive) { confirmRemove = person }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 20)).foregroundColor(.ptMid)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
