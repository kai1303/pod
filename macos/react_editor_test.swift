import AppKit
import WebKit

@main
struct ReactEditorTest {
    static func main() throws {
        let app=NSApplication.shared; app.setActivationPolicy(.accessory); app.finishLaunching()
        let resources=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let scroll=NSScrollView(); scroll.documentView=NSView(frame:NSRect(x:0,y:0,width:900,height:1200))
        let host=ReactEditor(resources:resources,canvas:scroll)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1240,height:800),styleMask:[.titled],backing:.buffered,defer:false)
        window.contentView=host; window.orderBack(nil)
        var commands:[String]=[]
        host.onCommand={ name,data in commands.append(name); if name=="tool",let tool=data["name"] as? String { host.setState(["tool":tool]) } }
        host.setState(["documentName":"Native fixture.pdf","previewRevision":"fixture","totalPages":2,"page":1,"canSave":true,"canOpen":true,"canUndo":true,"busy":false,"status":"Native bridge test"])
        func wait(_ label:String,_ condition:()->Bool) {
            let deadline=Date().addingTimeInterval(10)
            while !condition() && Date()<deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.02)) }
            guard condition() else {
                fputs("FAILED: \(label)\n",stderr)
                var inspected=false
                host.webView.evaluateJavaScript("JSON.stringify({url:location.href,native:window.__POD_NATIVE__,root:document.getElementById('root')?.innerHTML.slice(0,400),scripts:Array.from(document.scripts).map(s=>s.src),overlays:Array.from(document.querySelectorAll('[role=menu],[role=dialog],[role=tooltip],[role=listbox]')).map(e=>({role:e.getAttribute('role'),state:e.getAttribute('data-state'),text:e.textContent.slice(0,120)}))})") { value,error in print("DOM diagnostic:",value ?? "nil",error as Any); inspected=true }
                let end=Date().addingTimeInterval(3); while !inspected && Date()<end { RunLoop.current.run(until:Date().addingTimeInterval(0.02)) }
                exit(1)
            }
        }
        func js(_ source:String)->Any? {
            var done=false,result:Any?,failure:Error?
            host.webView.evaluateJavaScript(source) { value,error in result=value; failure=error; done=true }
            wait("JavaScript completion",{done})
            if let failure { fputs("JavaScript failed: \(failure)\n",stderr); exit(1) }
            return result
        }
        wait("bundled editor loaded and native viewport placed",{!scroll.isHidden && scroll.frame.width>100})
        wait("native document state applied",{js("document.querySelector('.editor-document-name').textContent.includes('Native fixture.pdf')") as? Bool == true})
        assert(scroll.superview === host && scroll.frame.minY>=90)
        _=js("document.querySelector('[aria-label=\"Draw\"]').click();true")
        wait("native tool command",{commands.contains("tool")})
        _=js("document.querySelector('[aria-label=\"File menu\"]').dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowDown',bubbles:true}));true")
        wait("native canvas yields to web menus",{scroll.isHidden})
        assert(js("!!document.querySelector('[role=menu]')") as? Bool == true)
        _=js("document.querySelector('[role=menuitem]').click();true")
        wait("native canvas returns after menu dismissal",{!scroll.isHidden})
        _=js("""
            document.querySelector('[aria-label="Page view"]').dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowDown',bubbles:true})); true
            """)
        wait("page view choices", { js("!!document.querySelector('[role=menuitemradio]')") as? Bool == true })
        _=js("Array.from(document.querySelectorAll('[role=menuitemradio]')).find(item => item.textContent.trim()==='Two pages').click();true")
        wait("two-page spread appears", { js("document.querySelectorAll('.reading-grid [data-page]').length===2") as? Bool == true })
        _=js("document.querySelector('[role=menu]').dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));true")
        _=js("document.querySelector('[aria-label=Select]').click();true")
        wait("native canvas restored after page view change", { !scroll.isHidden && js("!document.querySelector('.reading-pages, [data-transitioning]')") as? Bool == true })
        _=js("document.querySelector('.editor-header-end button:last-child').click();true")
        wait("native save action",{commands.contains("save")})
        print("PASS: bundled WKWebView, document state, native canvas placement, tool/save bridge, menu occlusion and restoration (no screenshots)")
        window.orderOut(nil)
        host.webView.configuration.userContentController.removeScriptMessageHandler(forName:"pod")
    }
}
