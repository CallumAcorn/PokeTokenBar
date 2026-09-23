import SwiftUI

/// Read-only battle viewer — see spectator.md. Deliberately not `BattleView`'s beat-by-beat
/// animation engine (sprite flashes, paced HP drain, effect chips): that machinery exists to make
/// *your own* battle feel good to play, which isn't the ask here. A spectator gets the plain,
/// live state each poll reports, laid out on the same field/scene `BattleView` uses so this
/// doesn't read as a second, lesser app — same background-by-type art, same info-card chrome, same
/// diagonal composition. Two deliberate differences from a participant's own screen: **both**
/// sprites are front-facing (neither side is "you" here to get the real games' from-behind
/// treatment) with the left one mirrored to face the right, the way two front sprites are laid out
/// facing each other; and there's no move grid to show, so the battle log sits in that slot
/// instead, always visible rather than a toggled overlay.
struct SpectatorView: View {
    @Environment(CompanionStore.self) private var companion
    @Environment(SpectatorStore.self) private var spectator
    var onClose: () -> Void

    /// Same "load once per battle, keyed on the fixed lead species" as `BattleView`'s own
    /// `battleBackgroundImage` — reuses its terrain lookup/asset loader (`BattleView.backgroundTerrain`/
    /// `.loadBackgroundImage`, both `internal`, not `private`) rather than re-deriving the same
    /// type→terrain table a second time.
    @State private var battleBackgroundImage: NSImage?
    /// Real species names resolved to sprite ids, keyed by name — populated once per battle (see
    /// the background-loading `.task` below) from every name team preview reveals, for both info
    /// boxes and the log's per-line avatars. Necessarily name-keyed, not id-keyed: a spectator's
    /// restricted view only ever gives a *name* for anything beyond a side's current active mon
    /// (team preview text, `|switch|` lines) — resolving a real id at all needs
    /// `CompanionStore.speciesID(name:)` (network-backed, ownership-independent — unlike
    /// `speciesName(_:)`, which only knows species this viewer's own dex has already unlocked).
    @State private var speciesIDByName: [String: Int] = [:]

    private var l: L { companion.l }

    var body: some View {
        content
            .frame(width: BattleWindowMetrics.width, height: BattleWindowMetrics.height, alignment: .top)
            .padding(BattleWindowMetrics.padding)
    }

    @ViewBuilder
    private var content: some View {
        switch spectator.phase {
        case .idle, .connecting:
            ProgressView(l.spectatorConnecting)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .watching(_, let view):
            watchingContent(view)
        case .failed(.server(status: 404)):
            statusMessage(l.battleExpiredTitle)
        case .failed:
            statusMessage(l.spectatorNotStarted)
        }
    }

