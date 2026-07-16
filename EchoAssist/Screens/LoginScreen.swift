//
//  LoginScreen.swift
//  EchoAssist
//
//  Implements the "Login Screen" from Figma.
//

import SwiftUI

struct LoginScreen: View {
    var onLogin: () -> Void = {}
    var onSignUp: () -> Void = {}

    var body: some View {
        VStack {
            Spacer()

            Text("EchoAssist")
                .font(.system(.largeTitle, weight: .heavy))
                .foregroundStyle(.black)

            Spacer()

            VStack(spacing: 20) {
                Button(action: onLogin) {
                    Text("Login")
                        .font(.system(.body, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(white: 0.5))

                Button(action: onSignUp) {
                    Text("Sign up")
                        .font(.system(.body, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(white: 0.16))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 60)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

#Preview {
    LoginScreen()
}
