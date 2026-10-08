// Compares the hand-written declarations in src/lib.rs with the C declarations in the
// generated headers of the frameworks being linked. Fails when a function exists on one
// side only, or when its parameters or return type differ.
//
// The generated headers name the enums and the callback types but do not define them;
// those are compared with the hand-written C headers the frameworks ship beside them.

#![cfg(target_os = "macos")]

use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

const HEADERS: [&str; 3] = [
    "ActionUICAdapter.framework/Headers/ActionUICAdapter-Swift.h",
    "ActionUIAppKitApplication.framework/Headers/ActionUIAppKitApplication-Swift.h",
    "ActionUIRemote.framework/Headers/ActionUIRemote-Swift.h",
];

const TYPE_HEADERS: [&str; 2] = [
    "ActionUICAdapter.framework/Headers/ActionUIC.h",
    "ActionUIAppKitApplication.framework/Headers/ActionUIApp.h",
];

const RUST_SOURCE: &str = include_str!("../src/lib.rs");

/// A function reduced to comparable text: `name(param: type, ...) -> type`.
type Signatures = BTreeMap<String, String>;

fn rust_type_for_c(c_type: &str) -> String {
    // "char*" and "char *" are the same type.
    let cleaned = c_type.replace("_Nonnull", "").replace("_Nullable", "").replace('*', " * ");
    let normalized = cleaned.split_whitespace().collect::<Vec<_>>().join(" ");
    match normalized.as_str() {
        "void" => "",
        "bool" => "bool",
        "int64_t" => "i64",
        "double" => "f64",
        "NSInteger" => "isize",
        "char const *" => "*const c_char",
        "const char *" => "*const c_char",
        "char *" => "*mut c_char",
        "void *" => "*mut c_void",
        "bool *" => "*mut bool",
        "double *" => "*mut f64",
        "int64_t *" => "*mut i64",
        // Enums and callback types have the same name on both sides.
        other => other,
    }
    .to_string()
}

