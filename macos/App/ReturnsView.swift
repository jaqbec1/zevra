import AttentionCore
import SwiftUI

struct ReturnsView: View {
  @ObservedObject var model: AppModel
  @State private var group: ReturnGroup = .ready

  var body: some View {
    let all = model.allReturns
    let visible = all.filter { $0.state.group(at: model.returnNow) == group }
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Returns").font(.title.weight(.semibold))
          Text("\(all.count) saved · Opening a material keeps its status unchanged.")
            .foregroundStyle(ZevraStyle.secondaryText)
        }
        Spacer()
        Button("Refresh", systemImage: "arrow.clockwise") { model.refreshReturns() }
      }
      .padding(24)
      Picker("Return status", selection: $group) {
        ForEach(ReturnGroup.allCases, id: \.self) { value in
          let count = all.filter { $0.state.group(at: model.returnNow) == value }.count
          Text("\(value.rawValue) (\(count))").tag(value)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, 24).padding(.bottom, 16)
      if model.returnsAvailability == .available {
        if visible.isEmpty {
          ContentUnavailableView(
            "No \(group.rawValue.lowercased()) returns", systemImage: "bookmark",
            description: Text(
              "Use Return to this from Saved materials or Browsing history. Saving needs no goal, rating, or AI key."
            )
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(visible) { presentation in
            switch presentation {
            case .available(let card):
              ReturnCardView(model: model, card: card)
                .listRowInsets(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
            case .restricted(let id, let state):
              VStack(alignment: .leading, spacing: 10) {
                Label("Material hidden by current site rules", systemImage: "hand.raised")
                  .font(.headline)
                Text("The saved return is retained. Restore the site rules to view it again.")
                  .font(.callout).foregroundStyle(ZevraStyle.secondaryText)
                HStack {
                  if state != .letGo {
                    Button("Let go") { model.changeReturn(id, to: .letGo) }
                  }
                  Button("Remove return") { model.changeReturn(id, to: .remove) }
                }
                .buttonStyle(.bordered).controlSize(.small)
              }
              .accessibilityElement(children: .contain)
              .listRowInsets(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
            }
          }
          .listStyle(.plain).scrollContentBackground(.hidden)
        }
      } else {
        Spacer()
      }
    }
    .onAppear { model.refreshReturns() }
  }
}

struct ReturnCardView: View {
  @ObservedObject var model: AppModel
  let card: ReturnCard
  @State private var showingLater = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(card.entry.title).font(.headline).textSelection(.enabled)
      if let reason = card.entry.reason {
        Text(reason).font(.body).textSelection(.enabled)
      }
      if let goal = card.entry.goal {
        Text("\(card.earlierGoal ? "Earlier goal" : "Goal") · \(goal)")
          .font(.callout).foregroundStyle(ZevraStyle.secondaryText)
      }
      if card.sourceRemoved {
        Text("Library source removed. Showing the snapshot you saved.")
          .font(.caption).foregroundStyle(ZevraStyle.secondaryText)
      }
      if card.negativeFeedback {
        Text("You marked this not worth your time. Your explicit return is still saved here.")
          .font(.caption).foregroundStyle(ZevraStyle.secondaryText)
      }
      Text("\(card.entry.archiveID == nil ? "Saved page" : "Library material") · \(stateLabel)")
        .font(.caption).foregroundStyle(ZevraStyle.secondaryText)
      if card.entry.url == nil {
        Text("No link added. Find this material in its original source.")
          .font(.caption).foregroundStyle(ZevraStyle.secondaryText)
      }
      ViewThatFits(in: .horizontal) {
        HStack { actions }
        VStack(alignment: .leading) { actions }
      }
      .buttonStyle(.bordered).controlSize(.small)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
    .sheet(isPresented: $showingLater) {
      ReturnLaterEditor(model: model, entryID: card.id)
    }
  }

  @ViewBuilder private var actions: some View {
    Button("Open") { model.openReturn(card.id) }.disabled(card.entry.url == nil)
    switch card.entry.state {
    case .active, .deferred:
      if case .deferred = card.entry.state {
        Button("Return now") { model.changeReturn(card.id, to: .returnAgain) }
      }
      Button("Later…") { showingLater = true }
      Button("Done") { model.changeReturn(card.id, to: .done) }
      Button("Let go") { model.changeReturn(card.id, to: .letGo) }
    case .completed, .letGo:
      Button("Return again") { model.changeReturn(card.id, to: .returnAgain) }
      Button("Remove return") { model.changeReturn(card.id, to: .remove) }
    }
  }

  private var stateLabel: String {
    switch card.entry.state {
    case .active: "Ready"
    case .deferred(let until):
      until <= model.returnNow
        ? "Ready again · the later date has passed"
        : "Later · \(until.formatted(date: .abbreviated, time: .shortened))"
    case .completed: "Done"
    case .letGo: "Let go"
    }
  }
}

struct ReturnsStatusView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    if model.returnsAvailability == .unavailable || model.returnMessage != nil
      || model.hasReturnUndo
    {
      VStack(alignment: .leading, spacing: 8) {
        if model.returnsAvailability == .unavailable {
          HStack {
            Label(
              "Returns unavailable. Saved data has not been replaced.",
              systemImage: "exclamationmark.triangle")
            Spacer()
            Button("Retry returns") { model.retryReturns() }
          }
        }
        if model.returnMessage != nil || model.hasReturnUndo {
          HStack {
            Text(model.returnMessage ?? "A return change can be undone in this session.")
            Spacer()
            if model.hasReturnUndo {
              Button("Undo") { model.undoReturn() }.disabled(!model.canUndoReturn)
                .help(
                  model.canUndoReturn
                    ? "Undo the last return change"
                    : "Restore site rules before restoring hidden content")
            }
            if model.returnMessage != nil {
              Button("Dismiss", systemImage: "xmark") { model.returnMessage = nil }
                .labelStyle(.iconOnly)
            }
          }
        }
      }
      .font(.callout)
      .padding(.horizontal, 20).padding(.vertical, 12)
      .background(.bar)
    }
  }
}
