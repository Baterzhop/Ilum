#if canImport(SwiftUI)
import SwiftUI
import IlumCore

struct ContentView: View {
    @EnvironmentObject private var model: IlumAppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            if !model.selectedFiles.isEmpty {
                Divider()
                selectedFileBar
            }
            Divider()
            conversation
            if !model.lastCitations.isEmpty {
                Divider()
                citationBar
            }
            if let pending = model.pendingApproval {
                Divider()
                permissionPanel(pending)
            }
            Divider()
            composer
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ilum")
                    .font(.headline)
                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(model.isSafeMode ? .red : .secondary)
                Text(model.modelStatus)
                    .font(.caption2)
                    .foregroundStyle(model.modelStatus.contains("unavailable") ? .orange : .secondary)
                    .lineLimit(1)
                    .help(model.modelStatus)
            }

            if model.isMemoryAvailable {
                Label("Memory", systemImage: "brain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Durable Personal Memory is available. Writes and deletion require approval.")
            }

            if model.isKnowledgeAvailable {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Knowledge: \(model.knowledgeDocuments.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.knowledgeRetrievalStatus)
                        .font(.caption2)
                        .foregroundStyle(
                            model.knowledgeRetrievalStatus.contains("fallback")
                                ? .orange
                                : .secondary
                        )
                        .lineLimit(1)
                        .help(model.knowledgeRetrievalDetail ?? model.knowledgeRetrievalStatus)
                }
            }

            if let budget = model.lastContextBudget {
                Text("Context: \(budget.estimatedInputTokens)/\(budget.inputBudgetTokens)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Dropped history messages: \(budget.droppedMessageCount)")
            }

            Spacer()

            Button {
                model.newConversation()
            } label: {
                Label("New Chat", systemImage: "square.and.pencil")
            }
            .disabled(model.isSafeMode || model.isSending || model.pendingApproval != nil)

            Menu {
                if model.conversations.isEmpty {
                    Text("No saved conversations")
                } else {
                    ForEach(model.conversations) { summary in
                        Button {
                            model.selectConversation(summary)
                        } label: {
                            Label(
                                summary.title,
                                systemImage: model.isActiveConversation(summary)
                                    ? "checkmark.circle.fill"
                                    : "bubble.left"
                            )
                        }
                        .disabled(model.isActiveConversation(summary))
                    }
                }
            } label: {
                Label("Chats", systemImage: "bubble.left.and.bubble.right")
            }
            .disabled(model.isSafeMode || model.isSending || model.pendingApproval != nil)

            Button {
                model.selectFile()
            } label: {
                Label("Select File…", systemImage: "doc.badge.plus")
            }
            .disabled(
                model.isSafeMode ||
                model.isSending ||
                model.indexingResourceID != nil ||
                model.pendingApproval != nil
            )
        }
        .padding()
    }

    private var selectedFileBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(model.selectedFiles, id: \.id) { descriptor in
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                        Text(descriptor.displayName)
                            .lineLimit(1)

                        if model.indexingResourceID == descriptor.id {
                            ProgressView()
                                .controlSize(.small)
                        } else if model.isIndexed(descriptor) {
                            Label("Indexed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        } else if model.canIngest(descriptor) {
                            Button("Add to Knowledge") {
                                model.ingestIntoKnowledge(descriptor)
                            }
                            .buttonStyle(.borderless)
                            .disabled(model.isSending || model.pendingApproval != nil)
                        }

                        Button {
                            model.removeFile(descriptor)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove this file and its indexed Knowledge from Ilum")
                        .disabled(model.indexingResourceID != nil || model.isSending)
                    }
                    .font(.caption)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(0.45), in: Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var citationBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Label("Sources", systemImage: "books.vertical")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(model.lastCitations, id: \.label) { citation in
                    HStack(spacing: 5) {
                        Text("[\(citation.label)]")
                            .fontWeight(.semibold)
                        Text(citation.displayName)
                            .lineLimit(1)
                        Text(pageLabel(citation))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(0.45), in: Capsule())
                    .help("Chunk \(citation.chunkOrdinal + 1) · source \(citation.sourceResourceID.rawValue)")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func pageLabel(_ citation: KnowledgeCitation) -> String {
        citation.pageStart == citation.pageEnd
            ? "p. \(citation.pageStart)"
            : "pp. \(citation.pageStart)–\(citation.pageEnd)"
    }

    private var visibleMessages: [ChatMessage] {
        model.messages.filter { $0.role == .user || $0.role == .assistant }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            List(visibleMessages) { message in
                VStack(alignment: .leading, spacing: 5) {
                    Text(message.role == .user ? "You" : "Ilum")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(message.content)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
                .id(message.id)
            }
            .overlay {
                if visibleMessages.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.largeTitle)
                        Text("Ilum")
                            .font(.title2)
                        Text("Local runtime ready. Start a conversation or select a PDF.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: visibleMessages.count) { _ in
                if let last = visibleMessages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func permissionPanel(_ pending: PendingToolApproval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ilum is requesting permission")
                .font(.headline)
            Text("Tool: \(pending.toolName)@\(pending.toolVersion)")
                .font(.subheadline)

            if let displayName = pending.permission.resourceDisplayName {
                Label(displayName, systemImage: "doc")
                    .font(.subheadline)
            }
            if let location = pending.permission.resourceLocationHint {
                Text(location)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text("Capability: \(pending.permission.capability.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Scope: \(pending.permission.resource.kind.rawValue) / \(pending.permission.resource.identifier)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(pending.permission.reason)
                .font(.caption)

            HStack {
                Button("Allow once") { model.approve(.once) }
                    .disabled(model.isSending)
                if pending.permission.allowsSessionGrant {
                    Button("Allow for session") { model.approve(.session) }
                        .disabled(model.isSending)
                }
                Button("Deny", role: .cancel) { model.deny() }
                    .disabled(model.isSending)
                Spacer()
            }
        }
        .padding()
        .background(.quaternary.opacity(0.35))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message Ilum…", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)
                    .disabled(model.isSafeMode || model.isSending || model.pendingApproval != nil)
                    .onSubmit { model.send() }

                if model.canStopGeneration {
                    Button("Stop", role: .cancel) {
                        model.stopGeneration()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                } else {
                    Button("Send") { model.send() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(
                            model.isSafeMode ||
                            model.isSending ||
                            model.pendingApproval != nil ||
                            model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
            }
        }
        .padding()
    }
}
#endif
