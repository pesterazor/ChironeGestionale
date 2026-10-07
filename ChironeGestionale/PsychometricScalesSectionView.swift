import SwiftUI

// Aggiungere nuovi questionari: 1) creare modello + ScaleContent view,
// 2) aggiungere un case qui sotto, 3) aggiungere il branch nello switch in body.
enum PsychometricScale: String, CaseIterable, Identifiable {
    case phq9
    case gad7
    case mdq
    case bai
    case bdiII
    case madrs

    var id: String { rawValue }

    var pickerLabel: String {
        switch self {
        case .phq9: return "PHQ-9"
        case .gad7: return "GAD-7"
        case .mdq: return "MDQ"
        case .bai: return "BAI"
        case .bdiII: return "BDI-II"
        case .madrs: return "MADRS"
        }
    }

    var scaleDescription: String {
        switch self {
        case .phq9: return "Depressione"
        case .gad7: return "Ansia"
        case .mdq: return "Disturbi bipolari"
        case .bai: return "Ansia · Beck"
        case .bdiII: return "Depressione · Beck"
        case .madrs: return "Depressione · clinico"
        }
    }
}

struct PsychometricScalesSectionView: View {
    @Bindable var patient: Patient
    @State private var selectedScale: PsychometricScale = .phq9

    var body: some View {
        ClinicalSectionBox("Scale psicometriche", systemImage: "list.clipboard") {
            VStack(alignment: .leading, spacing: ClinicalSpacing.m) {
                scalePicker

                Divider()

                switch selectedScale {
                case .phq9:
                    PHQ9ScaleContent(patient: patient)
                case .gad7:
                    GAD7ScaleContent(patient: patient)
                case .mdq:
                    MDQScaleContent(patient: patient)
                case .bai:
                    BeckScaleContent(patient: patient, scale: .bai)
                        .id(BeckScale.bai)
                case .bdiII:
                    BeckScaleContent(patient: patient, scale: .bdiII)
                        .id(BeckScale.bdiII)
                case .madrs:
                    MADRSScaleContent(patient: patient)
                }
            }
        }
    }

    private var scalePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ClinicalSpacing.s) {
                ForEach(PsychometricScale.allCases) { scale in
                    Button {
                        selectedScale = scale
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scale.pickerLabel)
                                .font(.subheadline.weight(.semibold))
                            Text(scale.scaleDescription)
                                .font(.caption2)
                                .foregroundStyle(selectedScale == scale ? .white.opacity(0.80) : .secondary)
                        }
                        .padding(.horizontal, ClinicalSpacing.m)
                        .padding(.vertical, ClinicalSpacing.s)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedScale == scale ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    selectedScale == scale ? Color.clear : Color.secondary.opacity(0.20),
                                    lineWidth: 1
                                )
                        )
                        .foregroundStyle(selectedScale == scale ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("psychometric_scale_\(scale.rawValue)")
                }
            }
        }
    }
}