/// Splits "type name" at the last identifier.
fn split_trailing_identifier(text: &str) -> (&str, &str) {
    let text = text.trim();
    let start = text
        .rfind(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
        .map(|index| index + 1)
        .unwrap_or(0);
    (text[..start].trim(), &text[start..])
}

fn signature(name: &str, params: &[(String, String)], return_type: &str) -> String {
    let list = params
        .iter()
        .map(|(param_name, param_type)| format!("{param_name}: {param_type}"))
        .collect::<Vec<_>>()
        .join(", ");
    if return_type.is_empty() {
        format!("{name}({list})")
    } else {
        format!("{name}({list}) -> {return_type}")
    }
}

fn header_signatures(frameworks_dir: &Path) -> Signatures {
    let mut signatures = Signatures::new();
    for header in HEADERS {
        let path = frameworks_dir.join(header);
        let text = fs::read_to_string(&path)
            .unwrap_or_else(|error| panic!("cannot read {}: {error}", path.display()));
        // A universal framework's header repeats every declaration once per architecture;
        // the map keeps one.
        for line in text.lines() {
            let Some(declaration) = line.strip_prefix("SWIFT_EXTERN ") else {
                continue;
            };
            let open = declaration.find('(').expect("declaration has a parameter list");
            let close = declaration.rfind(')').expect("declaration has a parameter list");
            let (return_c_type, name) = split_trailing_identifier(&declaration[..open]);
            let params_text = declaration[open + 1..close].trim();
            let mut params = Vec::new();
            if params_text != "void" && !params_text.is_empty() {
                for param in params_text.split(',') {
                    let (param_c_type, param_name) = split_trailing_identifier(param);
                    params.push((param_name.to_string(), rust_type_for_c(param_c_type)));
                }
            }
            signatures.insert(
                name.to_string(),
                signature(name, &params, &rust_type_for_c(return_c_type)),
            );
        }
    }
    signatures
}

fn rust_signatures() -> Signatures {
    let mut signatures = Signatures::new();
    for line in RUST_SOURCE.lines() {
        let Some(declaration) = line.trim().strip_prefix("pub fn ") else {
            continue;
        };
        let declaration = declaration.trim_end_matches(';');
        let open = declaration.find('(').expect("declaration has a parameter list");
        let close = declaration.rfind(')').expect("declaration has a parameter list");
        let name = &declaration[..open];
        let return_type = declaration[close + 1..].trim().trim_start_matches("->").trim();
        let mut params = Vec::new();
        let params_text = declaration[open + 1..close].trim();
        if !params_text.is_empty() {
            for param in params_text.split(',') {
                let (param_name, param_type) = param.split_once(':').expect("parameter has a type");
                params.push((param_name.trim().to_string(), param_type.trim().to_string()));
            }
        }
        signatures.insert(name.to_string(), signature(name, &params, return_type));
    }
    signatures
}

fn differences(in_headers: &Signatures, in_rust: &Signatures) -> Vec<String> {
    let mut problems = Vec::new();
    for (name, header_signature) in in_headers {
        match in_rust.get(name) {
            None => problems.push(format!("missing in src/lib.rs: {header_signature}")),
            Some(rust_signature) if rust_signature != header_signature => problems.push(format!(
                "differs:\n    header: {header_signature}\n    rust:   {rust_signature}"
            )),
            Some(_) => {}
        }
    }
    for (name, rust_signature) in in_rust {
        if !in_headers.contains_key(name) {
            problems.push(format!("not in any header: {rust_signature}"));
        }
    }
    problems
}

#[test]
fn declarations_match_the_framework_headers() {
    let frameworks_dir = Path::new(env!("ACTIONUI_SYS_FRAMEWORKS_DIR"));
    let in_headers = header_signatures(frameworks_dir);
    let in_rust = rust_signatures();

    assert!(
        in_headers.len() > 50,
        "only {} declarations found in the headers under {}; the header format may have changed",
        in_headers.len(),
        frameworks_dir.display()
    );

    let problems = differences(&in_headers, &in_rust);
    assert!(
        problems.is_empty(),
        "src/lib.rs and the framework headers disagree:\n{}",
        problems.join("\n")
    );
}

// MARK: - Enums and callback types

fn without_comments(text: &str) -> String {
    let mut code = String::new();
    let mut rest = text;
    while let Some(start) = rest.find("/*") {
        code.push_str(&rest[..start]);
        let end = rest[start..].find("*/").expect("block comment is closed");
        rest = &rest[start + end + 2..];
    }
    code.push_str(rest);
    code.lines()
        .map(|line| line.split("//").next().unwrap_or(""))
        .collect::<Vec<_>>()
        .join("\n")
}

/// `ActionUILogLevelError` -> `ACTIONUI_LOG_LEVEL_ERROR`.
fn rust_constant_name(c_name: &str) -> String {
    let mut name = String::from("ACTIONUI");
    for c in c_name.strip_prefix("ActionUI").unwrap_or(c_name).chars() {
        if c.is_ascii_uppercase() {
            name.push('_');
        }
        name.push(c.to_ascii_uppercase());
    }
    name
}

fn callback_type(name: &str, params: &[String], return_type: &str) -> String {
    let list = params.join(", ");
    if return_type.is_empty() {
        format!("type {name} = fn({list})")
    } else {
        format!("type {name} = fn({list}) -> {return_type}")
    }
}

/// The text between each occurrence of `keyword` and the `;` that ends the statement.
fn statements<'a>(code: &'a str, keyword: &str) -> Vec<&'a str> {
    let mut found = Vec::new();
    let mut rest = code;
    while let Some(start) = rest.find(keyword) {
        let after = &rest[start + keyword.len()..];
        let end = after.find(';').expect("statement ends with a semicolon");
        found.push(after[..end].trim());
        rest = &after[end + 1..];
    }
    found
}

