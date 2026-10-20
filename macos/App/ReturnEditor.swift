import AttentionCore
import SwiftUI

struct ReturnEditor: View {
  @ObservedObject var model: AppModel
  let material: ReturnMaterial
  @Environment(\.dismiss) private var dismiss
  @State private var reason = ""
  @State private var goal: String?
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Return to this").font(.title2.weight(.semibold))
      if model.canReturn(material) {
        Text(material.title).font(.headline).textSelection(.enabled)
        TextField("Why return? (optional)", text: $reason, axis: .vertical)
          .lineLimit(3...6).textFieldStyle(.roundedBorder)
          .accessibilityLabel("Reason for returning, optional")
        Picker("Existing goal (optional)", selection: $goal) {
          Text("No goal selected").tag(String?.none)
          ForEach(Array(model.returnGoalLines.enumerated()), id: \.offset) { _, line in
            Text(line).tag(Optional(line))
          }
        }
        Text(
          "Your own reason comes first. Repeated saves preserve the existing reason, goal, and status."
        )
        .font(.callout).foregroundStyle(ZevraStyle.secondaryText)
        if let error { Text(error).foregroundStyle(.red) }
      } else {
        Text("This material is unavailable under your current site rules.")
      }
      HStack {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Save return") {
          if let message = model.saveReturn(material, reason: reason, goal: goal) {
            error = message
          } else {
            dismiss()
          }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!model.canReturn(material))
      }
    }
    .padding(24).frame(width: 520)
  }
}

struct ReturnLaterEditor: View {
  @ObservedObject var model: AppModel
  let entryID: String
  @Environment(\.dismiss) private var dismiss
  @State private var date = Date().addingTimeInterval(86_400)
  @State private var error: String?

  private var card: ReturnCard? {
    guard let value = model.allReturns.first(where: { $0.id == entryID }),
      case .available(let card) = value
    else { return nil }
    return card
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Return later").font(.title2.weight(.semibold))
      if let card {
        Text(card.entry.title).font(.headline)
        DatePicker(
          "Return after", selection: $date, in: Date()...,
          displayedComponents: [.date, .hourAndMinute])
        HStack {
          Button("Tomorrow") { date = Date().addingTimeInterval(86_400) }
          Button("Next week") { date = Date().addingTimeInterval(7 * 86_400) }
          if model.demo {
            Button("In a few seconds") { date = Date().addingTimeInterval(5) }
          }
        }
        Text(
          "This date changes when the material appears in Ready. Zevra will not send a reminder."
        )
        .font(.callout).foregroundStyle(ZevraStyle.secondaryText)
        if let error { Text(error).foregroundStyle(.red) }
      } else {
        Text("This return is unavailable under your current site rules.")
      }
      HStack {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Save later date") {
          if let message = model.changeReturn(entryID, to: .later(date)) {
            error = message
          } else {
            dismiss()
          }
        }
        .keyboardShortcut(.defaultAction).disabled(card == nil)
      }
    }
    .padding(24).frame(width: 520)
  }
}
