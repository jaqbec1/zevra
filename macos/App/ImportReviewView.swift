import AttentionCore
import SwiftUI

struct ImportReviewView: View {
  @ObservedObject var model: AppModel
  @Binding var draft: ImportDraft
  @State private var pendingKey = ""

  private var selectedCount: Int { draft.materials.filter(\.selected).count }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(draft.modelGenerated ? "Review model proposals" : "Review source")
            .font(.title2.weight(.semibold))
          Text("Nothing is saved until you approve. Edit or deselect any result.")
            .font(.callout).foregroundStyle(.secondary)
        }
        Spacer()
        Button("Cancel") { model.cancelImport() }.keyboardShortcut(.cancelAction)
      }

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          HStack {
            Text("Materials · \(selectedCount) selected").font(.headline)
            Spacer()
            Button("Select all") {
              for index in draft.materials.indices { draft.materials[index].selected = true }
            }
            Button("Deselect all") {
              for index in draft.materials.indices { draft.materials[index].selected = false }
            }
          }
          ForEach($draft.materials) { $material in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Toggle("Include material", isOn: $material.selected).labelsHidden()
                  .accessibilityLabel("Include \(material.title)")
                TextField("Title", text: $material.title).accessibilityLabel("Material title")
                Text(material.original.source.rawValue).font(.caption).foregroundStyle(.secondary)
              }
              TextField("Link (optional)", text: $material.link).accessibilityLabel("Material link")
              TextField("Topic (optional)", text: $material.topic).accessibilityLabel(
                "Material topic")
            }
            .padding(12)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
          }
          if draft.modelGenerated {
            Divider()
            Text("Proposed interests").font(.headline)
            Text("Select only interests you want to add.").font(.caption).foregroundStyle(
              .secondary)
            if draft.interests.isEmpty {
              Text("No interests proposed.").foregroundStyle(.secondary)
            }
            ForEach($draft.interests) { $suggestion in
              suggestionRow($suggestion)
            }
            Divider()
            Text("Proposed intentions").font(.headline)
            Text(
              "Selected intentions will be appended to your current goals. Existing goals stay in place."
            )
            .font(.caption).foregroundStyle(.secondary)
            if draft.intentions.isEmpty {
              Text("No intentions proposed.").foregroundStyle(.secondary)
            }
            ForEach($draft.intentions) { $suggestion in
              suggestionRow($suggestion)
            }
          }
        }
        .textFieldStyle(.roundedBorder)
        .disabled(model.analyzingImport)
      }

      Divider()
      if !draft.modelGenerated && !model.demo {
        VStack(alignment: .leading, spacing: 8) {
          Text("Optional analysis with OpenAI").font(.headline)
          Text(
            "Sends only the selected titles, links and source labels shown above to OpenAI (\(ModelImport.defaultModel)). No note bodies or existing profile are sent. API usage is billed to your OpenAI account. Up to 100 materials per analysis."
          )
          .font(.caption).foregroundStyle(.secondary)
          HStack {
            if model.hasOpenAIKey {
              Label("OpenAI key saved on this Mac", systemImage: "key")
                .font(.caption)
              Button("Remove key") { model.removeOpenAIKey() }
            } else {
              SecureField("OpenAI API key", text: $pendingKey)
                .textFieldStyle(.roundedBorder)
              Button("Save key") {
                model.saveOpenAIKey(pendingKey)
                pendingKey = ""
              }.disabled(pendingKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Spacer()
            Button("Analyze with OpenAI") {
              model.analyzeImport()
            }
            .disabled(
              !model.hasOpenAIKey || model.analyzingImport || selectedCount == 0
                || selectedCount > ModelImport.maxCandidates)
          }.disabled(model.analyzingImport)
        }
      }
      if model.analyzingImport {
        HStack {
          ProgressView().controlSize(.small)
          Text("Analyzing… You can cancel at any time.")
        }
      }
      if let error = model.importError {
        Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
      }
      HStack {
        Text(
          model.demo
            ? "Demo · synthetic data, saved in memory only" : "Approved results are saved locally."
        )
        .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button(draft.modelGenerated ? "Save approved results" : "Import selected locally") {
          model.saveReviewedImport()
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.analyzingImport)
      }
    }
    .padding(24)
    .frame(width: 760, height: 650)
    .interactiveDismissDisabled(model.analyzingImport)
  }

  private func suggestionRow(_ value: Binding<ImportSuggestion>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Toggle("Accept proposal", isOn: value.selected).labelsHidden()
          .accessibilityLabel("Accept \(value.wrappedValue.text)")
        TextField("Proposal", text: value.text)
      }
      Text(
        "Based on: "
          + draft.materials.filter { value.wrappedValue.sourceIDs.contains($0.id) }.map(
            \.original.title
          ).joined(separator: "; ")
      )
      .font(.caption).foregroundStyle(.secondary)
    }
  }
}
