import Foundation
import CoreGraphics

let defaultMascotHeight: CGFloat = 140

func resizedMascotFrame(_ frame: CGRect, height: CGFloat, aspectRatio: CGFloat,
                       anchor: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> CGRect {
    guard height.isFinite, aspectRatio.isFinite, aspectRatio > 0 else { return frame }
    let newHeight: CGFloat = min(1200, max(64, height))
    let size = CGSize(width: newHeight * aspectRatio, height: newHeight)
    let x: CGFloat = frame.minX + (frame.width - size.width) * anchor.x
    let y: CGFloat = frame.minY + (frame.height - size.height) * anchor.y
    return CGRect(origin: CGPoint(x: x, y: y), size: size)
}
