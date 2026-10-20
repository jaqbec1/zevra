import AttentionCore
import SwiftUI

struct CurrentGoalsView: View {
  @ObservedObject var model: AppModel
  var showReturns: () -> Void
  var showLibrary: () -> Void
  var showHistory: () -> Void
  var editGoals: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack(alignment: .firstTextBaseline) {
          Text("Current goals").font(.largeTitle.weight(.semibold))
          Spacer()
          Button("Edit goals", action: editGoals)
        }
        if model.returnGoalLines.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
            Text("What would you like to make room for?").font(.title3.weight(.medium))
            Text(
              "Add a goal in your own words, or save a material you want to return to. A reason and goal are optional."
            )
            .foregroundStyle(ZevraStyle.secondaryText)
            Button("Write a current goal", action: editGoals)
          }
        } else {
          Text(model.personalProfile.goals)
            .font(.title3).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        }

        VStack(alignment: .leading, spacing: 14) {
          HStack(alignment: .firstTextBaseline) {
            Text("Your returns").font(.title2.weight(.semibold))
            Spacer()
            Button("See all returns (\(model.returnEntries.count))", action: showReturns)
          }
          if model.returnsAvailability == .available {
            let ready = model.readyReturns
            if ready.isEmpty {
              Text(
                "No returns to feature now. Save something with Return to this, or visit all returns to see later and finished items."
              )
              .foregroundStyle(ZevraStyle.secondaryText)
            } else {
              Text(
                "Showing \(min(ready.count, 3)) of \(ready.count) ready to feature · \(model.returnEntries.count) saved in all states"
              )
              .font(.caption).foregroundStyle(ZevraStyle.secondaryText)
              ForEach(Array(ready.prefix(3))) { card in
                ReturnCardView(model: model, card: card)
                  .padding(14)
                  .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
              }
            }
          }
          HStack {
            Button("Browse saved materials", action: showLibrary)
            Button("Browse history", action: showHistory)
          }
          .buttonStyle(.bordered)
        }

        let estimates = model.jevEstimates
        if !estimates.isEmpty {
          Divider()
          VStack(alignment: .leading, spacing: 14) {
            Text("Jev estimates").font(.title2.weight(.semibold))
            Text("Existing model estimates. Choose what deserves a return.")
              .font(.callout).foregroundStyle(ZevraStyle.secondaryText)
            ForEach(estimates) { estimate in
              VStack(alignment: .leading, spacing: 8) {
                Text(estimate.title).font(.headline)
                if let basis = estimate.basis { Text(basis) }
                if let confidence = estimate.confidence, let worth = estimate.worth {
                  Text(
                    "Worth now \(worth.formatted(.number.precision(.fractionLength(1))))/4 · Model confidence \(Int(confidence * 100))%"
                  )
                  .font(.caption).foregroundStyle(ZevraStyle.secondaryText)
                }
                HStack {
                  Button("Return to this") {
                    model.beginReturn(ReturnMaterial(title: estimate.title, rawURL: estimate.url))
                  }
                  Button("Not worth my time") { model.rejectEstimate(estimate) }
                }
                .buttonStyle(.bordered).controlSize(.small)
              }
              .padding(14)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            }
          }
        }

        if model.demo {
          Divider()
          DisclosureGroup("Preview scenarios · memory only") {
            VStack(alignment: .leading, spacing: 10) {
              Text(
                "Fictional materials only. Reset restores the sample goal, sources, and first return."
              )
              .font(.caption).foregroundStyle(ZevraStyle.secondaryText)
              HStack {
                Button("Empty home") { model.previewEmptyHome() }
                Button("Reset demo") { model.previewResetGuidance() }
                Button("Change goal words") { model.previewChangeGoals() }
              }
              HStack {
                Button("Exclude example.com") { model.previewExcludeExample(true) }
                Button("Restore site rules") { model.previewExcludeExample(false) }
                Button("Remove saved source") { model.previewRemoveSavedSource() }
              }
            }
            .padding(.top, 8)
          }
        }
      }
      .padding(24)
      .frame(maxWidth: 900, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .onAppear { model.refreshReturns() }
  }
}
