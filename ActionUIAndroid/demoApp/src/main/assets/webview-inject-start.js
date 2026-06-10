// webview-inject-start.js
// Injected at WKUserScriptInjectionTimeAtDocumentStart — runs before any page script.
// Sets window.actionUI so the page and the documentEnd script can detect the injection.

window.actionUI = {
    framework: "ActionUI",
    injectedAtStart: true,
    startTime: Date.now()
};
