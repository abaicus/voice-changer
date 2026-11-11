import SwiftUI
import VoiceChangerKit

struct PresetSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var namePrompt: NamePrompt?
    @State private var name = ""

    private enum NamePrompt: Equatable {
        case saveNew
        case rename(id: String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accent)
                Text("Voice Changer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.top, 52)
            .padding(.leading, 16)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sectionHeader("Built-in")
                    ForEach(Preset.builtIns) { row($0) }
                    sectionHeader("My Presets")
                        .padding(.top, 14)
                    ForEach(model.customPresets) { preset in
                        row(preset)
                            .contextMenu {
                                Button("Rename…") {
                                    name = preset.name
                                    namePrompt = .rename(id: preset.id)
                                }
                                Button("Delete", role: .destructive) { model.deletePreset(id: preset.id) }
                            }
                    }
                    if model.customPresets.isEmpty {
                        Text("None saved yet")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.leading, 8)
                    }
                }
                .padding(.horizontal, 10)
            }

            VStack(spacing: 8) {
                if model.isModified {
                    HStack(spacing: 8) {
                        Button("Revert") { model.revertToPreset() }
                            .buttonStyle(PillButtonStyle())
                        if model.selectedPreset?.isBuiltIn == false {
                            Button("Update") { model.updateSelectedPreset() }
                                .buttonStyle(PillButtonStyle())
                        }
                    }
                }
                Button {
                    name = ""
                    namePrompt = .saveNew
                } label: {
                    Label("Save as New Preset…", systemImage: "plus")
                }
                .buttonStyle(PillButtonStyle())
            }
            .padding(12)

            Button {
                openWindow(id: AppInfo.aboutWindowID)
            } label: {
                Text(AppInfo.versionLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
            .accessibilityLabel("About Voice Changer, version \(AppInfo.version)")
        }
        .frame(width: Theme.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
        .alert(
            namePrompt == .saveNew ? "Save Preset" : "Rename Preset",
            isPresented: Binding(get: { namePrompt != nil }, set: { if !$0 { namePrompt = nil } })
        ) {
            TextField("Name", text: $name)
            Button("Save") { commitName() }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Theme.textTertiary)
            .padding(.leading, 8)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ preset: Preset) -> some View {
        PresetRow(
            preset: preset,
            isSelected: preset.id == model.settings.selectedPresetID,
            isModified: model.isModified,
            action: {
                if preset.id != model.settings.selectedPresetID { model.select(preset) }
            })
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        switch namePrompt {
        case .saveNew: model.saveAsNewPreset(named: trimmed)
        case .rename(let id): model.renamePreset(id: id, to: trimmed)
        case nil: break
        }
    }
}

private struct PresetRow: View {
    let preset: Preset
    let isSelected: Bool
    let isModified: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: preset.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.textSecondary))
                    .frame(width: 20)
                Text(preset.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isSelected, isModified {
                    Text("edited").font(.system(size: 11)).foregroundStyle(Theme.textTertiary).fixedSize()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: Theme.rowRadius)
                    .fill(isSelected ? Theme.rowSelected : hovering ? Theme.rowHover : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
