//
//  ExplorerHoverTooltipModifier.swift
//  FinallyExplorer
//

import SwiftUI

struct ExplorerHoverTooltipModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.explorerTheme) private var theme

    let text: String
    let alignment: Alignment

    @State private var isHovering = false
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .accessibilityHint(text)
            .onHover(perform: updateHoverState)
            .task(id: isHovering) {
                await presentAfterHoverDelay()
            }
            .simultaneousGesture(
                TapGesture().onEnded(dismissAfterActivation)
            )
            .overlay(alignment: alignment) {
                if isPresented {
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(theme.chromeText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: 220)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(theme.imperialPrimer)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(
                                    theme.accent.opacity(0.42),
                                    lineWidth: 0.75
                                )
                        }
                        .shadow(
                            color: Color.black.opacity(0.24),
                            radius: 7,
                            x: 0,
                            y: 4
                        )
                        .fixedSize()
                        .offset(y: 44)
                        .transition(
                            .opacity.combined(
                                with: .scale(scale: 0.96, anchor: .top)
                            )
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .zIndex(isPresented ? 100 : 0)
            .onDisappear(perform: reset)
    }

    private func updateHoverState(_ hovering: Bool) {
        isHovering = hovering
        if hovering == false {
            setPresented(false)
        }
    }

    private func presentAfterHoverDelay() async {
        guard isHovering else { return }

        do {
            try await Task.sleep(for: .milliseconds(350))
        } catch {
            return
        }

        guard isHovering, Task.isCancelled == false else { return }
        setPresented(true)

        do {
            try await Task.sleep(for: .seconds(3))
        } catch {
            return
        }

        guard isHovering, Task.isCancelled == false else { return }
        setPresented(false)
    }

    private func setPresented(_ presented: Bool) {
        if reduceMotion {
            isPresented = presented
        } else {
            withAnimation(.easeOut(duration: 0.12)) {
                isPresented = presented
            }
        }
    }

    private func reset() {
        isHovering = false
        isPresented = false
    }

    private func dismissAfterActivation() {
        isHovering = false
        setPresented(false)
    }
}

extension View {
    func explorerTooltip(
        _ text: String,
        alignment: Alignment = .top
    ) -> some View {
        modifier(
            ExplorerHoverTooltipModifier(
                text: text,
                alignment: alignment
            )
        )
    }
}
