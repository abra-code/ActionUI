// webview-inject-end.js
// Injected at WKUserScriptInjectionTimeAtDocumentEnd — runs after the DOM is ready.
// Updates the status banner in the demo page to confirm both injection times worked.

(function () {
    var banner = document.getElementById("actionui-banner");
    if (!banner) return;

    var startOK = window.actionUI && window.actionUI.injectedAtStart === true;
    var elapsed = (window.actionUI && window.actionUI.startTime)
        ? (Date.now() - window.actionUI.startTime) + " ms"
        : "n/a";

    if (startOK) {
        banner.textContent = "✓ documentStart injection OK  |  ✓ documentEnd injection OK  |  elapsed: " + elapsed;
        banner.style.background = "#e6f4ea";
        banner.style.color = "#1a6b2d";
        banner.style.borderColor = "#a8d5b5";
    } else {
        banner.textContent = "✗ documentStart injection missing  |  ✓ documentEnd injection OK";
        banner.style.background = "#fdecea";
        banner.style.color = "#b71c1c";
        banner.style.borderColor = "#f4b8b8";
    }
})();
