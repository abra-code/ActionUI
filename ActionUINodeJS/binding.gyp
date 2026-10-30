{
  "targets": [{
    "target_name": "actionui",
    "sources": ["src/actionui_node.c"],
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
            "-framework ActionUIRemote",
            "-framework Foundation",
            "-framework SwiftUI",
            "-framework AppKit",
            "-framework AVKit",
            "-framework Charts",
            "-mmacosx-version-min=14.6"
          ]
        }
      }],
      ["OS=='linux'", {
        "variables": {
          "lib_dir": "<!(node -p \"require('path').resolve(process.env.ACTIONUI_LIBRARY_DIR || 'library')\")"
        },
        "include_dirs": ["<(lib_dir)/include"],
        "cflags": ["<!@(pkg-config --cflags glib-2.0)"],
        "libraries": [
          "-L<(lib_dir)/lib",
          "-lActionUI",
          "<!@(pkg-config --libs glib-2.0)"
        ],
        "ldflags": ["-Wl,-rpath,'$$ORIGIN'", "-Wl,-z,nodelete"],
        "copies": [{
          "destination": "<(PRODUCT_DIR)",
          "files": [
            "<(lib_dir)/lib/libActionUI.so",
            "<(lib_dir)/LICENSE.txt",
            "<(lib_dir)/LICENSE-MaterialSymbols.txt"
          ]
        }]
      }],
      ["OS!='mac' and OS!='linux'", {
        "actions": [{
          "action_name": "abort",
          "inputs": [],
          "outputs": [],
          "action": ["sh", "-c", "echo 'ERROR: ActionUINodeJS supports macOS and Linux' >&2; exit 1"]
        }]
      }]
    ]
  }]
}
