import SwiftUI

/// The SwiftUI content hosted by `SmartFoldersWizardWindow`. It renders the current step of the
/// view model and wires the buttons to it; it owns no wizard logic.
struct SmartFoldersWizardPanel: View {
    @Bindable var model: SmartFoldersWizardViewModel
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch model.step {
            case .selection:
                WizardSelectionStep(model: model, onClose: onClose)
            case .preview:
                WizardPreviewStep(model: model, onClose: onClose)
            case .done:
                WizardDoneStep(model: model, onClose: onClose)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Step 1: selection

private struct WizardSelectionStep: View {
    @Bindable var model: SmartFoldersWizardViewModel
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.isRerun ? "Organize Your Apps" : "Set Up Smart Folders")
                .font(.system(size: 18, weight: .semibold))

            if model.isBuilding {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(String(localized: "Analyzing your apps…"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.totalUnsortedApps == 0 {
                emptyState
            } else {
                Text(model.isRerun
                     ? String(localized: "\(model.totalUnsortedApps) apps are not in a folder yet.")
                     : String(localized: "Choose the folders to create. Apps will be added automatically."))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if model.isRerun {
                            Toggle(String(localized: "Create folders for new categories"), isOn: $model.createMissingFolders)
                                .font(.system(size: 13))
                                .padding(.vertical, 4)
                            Divider()
                        }
                        ForEach(model.categoryCounts, id: \.category) { entry in
                            HStack {
                                let available = model.isCategoryAvailable(entry.category)
                                Toggle(isOn: toggleBinding(for: entry.category)) {
                                    HStack {
                                        Text(entry.category.displayName)
                                            .font(.system(size: 13))
                                        Spacer()
                                        if !available {
                                            Text(String(localized: "No folder yet"))
                                                .font(.system(size: 11))
                                                .foregroundStyle(.tertiary)
                                        }
                                        Text("\(entry.count)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(.checkbox)
                                .disabled(!available)
                            }
                        }
                    }
                }

                if model.needsCreateMissingToProceed {
                    Text(String(localized: "Turn on \"Create folders for new categories\" to sort these apps."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if model.animationOffered {
                    Toggle(String(localized: "Play animation"), isOn: $model.showAnimation)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack {
                Button(String(localized: "Cancel"), action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Continue")) {
                    model.proceedToPreview()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canProceed)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            Text(String(localized: "Everything is already organized."))
                .font(.system(size: 14, weight: .medium))
            Text(String(localized: "No apps are waiting to be sorted."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggleBinding(for category: SmartFolderCategory) -> Binding<Bool> {
        Binding(
            get: { model.selectedCategories.contains(category) },
            set: { on in
                if on { model.selectedCategories.insert(category) }
                else { model.selectedCategories.remove(category) }
            })
    }
}

// MARK: - Step 2: preview

private struct WizardPreviewStep: View {
    @Bindable var model: SmartFoldersWizardViewModel
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Preview"))
                .font(.system(size: 18, weight: .semibold))

            if model.showAnimation {
                WizardAnimationView(plan: model.effectivePlan)
                    .frame(height: 220)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.effectivePlan.assignments
                                    .map { (category: $0.key, candidates: $0.value) }
                                    .sorted { $0.category.rawValue < $1.category.rawValue },
                            id: \.category) { category, candidates in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.displayName)
                                .font(.system(size: 13, weight: .semibold))
                            ForEach(candidates, id: \.path) { cand in
                                HStack(spacing: 6) {
                                    Image(systemName: "app")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    Text(cand.name)
                                        .font(.system(size: 12))
                                }
                            }
                        }
                    }
                }
            }

            Spacer()

            HStack {
                Button(String(localized: "Back")) {
                    model.backToSelection()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Organize")) {
                    model.apply()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Step 3: done

private struct WizardDoneStep: View {
    @Bindable var model: SmartFoldersWizardViewModel
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            if model.organizedApps == 0 {
                Text(String(localized: "Nothing needed organizing."))
                    .font(.system(size: 15, weight: .medium))
            } else {
                Text(String(localized: "Organized \(model.organizedApps) apps into \(model.organizedFolders) folders."))
                    .font(.system(size: 15, weight: .medium))
            }

            Spacer()

            HStack {
                if model.canUndo {
                    Button(String(localized: "Undo")) {
                        model.undo()
                    }
                }
                Spacer()
                Button(String(localized: "Done"), action: onClose)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Animation

/// The "apps moving into folders" flourish. Driven by a `TimelineView` clock; each app dot eases
/// from a scattered position to its folder's cluster, then into its slot, using the pure math in
/// `SmartFoldersAnimation`. Capped at `WizardMetrics.maxAnimatedApps` dots (extras simply aren't
/// drawn as moving dots — the list below always shows the full plan).
private struct WizardAnimationView: View {
    let plan: SmartFolderPlan
    @State private var start = Date()
    @State private var isFinished = false

    /// How long the whole sequence runs: the last dot starts `stagger × (count − 1)` in and then
    /// takes `duration` to settle. Used to stop the `TimelineView` once every dot is at its slot,
    /// so a lingering preview doesn't keep ticking at display refresh rate for nothing.
    private var totalDuration: Double {
        let count = min(plan.assignedCount, WizardMetrics.maxAnimatedApps)
        guard count > 0 else { return 0 }
        return WizardMetrics.animationStagger * Double(count - 1) + WizardMetrics.animationDuration
    }

    var body: some View {
        GeometryReader { geo in
            let layout = WizardAnimationLayout(plan: plan, size: geo.size)
            ZStack {
                ForEach(layout.folders) { folder in
                    Text(folder.name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .position(x: folder.center.x, y: folder.center.y - 16)
                }
                if isFinished {
                    // Static end state: every dot parked at its slot — no live timeline.
                    ForEach(layout.apps) { app in
                        Circle()
                            .fill(app.color)
                            .frame(width: 7, height: 7)
                            .position(app.slot)
                    }
                } else {
                    TimelineView(.animation) { timeline in
                        let elapsed = timeline.date.timeIntervalSince(start)
                        ForEach(layout.apps.indices, id: \.self) { i in
                            let app = layout.apps[i]
                            let t = SmartFoldersAnimation.progress(
                                elapsed: elapsed,
                                index: i,
                                duration: WizardMetrics.animationDuration,
                                stagger: WizardMetrics.animationStagger)
                            let pos = SmartFoldersAnimation.position(
                                loose: app.loose, clusterCenter: app.cluster, slot: app.slot, at: t)
                            Circle()
                                .fill(app.color)
                                .frame(width: 7, height: 7)
                                .position(pos)
                        }
                    }
                    .task {
                        // Swap to the static end state once the last dot has settled.
                        try? await Task.sleep(nanoseconds: UInt64(totalDuration * 1_000_000_000))
                        if !Task.isCancelled { isFinished = true }
                    }
                }
            }
        }
    }
}

private struct WizardAnimationFolder: Identifiable {
    let id: String
    let name: String
    let center: CGPoint
}

private struct WizardAnimationDot: Identifiable {
    let id: String
    let loose: CGPoint
    let cluster: CGPoint
    let slot: CGPoint
    let color: Color
}

/// Pure layout for the animation: where the folder clusters sit (a grid) and where each app dot
/// starts (scattered) and ends (a slot near its cluster). Kept out of the view body so the geometry
/// is deterministic and cheap to build.
private struct WizardAnimationLayout {
    let folders: [WizardAnimationFolder]
    let apps: [WizardAnimationDot]

    private static let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint, .yellow, .cyan, .red, .brown]

    init(plan: SmartFolderPlan, size: CGSize) {
        let cats: [(category: SmartFolderCategory, candidates: [SmartFolderCandidate])] = plan.assignments
            .map { (category: $0.key, candidates: $0.value) }
            .sorted { $0.category.rawValue < $1.category.rawValue }
        let n = cats.count
        let cols = max(1, Int(ceil(sqrt(Double(max(n, 1))))))
        let rows = max(1, Int(ceil(Double(n) / Double(cols))))
        let cellW = size.width / CGFloat(cols)
        let cellH = size.height / CGFloat(rows)

        var folderList: [WizardAnimationFolder] = []
        var centerByCategory: [SmartFolderCategory: CGPoint] = [:]
        for (i, (cat, _)) in cats.enumerated() {
            let row = i / cols, col = i % cols
            let center = CGPoint(x: (CGFloat(col) + 0.5) * cellW, y: (CGFloat(row) + 0.5) * cellH)
            folderList.append(WizardAnimationFolder(id: cat.rawValue, name: cat.displayName, center: center))
            centerByCategory[cat] = center
        }
        folders = folderList

        var dots: [WizardAnimationDot] = []
        var total = 0
        for (cat, candidates) in cats {
            guard let center = centerByCategory[cat] else { continue }
            for (j, cand) in candidates.enumerated() {
                if total >= WizardMetrics.maxAnimatedApps { break }
                let slot = CGPoint(
                    x: center.x + CGFloat(j % 5) * 9 - 18,
                    y: center.y + 22 + CGFloat(j / 5) * 9)
                dots.append(WizardAnimationDot(
                    id: cand.path,
                    loose: Self.scattered(index: total, in: size),
                    cluster: center,
                    slot: slot,
                    color: Self.palette[total % Self.palette.count]))
                total += 1
            }
            if total >= WizardMetrics.maxAnimatedApps { break }
        }
        apps = dots
    }

    /// A deterministic, evenly-spread "loose" position for the `index`-th dot.
    private static func scattered(index: Int, in size: CGSize) -> CGPoint {
        let fx = Double((index * 37) % 97) / 97
        let fy = Double((index * 53) % 89) / 89
        let margin: CGFloat = 14
        return CGPoint(x: margin + fx * max(0, size.width - 2 * margin),
                       y: margin + fy * max(0, size.height - 2 * margin))
    }
}
