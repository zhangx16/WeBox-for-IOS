import Foundation
import WebKit

/// Isolated, disposable Web Worker: WebAssembly support without executing source
/// computations on the app's JSContext / UI thread. CSP blocks network access.
@MainActor
final class ComputeService {
    private var jobs: [UUID: ComputeJob] = [:]
    func run(_ parameters: [String: Any]) async throws -> Any {
        let code = string(parameters["code"])
        guard !code.isEmpty, code.utf8.count <= 1024 * 1024 else { throw AppFailure("计算代码为空或超过 1 MB") }
        let raw = try jsonText(parameters)
        guard raw.utf8.count <= 24 * 1024 * 1024 else { throw AppFailure("计算输入超过 24 MB") }
        let id = UUID(), job = ComputeJob()
        jobs[id] = job
        defer { jobs.removeValue(forKey: id) }
        return try await job.run(raw, timeout: max(0.01, min(parameters["timeout"] as? Double ?? 60, 60)))
    }
    func close() { for job in jobs.values { job.cancel() }; jobs.removeAll() }
}

@MainActor
private final class ComputeJob: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private var view: WKWebView?
    private var continuation: CheckedContinuation<Any, Error>?
    private var deadline: Task<Void, Never>?
    private var raw = ""

    func run(_ raw: String, timeout: Double) async throws -> Any {
        self.raw = raw
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let config = WKWebViewConfiguration()
                config.websiteDataStore = .nonPersistent()
                config.userContentController.add(WeakComputeHandler(self), name: "compute")
                let view = WKWebView(frame: .zero, configuration: config)
                self.view = view; view.navigationDelegate = self
                deadline = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeout))
                    guard !Task.isCancelled else { return }
                    self?.finish(.failure(AppFailure("独立计算超时，Worker 已终止")))
                }
                view.loadHTMLString(Self.html, baseURL: nil)
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel() } }
    }
    func cancel() { finish(.failure(CancellationError())) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard continuation != nil else { return }
        webView.evaluateJavaScript("__runIOSCompute(" + raw + ");") { [weak self] _, error in
            if let error { self?.finish(.failure(error)) }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(.failure(AppFailure("独立计算进程已结束"))) }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let reply = message.body as? [String: Any] else { return }
        if reply["ok"] as? Bool == true { finish(.success(reply["value"] ?? NSNull())) }
        else { finish(.failure(AppFailure(string(reply["error"]).isEmpty ? "独立计算失败" : string(reply["error"])))) }
    }
    private func finish(_ result: Result<Any, Error>) {
        guard let continuation else { return }
        self.continuation = nil; deadline?.cancel(); deadline = nil
        view?.evaluateJavaScript("if(window.__computeWorker)window.__computeWorker.terminate();")
        view?.stopLoading(); view?.configuration.userContentController.removeScriptMessageHandler(forName: "compute")
        view?.navigationDelegate = nil; view = nil
        continuation.resume(with: result)
    }
    private static let html = """
    <!doctype html><html><head><meta charset="utf-8">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval' blob:; worker-src blob:; connect-src 'none'; img-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'">
    </head><body><script>
    const workerSource = `self.onmessage=async function(event){try{
      const request=event.data,binaries=Object.create(null);
      for(const [name,value] of Object.entries(request.binaries||{})){
        const raw=atob(value),bytes=new Uint8Array(raw.length);
        for(let i=0;i<raw.length;i++)bytes[i]=raw.charCodeAt(i);
        binaries[name]=bytes;
      }
      const invoke=new Function('input','binaries','"use strict";return ('+request.code+')(input,binaries);');
      const value=await invoke(request.input,binaries);
      const reply=JSON.stringify({ok:true,value:value===undefined?null:value});
      if(reply.length>1024*1024)throw Error('计算结果超过 1 MiB');
      self.postMessage(JSON.parse(reply));
    }catch(error){self.postMessage({ok:false,error:String(error&&error.message||error).slice(0,512)});}};`;
    function __runIOSCompute(request){
      const url=URL.createObjectURL(new Blob([workerSource],{type:'text/javascript'}));
      const worker=new Worker(url);URL.revokeObjectURL(url);window.__computeWorker=worker;
      worker.onmessage=function(event){worker.terminate();webkit.messageHandlers.compute.postMessage(event.data);};
      worker.onerror=function(event){event.preventDefault();worker.terminate();webkit.messageHandlers.compute.postMessage({ok:false,error:String(event.message||'Worker 启动失败')});};
      worker.postMessage(request);
    }
    </script></body></html>
    """
}
@MainActor
private final class WeakComputeHandler: NSObject, WKScriptMessageHandler {
    weak var owner: ComputeJob?
    init(_ owner: ComputeJob) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { owner?.userContentController(userContentController, didReceive: message) }
}
