{
  "targets": [{
    "target_name": "actionui",
    "sources": ["src/actionui_node.m"],
    "conditions": [
      ["OS=='mac'", {
        "variables": {
          "fw_dir": "<!(node -p \"process.env.ACTIONUI_FRAMEWORKS_DIR || require('path').resolve('frameworks', 'Release')\")"
        },
        "xcode_settings": {
          "MACOSX_DEPLOYMENT_TARGET": "14.6",
          "OTHER_CFLAGS": [
            "-F<(fw_dir)",
            "-mmacosx-version-min=14.6"
          ],
          "OTHER_LDFLAGS": [
            "-F<(fw_dir)",
            "-framework ActionUI",
            "-framework ActionUICAdapter",
            "-framework ActionUIAppKitApplication",
            "-framework Foundation",
            "-framework SwiftUI",
            "-framework AppKit",
            "-framework AVKit",
            "-mmacosx-version-min=14.6"
          ]
        }
      }],
      ["OS!='mac'", {
        "actions": [{
          "action_name": "abort",
          "inputs": [],
          "outputs": [],
          "action": ["sh", "-c", "echo 'ERROR: ActionUINodeJS only supports macOS' >&2; exit 1"]
        }]
      }]
    ]
  }]
}