    private func statusMessage(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func watchingContent(_ view: BattleClient.SpectatorView) -> some View {
        if view.status == "waiting" {
            statusMessage(l.spectatorNotStarted)
        } else {
            VStack(spacing: 8) {
                topStatusBar(view)
                ZStack(alignment: .bottom) {
                    battleScene(view)
                    logPanel(view.log ?? [], p1DisplayName: view.p1?.displayName ?? "")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                // A centered modal over the still-visible (dimmed) scene/log, not a full-screen
                // takeover — unlike BattleView's own result screen, the log here is the thing this
                // whole feature is for, so it stays on screen (and reviewable) under the result
                // instead of the modal replacing it.
                .overlay { if view.status == "completed" { resultModal(view) } }
            }
            // hostLeadSpeciesID is fixed for the whole battle, same reasoning BattleView's own
            // identical .task(id:) comment gives — resolves once, not every poll. Name resolution
            // rides along here rather than its own `.task` for the same reason: team preview (the
            // only source of every name this battle will ever mention) is written to the log once,
            // right at battle start, and never changes after.
            .task(id: view.hostLeadSpeciesID) {
                guard let speciesID = view.hostLeadSpeciesID else { return }
                let type = await companion.baseStats(speciesID: speciesID)?.types.first ?? .normal
                let terrain = BattleView.backgroundTerrain(for: type)
                battleBackgroundImage = BattleView.loadBackgroundImage(terrain: terrain)

                for names in BattleClient.teamPreviewSpeciesNames(view.log ?? []).values {
                    for name in names where speciesIDByName[name] == nil {
                        if let id = await companion.speciesID(name: name) { speciesIDByName[name] = id }
                    }
                }
            }
        }
    }

    private func topStatusBar(_ view: BattleClient.SpectatorView) -> some View {
        HStack(spacing: 10) {
            Text(l.spectatorTurn(view.turn)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
        }
    }

    /// Same icon/card/shadow vocabulary as `BattleView.resultView`'s own result card (trophy,
    /// bold title on a solid theme-adaptive surface, dropped shadow) — just centered as a true
    /// modal over a dimming scrim instead of that screen's full takeover, and with no win/loss
    /// framing (`spectatorWinner`/`spectatorDraw` are already neutral — nobody watching is "you").
    private func resultModal(_ view: BattleClient.SpectatorView) -> some View {
        let (icon, tint, title): (String, Color, String) = switch view.winner {
        case "p1": ("trophy.fill", .green, l.spectatorWinner(view.p1?.displayName ?? ""))
        case "p2": ("trophy.fill", .green, l.spectatorWinner(view.p2?.displayName ?? ""))
        default: ("equal.circle.fill", .secondary, l.spectatorDraw)
        }
        return ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 34)).foregroundStyle(tint)
                Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(.primary)
                Button(l.battleDoneButton) { onClose() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(24)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        }
        .transition(.opacity)
    }

    // MARK: Scene — mirrors BattleView.battleScene's layout/chrome (background, info-card style,
    // sprite sizing/position), just fed both sides' restricted `SpectatorSide` instead of a
    // participant's you/opponent split.

    private func battleScene(_ view: BattleClient.SpectatorView) -> some View {
        let log = view.log ?? []
        return ZStack {
            battleFieldBackground
            pokemonInfoBox(name: view.p2?.displayName ?? "—", monName: Self.activeMonName(side: "p2", log: log),
                            active: view.p2?.active, benchCount: view.p2?.rosterSize ?? 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14)
            pokemonInfoBox(name: view.p1?.displayName ?? "—", monName: Self.activeMonName(side: "p1", log: log),
                            active: view.p1?.active, benchCount: view.p1?.rosterSize ?? 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.horizontal, 14).padding(.top, 14)
                .padding(.bottom, BattleWindowMetrics.actionBoxHeight + 10)
            // p2 — top-right, smaller, unmirrored (a plain front sprite already faces the viewer,
            // which reads as "facing left/inward" from this side of the field).
            spectatorSprite(speciesID: view.p2?.active?.speciesID, fainted: view.p2?.active?.fainted ?? false,
                             size: 130, mirrored: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 16).padding(.trailing, 28)
            // p1 — bottom-left, larger (same diagonal BattleView's own you/opponent sizing uses),
            // mirrored so its front sprite faces right/inward instead of out of the scene.
            spectatorSprite(speciesID: view.p1?.active?.speciesID, fainted: view.p1?.active?.fainted ?? false,
                             size: 170, mirrored: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.bottom, 130).padding(.leading, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    /// Copy of `BattleView`'s private `battleFieldBackground` — the type→terrain table/asset loader
    /// it calls into are `internal`, reused directly; only this small image-or-gradient wrapper
    /// around them is duplicated (it's `private` there, and reading its own `@State` either way).
    @ViewBuilder
    private var battleFieldBackground: some View {
        if let battleBackgroundImage {
            GeometryReader { geo in
                Image(nsImage: battleBackgroundImage)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        } else {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.68, green: 0.85, blue: 0.95), location: 0.0),
                    .init(color: Color(red: 0.80, green: 0.91, blue: 0.97), location: 0.42),
                    .init(color: Color(red: 0.56, green: 0.76, blue: 0.42), location: 0.44),
                    .init(color: Color(red: 0.44, green: 0.66, blue: 0.36), location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom)
        }
    }

    /// Copy of `BattleView`'s private `pokemonInfoBox`, minus the `conditions` badge row (the
    /// restricted `SpectatorSide`/`PublicMon` shapes carry no hazard/screen data to show one for),
    /// plus `monName` — the trainer's *own* screen never needs to spell out which mon is out
    /// (their sprite/moves already say so), but a spectator watching two strangers benefits from
    /// the reminder.
    private func pokemonInfoBox(name: String, monName: String?, active: BattleClient.PublicMon?, benchCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(.system(size: 12, weight: .bold)).lineLimit(1)
                    if let monName {
                        Text(monName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text("×\(benchCount)").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            if let active {
                HStack(spacing: 5) {
                    Text("HP").font(.system(size: 8, weight: .heavy)).italic().foregroundStyle(.orange)
                    SpectatorHPBar(fraction: active.hpFraction).frame(maxWidth: .infinity).frame(height: 7)
                        .animation(.easeInOut(duration: 0.4), value: active.hpFraction)
                }
            } else {
                Text("—").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: 190)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.22), radius: 3, y: 2))
    }

    /// Copy of `BattleView`'s private `battleSprite`, minus `BattleSpriteFlash`'s hit-flash/pulse
    /// machinery (nothing here drives a move-by-move effect to flash for) — same ground-shadow +
    /// fainted opacity/tilt treatment, plus the mirroring `battleSprite` never needed (both of its
    /// sides come from the engine's own front/back asset pair, not two front sprites needing to
    /// face each other).
    private func spectatorSprite(speciesID: Int?, fainted: Bool, size: CGFloat, mirrored: Bool) -> some View {
        VStack(spacing: -size * 0.16) {
            SpriteView(speciesID: speciesID, size: size, animated: true, facing: .front)
                .id(speciesID)
                .transition(.opacity)
                .opacity(fainted ? 0.35 : 1)
                .rotationEffect(.degrees(fainted ? 90 : 0))
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                .zIndex(1)
            Ellipse()
                .fill(Color.black.opacity(0.16))
                .frame(width: size * 0.85, height: size * 0.24)
        }
        .animation(.easeInOut(duration: 0.35), value: fainted)
    }

    // MARK: Names — team preview (`|poke|SIDE|Species, Level|`, one line per roster slot, in
    // roster order, right at battle start) and `|switch|` lines are the only places a spectator's
    // restricted view (species *id* + trainer nickname on the active mon, nothing else) ever gets
    // a real species *name* for anything — including the currently active mon, whose id alone
    // isn't enough to look up a name for a stranger's Pokémon (`CompanionStore.speciesName` only
    // knows species this viewer's own dex has unlocked). Small light duplicates of the identical
    // parses `BattleClient.teamPreviewSpeciesNames`/`BattleView`'s own beat parser already do for
    // their own callers — same "different caller, not worth sharing a type for" reasoning both of
    // those already give.


    /// The name last `|switch|<sideIdent>a: ...|<Name>, L<level>...|...` put on the field for
    /// `side` ("p1"/"p2") — always the mon currently active there, since a new switch line is the
    /// only thing that ever changes who's out.
    private static func activeMonName(side: String, log: [String]) -> String? {
        var latest: String?
        for line in log {
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 4, parts[1] == "switch", parts[2].hasPrefix(side) else { continue }
            latest = parts[3].components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
        }
        return latest
    }

    // MARK: Log — the move-grid slot's replacement. Reuses `BattleView.formattedLogLines` for the
    // readable-text conversion (internal, not private) rather than re-deriving the same "raw
    // protocol line → plain sentence" table a second time; p1 is passed as `myDisplayName` purely
    // to split lines left/right below, not because either side is privileged here.

    private func logPanel(_ log: [String], p1DisplayName: String) -> some View {
        let p1Names = BattleClient.teamPreviewSpeciesNames(log)["p1"] ?? []
        return VStack(alignment: .leading, spacing: 0) {
            Text(l.battleLogTitle).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 6)
            Divider()
            ScrollViewReader { proxy in
                let lines = BattleView.formattedLogLines(log, myDisplayName: p1DisplayName)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            logRow(line, p1Names: p1Names).id(index)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: lines.count) {
                    guard let last = lines.indices.last else { return }
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: BattleWindowMetrics.actionBoxHeight, alignment: .top)
        .background(.regularMaterial)
    }

    /// Left/right alignment (and which side's avatar shows) echoes the scene above (p1 bottom-left,
    /// p2 top-right) — `.mine(index)` (p1, since `logPanel` passes `p1DisplayName` as "mine") needs
    /// `p1Names` to turn its roster index into a name first; `.opponent` already carries one.
    /// Either can still come back `nil` from `speciesIDByName` for a beat before name resolution's
    /// own `.task` finishes — the row just shows text without an avatar until then.
    @ViewBuilder
    private func logRow(_ line: BattleView.ChatLogLine, p1Names: [String]) -> some View {
        switch line.speaker {
        case .neutral:
            Text(line.text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        case .mine(let index):
            let name = (index >= 0 && index < p1Names.count) ? p1Names[index] : nil
            logChatRow(text: line.text, speciesID: name.flatMap { speciesIDByName[$0] }, rightAligned: false)
        case .opponent(let speciesName):
            logChatRow(text: line.text, speciesID: speciesIDByName[speciesName], rightAligned: true)
        }
    }

    private func logChatRow(text: String, speciesID: Int?, rightAligned: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if !rightAligned { SpriteView(speciesID: speciesID, size: 22) }
            Text(text).font(.system(size: 10)).foregroundStyle(.primary)
            if rightAligned { SpriteView(speciesID: speciesID, size: 22) }
        }
        .frame(maxWidth: .infinity, alignment: rightAligned ? .trailing : .leading)
    }
}

/// Copy of `BattleView`'s private `HPBar` — same file-privacy reasoning `pc-detail-view.md` already
/// settled for this codebase (a light copy for a ~10-line view beats exporting a type across the
/// UI-file boundary for it).
private struct SpectatorHPBar: View {
    let fraction: Double
    private var color: Color {
        if fraction > 0.5 { return .green }
        if fraction > 0.2 { return .orange }
        return .red
    }
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.35))
                RoundedRectangle(cornerRadius: 3).fill(color)
                    .frame(width: max(0, geo.size.width * fraction))
            }
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.black.opacity(0.4), lineWidth: 0.75))
        }
    }
}
