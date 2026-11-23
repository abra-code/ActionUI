// ActionUI's configuration (actionui::configure, actionui::configuration), with no window:
// every key read back, the keys a change names applied and the rest kept, and a bad change
// refused whole. Nothing in this process loads a window, so the configuration is never fixed
// here; ActionUIPython/test_configuration.py checks that against a real window.

use serde_json::json;

#[test]
fn the_configuration_changes_only_the_keys_named_and_refuses_bad_changes() {
    let initial = actionui::configuration().expect("configuration");
    let keys: Vec<&str> = initial.as_object().expect("an object").keys().map(String::as_str).collect();
    let mut sorted = keys.clone();
    sorted.sort_unstable();
    assert_eq!(sorted, ["addOns", "limits", "resourceFolder", "trust"]);
    assert_eq!(initial["limits"]["maximumJSONSize"], json!(16 * 1024 * 1024));
    assert_eq!(initial["limits"]["maximumNestingDepth"], json!(16));
    assert_eq!(initial["limits"]["maximumDownloadTime"].as_f64(), Some(120.0));

    actionui::configure(&json!({"limits": {"maximumNestingDepth": 4}, "trust": {"trustedOrigins": ["https://ui.example.com"]}}))
        .expect("a valid change");
    let changed = actionui::configuration().expect("configuration");
    assert_eq!(changed["limits"]["maximumNestingDepth"], json!(4));
    assert_eq!(changed["limits"]["maximumJSONSize"], json!(16 * 1024 * 1024), "kept");
    assert_eq!(changed["trust"]["trustedOrigins"], json!(["https://ui.example.com"]));
    actionui::configure(&json!({"limits": {"maximumDownloadTime": null}})).expect("no time limit");
    assert_eq!(actionui::configuration().expect("configuration")["limits"]["maximumDownloadTime"], json!(null));
    actionui::configure(&json!({"limits": {"maximumDownloadTime": 120}})).expect("the default again");

    // An add-on's section and the resource folder read back as they were set; null removes them.
    actionui::configure(&json!({"addOns": {"Demo": {"level": 3, "names": ["a"]}}, "resourceFolder": "/tmp/actionui-resources"}))
        .expect("add-on settings and a resource folder");
    let with_add_on = actionui::configuration().expect("configuration");
    assert_eq!(with_add_on["addOns"], json!({"Demo": {"level": 3, "names": ["a"]}}));
    assert_eq!(with_add_on["resourceFolder"], json!("/tmp/actionui-resources"));
    actionui::configure(&json!({"addOns": {"Demo": null}, "resourceFolder": initial["resourceFolder"]})).expect("removed");
    assert_eq!(actionui::configuration().expect("configuration"), changed, "back to the earlier configuration");

    for (settings, expected) in [
        (json!({"limits": {"maximumNestingDepth": 5}, "trustedOrigin": []}), "unknown configuration key trustedOrigin"),
        (json!({"limits": {"maximumJSONSize": "big"}}), "limits.maximumJSONSize must be a whole number"),
        (json!({"trust": {"trustedOrigins": ["http://ui.example.com"]}}), "is not an https address"),
        (json!([1]), "the configuration must be an object"),
    ] {
        let error = actionui::configure(&settings).expect_err("refused");
        assert!(error.to_string().contains(expected), "{settings}: {error}");
    }
    assert_eq!(actionui::configuration().expect("configuration"), changed, "the refusals changed nothing");
}
