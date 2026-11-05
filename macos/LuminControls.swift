import AppKit

final class LuminSliderCell:NSSliderCell {
    var opacityTrack=false
    var sourcePalette=false
    func sourceTrackRect(in bounds:NSRect)->NSRect {
        opacityTrack ? NSRect(x:0,y:(bounds.height-12)/2-2,width:bounds.width,height:12):NSRect(x:-2,y:11,width:bounds.width+4,height:4)
    }
    func sourceFilledTrackRect(in bounds:NSRect)->NSRect {
        NSRect(x:-2,y:11,width:CGFloat((doubleValue-minValue)/max(0.01,maxValue-minValue))*bounds.width,height:4)
    }
    func sourceMarkColor(at index:Int)->NSColor {
        Double(index)/Double(max(1,numberOfTickMarks-1))<=(doubleValue-minValue)/(maxValue-minValue) ? NSColor.white.withAlphaComponent(0.8):PodTheme.color(0x20375A)
    }
    override func barRect(flipped:Bool)->NSRect {
        guard sourcePalette,let view=controlView else { return super.barRect(flipped:flipped) }
        return NSRect(x:0,y:11,width:view.bounds.width,height:4)
    }
    override func knobRect(flipped:Bool)->NSRect {
        guard sourcePalette,let view=controlView else { return super.knobRect(flipped:flipped) }
        let fraction=CGFloat((doubleValue-minValue)/max(0.01,maxValue-minValue))
        return NSRect(x:view.bounds.width*fraction-8,y:5,width:16,height:16)
    }
    override func draw(withFrame cellFrame:NSRect,in controlView:NSView) {
        guard sourcePalette else { super.draw(withFrame:cellFrame,in:controlView); return }
        let track=sourceTrackRect(in:controlView.bounds),path=NSBezierPath(roundedRect:track,xRadius:6,yRadius:6)
        if opacityTrack {
            NSGraphicsContext.saveGraphicsState(); path.addClip()
            NSGradient(starting:.white,ending:.black)?.draw(in:track,angle:0)
            NSColor.black.withAlphaComponent(20/255).setFill()
            for x in stride(from:track.minX,through:track.maxX,by:8) {
                for y in stride(from:track.minY,through:track.maxY,by:8) where (Int((x-track.minX)/8)+Int((y-track.minY)/8))%2==0 { NSRect(x:x,y:y,width:8,height:8).fill() }
            }
            NSGraphicsContext.restoreGraphicsState()
            LuminLegacyStyle.outline.setStroke(); path.lineWidth=1; path.stroke()
        } else {
            LuminLegacyStyle.outline.setFill(); path.fill()
            LuminLegacyStyle.variant.setFill(); NSBezierPath(roundedRect:sourceFilledTrackRect(in:controlView.bounds),xRadius:2,yRadius:2).fill()
            if numberOfTickMarks>1 {
                for index in 0..<numberOfTickMarks {
                    let x=controlView.bounds.width*CGFloat(index)/CGFloat(numberOfTickMarks-1)
                    sourceMarkColor(at:index).setFill()
                    NSBezierPath(ovalIn:NSRect(x:x-1,y:12,width:2,height:2)).fill()
                }
            }
        }
        let knob=NSBezierPath(ovalIn:knobRect(flipped:controlView.isFlipped))
        (opacityTrack ? LuminLegacyStyle.surface:LuminLegacyStyle.inverseSurface).setFill(); knob.fill()
        LuminLegacyStyle.thumbOutline.setStroke(); knob.lineWidth=1; knob.stroke()
    }
    override func drawBar(inside rect:NSRect,flipped:Bool) {
        let height:CGFloat=opacityTrack ? 12:3
        let track=NSRect(x:rect.minX,y:rect.midY-height/2,width:rect.width,height:height)
        let path=NSBezierPath(roundedRect:track,xRadius:height/2,yRadius:height/2)
        if opacityTrack {
            NSColor.white.setFill(); path.fill()
            NSGraphicsContext.saveGraphicsState(); path.addClip()
            for x in stride(from:track.minX,through:track.maxX,by:8) {
                for y in stride(from:track.minY,through:track.maxY,by:8) {
                    if (Int((x-track.minX)/8)+Int((y-track.minY)/8))%2==0 { NSColor(srgbRed:0.7,green:0.7,blue:0.7,alpha:1).setFill(); NSRect(x:x,y:y,width:8,height:8).fill() }
                }
            }
            NSGradient(starting:.clear,ending:.black)?.draw(in:track,angle:0)
            NSGraphicsContext.restoreGraphicsState()
            PodTheme.border.setStroke(); path.lineWidth=1; path.stroke()
        } else {
            PodTheme.border.setFill(); path.fill()
            let proportion=(doubleValue-minValue)/max(0.01,maxValue-minValue)
            PodTheme.secondaryText.setFill(); NSBezierPath(roundedRect:NSRect(x:track.minX,y:track.minY,width:track.width*proportion,height:height),xRadius:height/2,yRadius:height/2).fill()
        }
    }
    override func drawKnob(_ rect:NSRect) {
        let knob=NSBezierPath(ovalIn:NSRect(x:rect.midX-8,y:rect.midY-8,width:16,height:16))
        (opacityTrack ? PodTheme.canvas:PodTheme.text).setFill(); knob.fill()
        PodTheme.border.setStroke(); knob.lineWidth=1; knob.stroke()
    }
}

final class LuminSlider:NSSlider {
    init(value:Double,min:Double,max:Double,opacity:Bool=false,sourcePalette:Bool=false,height:CGFloat=32) {
        super.init(frame:.zero)
        let custom=LuminSliderCell(); custom.opacityTrack=opacity; custom.sourcePalette=sourcePalette; cell=custom
        minValue=min; maxValue=max; doubleValue=value; isContinuous=false
        heightAnchor.constraint(equalToConstant:height).isActive=true
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
}