/// Every enum, enum value and callback type in the C headers, as comparable text:
/// `type Name = enum`, `const NAME: Type = value`, `type Name = fn(type, ...) -> type`.
fn header_types(frameworks_dir: &Path) -> Signatures {
    let mut types = Signatures::new();
    for header in TYPE_HEADERS {
        let path = frameworks_dir.join(header);
        let text = fs::read_to_string(&path)
            .unwrap_or_else(|error| panic!("cannot read {}: {error}", path.display()));
        let code = without_comments(&text);
        for body in statements(&code, "typedef ") {
            if let Some(enum_body) = body.strip_prefix("enum") {
                let open = enum_body.find('{').expect("enum has a body");
                let close = enum_body.rfind('}').expect("enum has a body");
                let name = enum_body[close + 1..].trim();
                types.insert(name.to_string(), format!("type {name} = enum"));
                for entry in enum_body[open + 1..close].split(',') {
                    let entry = entry.trim();
                    if entry.is_empty() {
                        continue;
                    }
                    let (c_name, value) = entry.split_once('=').expect("enum value is written out");
                    let constant = rust_constant_name(c_name.trim());
                    types.insert(constant.clone(), format!("const {constant}: {name} = {}", value.trim()));
                }
            } else {
                // return_type (*Name)(parameters)
                let star = body.find("(*").expect("typedef is a function pointer");
                let name_end = star + body[star..].find(')').expect("typedef is a function pointer");
                let name = body[star + 2..name_end].trim();
                let params_text = body[name_end + 1..]
                    .trim()
                    .strip_prefix('(')
                    .and_then(|list| list.strip_suffix(')'))
                    .expect("function pointer has a parameter list")
                    .trim();
                let mut params = Vec::new();
                if params_text != "void" && !params_text.is_empty() {
                    for param in params_text.split(',') {
                        let (param_c_type, _) = split_trailing_identifier(param);
                        params.push(rust_type_for_c(param_c_type));
                    }
                }
                types.insert(name.to_string(), callback_type(name, &params, &rust_type_for_c(&body[..star])));
            }
        }
    }
    types
}

fn rust_types() -> Signatures {
    let code = without_comments(RUST_SOURCE);
    let mut types = Signatures::new();
    for body in statements(&code, "pub type ") {
        let (name, definition) = body.split_once('=').expect("type alias has a definition");
        let name = name.trim();
        let definition = definition.split_whitespace().collect::<Vec<_>>().join(" ");
        let text = if definition == "c_int" {
            // A C enum without negative values or a fixed type is 32 bits wide.
            format!("type {name} = enum")
        } else if let Some(function) = definition
            .strip_prefix("Option<unsafe extern \"C\" fn(")
            .and_then(|function| function.strip_suffix('>'))
        {
            let close = function.rfind(')').expect("function pointer has a parameter list");
            let params: Vec<String> = function[..close]
                .split(',')
                .map(|param| param.trim().to_string())
                .filter(|param| !param.is_empty())
                .collect();
            callback_type(name, &params, function[close + 1..].trim().trim_start_matches("->").trim())
        } else {
            format!("type {name} = {definition}")
        };
        types.insert(name.to_string(), text);
    }
    for body in statements(&code, "pub const ") {
        let (name, _) = body.split_once(':').expect("constant has a type");
        let text = body.split_whitespace().collect::<Vec<_>>().join(" ");
        types.insert(name.trim().to_string(), format!("const {text}"));
    }
    types
}

#[test]
fn types_match_the_c_headers() {
    let frameworks_dir = Path::new(env!("ACTIONUI_SYS_FRAMEWORKS_DIR"));
    let in_headers = header_types(frameworks_dir);
    let in_rust = rust_types();

    assert!(
        in_headers.len() > 15,
        "only {} types and enum values found in the C headers under {}; the header format may have changed",
        in_headers.len(),
        frameworks_dir.display()
    );

    let problems = differences(&in_headers, &in_rust);
    assert!(
        problems.is_empty(),
        "src/lib.rs and the C headers disagree:\n{}",
        problems.join("\n")
    );
}
