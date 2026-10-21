//
//  AcknowledgementsScreen.swift
//  EchoAssist
//
//  Settings subpage crediting the third-party code built into the app and the
//  speech models it downloads, with the notices their licenses ask for.
//
//  Sources, checked against FluidAudio b6f4a7e (the pinned revision) and the
//  Hugging Face model cards:
//  - FluidAudio: Apache 2.0, with fastcluster (BSD 2-Clause) and VBx-derived
//    code (Apache 2.0) listed in its ThirdPartyLicenses folder.
//  - Both models are FluidInference's Core ML conversions, published under
//    CC BY 4.0, of NVIDIA checkpoints released under the NVIDIA Open Model
//    License — which asks for the "Licensed by NVIDIA Corporation…" notice.
//

import SwiftUI

struct AcknowledgementsScreen: View {
    var body: some View {
        List {
            librarySection
            modelsSection
            bundledCodeSection
            licenseTextsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(EchoPalette.surface.ignoresSafeArea())
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var librarySection: some View {
        Section {
            AcknowledgementLink(
                "FluidAudio",
                subtitle: "FluidInference · Apache License 2.0",
                destination: Acknowledgement.fluidAudio
            )
        } header: {
            Text("Speech Engine")
        } footer: {
            Text("Runs the on-device speech models that produce live captions.")
        }
        .listRowBackground(EchoPalette.fillSecondary)
    }

    private var modelsSection: some View {
        Section {
            AcknowledgementLink(
                "Parakeet Unified EN 0.6B",
                subtitle: "Core ML conversion by FluidInference · CC BY 4.0\n"
                    + "Original model by NVIDIA · NVIDIA Open Model License",
                destination: Acknowledgement.parakeet
            )

            AcknowledgementLink(
                "Streaming Sortformer 4spk v2.1",
                subtitle: "Core ML conversion by FluidInference · CC BY 4.0\n"
                    + "Original model by NVIDIA · NVIDIA Open Model License",
                destination: Acknowledgement.sortformer
            )
        } header: {
            Text("Speech Models")
        } footer: {
            Text(
                "Licensed by NVIDIA Corporation under the NVIDIA Open Model License. "
                    + "The Core ML versions were converted from NVIDIA's "
                    + "parakeet-unified-en-0.6b and diar_streaming_sortformer_4spk-v2.1 "
                    + "by FluidInference and are shared under CC BY 4.0. EchoAssist "
                    + "downloads them from Hugging Face unmodified."
            )
        }
        .listRowBackground(EchoPalette.fillSecondary)
    }

    /// Code compiled into the app as part of FluidAudio. fastcluster's BSD
    /// license requires its notice to travel with binary copies, so it is
    /// reproduced in full in the footer.
    private var bundledCodeSection: some View {
        Section {
            AcknowledgementLink(
                "fastcluster",
                subtitle: "Daniel Müllner, Google Inc. · BSD 2-Clause License",
                destination: Acknowledgement.fastclusterLicense
            )

            AcknowledgementLink(
                "VBx",
                subtitle: "BUT Speech@FIT · Apache License 2.0",
                destination: Acknowledgement.vbxLicense
            )
        } header: {
            Text("Included in FluidAudio")
        } footer: {
            Text(Acknowledgement.fastclusterNotice)
        }
        .listRowBackground(EchoPalette.fillSecondary)
    }

    private var licenseTextsSection: some View {
        Section {
            AcknowledgementLink("Apache License 2.0", destination: Acknowledgement.apacheLicense)
            AcknowledgementLink("CC BY 4.0", destination: Acknowledgement.ccByLicense)
            AcknowledgementLink("NVIDIA Open Model License", destination: Acknowledgement.nvidiaLicense)
        } header: {
            Text("License Texts")
        }
        .listRowBackground(EchoPalette.fillSecondary)
    }
}

/// A row that opens its destination in the browser, drawn like the
/// "Source Code on GitHub" row in Settings.
private struct AcknowledgementLink: View {
    let title: String
    var subtitle: String?
    let destination: URL

    init(_ title: String, subtitle: String? = nil, destination: URL) {
        self.title = title
        self.subtitle = subtitle
        self.destination = destination
    }

    var body: some View {
        Link(destination: destination) {
            SettingsRow(title, subtitle: subtitle) {
                Image(systemName: "arrow.up.right")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Where each credit points. FluidAudio links are pinned to the revision the
/// app builds against, so the license shown is the one that shipped.
private enum Acknowledgement {
    private static let fluidAudioRevision = "b6f4a7e234bc2b507725f59398fa31b263ac957e"
    private static let fluidAudioTree =
        "https://github.com/FluidInference/FluidAudio/blob/\(fluidAudioRevision)"

    static let fluidAudio = url("https://github.com/FluidInference/FluidAudio")
    static let fastclusterLicense = url("\(fluidAudioTree)/ThirdPartyLicenses/fastcluster-LICENSE.md")
    static let vbxLicense = url("\(fluidAudioTree)/ThirdPartyLicenses/vbx-LICENSE.md")

    static let parakeet = url("https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml")
    static let sortformer = url("https://huggingface.co/FluidInference/diar-streaming-sortformer-coreml")

    static let apacheLicense = url("https://www.apache.org/licenses/LICENSE-2.0")
    static let ccByLicense = url("https://creativecommons.org/licenses/by/4.0/")
    static let nvidiaLicense = url(
        "https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/")

    /// Verbatim from FluidAudio's ThirdPartyLicenses/fastcluster-LICENSE.md.
    static let fastclusterNotice = """
        fastcluster — Copyright © 2011 Daniel Müllner <https://danifold.net> \
        (until version 1.1.23); all changes from version 1.1.24 on © Google Inc. \
        <https://www.google.com>. All rights reserved.

        Redistribution and use in source and binary forms, with or without \
        modification, are permitted provided that the following conditions are met: \
        Redistributions of source code must retain the above copyright notice, this \
        list of conditions and the following disclaimer. Redistributions in binary \
        form must reproduce the above copyright notice, this list of conditions and \
        the following disclaimer in the documentation and/or other materials \
        provided with the distribution.

        THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" \
        AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE \
        IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE \
        ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE \
        LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR \
        CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF \
        SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS \
        INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN \
        CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) \
        ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE \
        POSSIBILITY OF SUCH DAMAGE.
        """

    /// The addresses above are fixed literals, so a failure here is a typo
    /// caught the first time this screen is opened in development.
    private static func url(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Invalid acknowledgement URL: \(string)")
        }
        return url
    }
}

#Preview {
    NavigationStack {
        AcknowledgementsScreen()
    }
}
