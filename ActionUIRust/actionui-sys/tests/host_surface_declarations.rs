// Compares the hand-written HostSurface declarations in src/host_surface.rs with the add-on
// framework's headers, and proves the add-on links:
// - functions with the generated ActionUIHostSurface-Swift.h (what the Swift code exports);
// - enums, enum values and structs (field by field, in order) with the hand-written
//   ActionUIHostSurface.h, which the generated header uses for its types.
// Runs with the host-surface feature: cargo test -p actionui-sys --features host-surface

#![cfg(all(feature = "host-surface", target_os = "macos"))]

use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

const LINKED_DIR: &str = env!("ACTIONUI_SYS_FRAMEWORKS_DIR");
const GENERATED_HEADER: &str = "ActionUIHostSurface.framework/Headers/ActionUIHostSurface-Swift.h";
const C_HEADER: &str = "ActionUIHostSurface.framework/Headers/ActionUIHostSurface.h";
const RUST_SOURCE: &str = include_str!("../src/host_surface.rs");

/// Name -> comparable text.
type Declarations = BTreeMap<String, String>;

fn read(relative: &str) -> String {
    let path = Path::new(LINKED_DIR).join(relative);
    fs::read_to_string(&path).unwrap_or_else(|error| panic!("cannot read {}: {error}", path.display()))
}

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

fn squeeze(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// A C type as the Rust declaration spells it.
fn rust_type_for_c(c_type: &str) -> String {
    let cleaned = c_type.replace("_Nonnull", "").replace("_Nullable", "").replace('*', " * ");
    let normalized = squeeze(&cleaned);
    match normalized.as_str() {
        "void" => String::new(),
        "bool" => "bool".into(),
        "uint32_t" => "u32".into(),
        "int32_t" => "i32".into(),
        "int64_t" => "i64".into(),
        "uint64_t" => "u64".into(),
        "double" => "f64".into(),
        "void *" => "*mut c_void".into(),
        "char const *" | "const char *" => "*const c_char".into(),
        other => {
            // const Name * or Name const *
            let pointee = other.strip_prefix("const ").and_then(|rest| rest.strip_suffix(" *"))
                .or_else(|| other.strip_suffix(" const *"));
            match pointee {
                Some(name) => format!("*const {name}"),
                None => other.to_string(),
            }
        }
    }
}

/// Splits "type name" at the last identifier.
fn split_trailing_identifier(text: &str) -> (String, String) {
    let text = text.trim();
    let start = text
        .rfind(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
        .map_or(0, |index| index + 1);
    (text[..start].trim().to_string(), text[start..].to_string())
}

fn function_text(params: &[String], return_type: &str) -> String {
    let list = params.join(", ");
    if return_type.is_empty() {
        format!("fn({list})")
    } else {
        format!("fn({list}) -> {return_type}")
    }
}

// MARK: functions

fn header_functions() -> Declarations {
    let code = without_comments(&read(GENERATED_HEADER));
    let mut functions = Declarations::new();
    for line in code.lines() {
        let Some(rest) = line.trim().strip_prefix("SWIFT_EXTERN ") else {
            continue;
        };
        let open = rest.find('(').expect("function has a parameter list");
        let close = rest.find(')').expect("function has a parameter list");
        let (return_type, name) = split_trailing_identifier(&rest[..open]);
        let params_text = rest[open + 1..close].trim();
        let mut params = Vec::new();
        if params_text != "void" && !params_text.is_empty() {
            for param in params_text.split(',') {
                params.push(rust_type_for_c(&split_trailing_identifier(param).0));
            }
        }
        functions.insert(name.clone(), function_text(&params, &rust_type_for_c(&return_type)));
    }
    functions
}

fn rust_functions() -> Declarations {
    let mut functions = Declarations::new();
    for line in RUST_SOURCE.lines() {
        let Some(declaration) = line.trim().strip_prefix("pub fn ") else {
            continue;
        };
        let declaration = declaration.trim_end_matches(';');
        let open = declaration.find('(').expect("declaration has a parameter list");
        let close = declaration.rfind(')').expect("declaration has a parameter list");
        let params: Vec<String> = declaration[open + 1..close]
            .split(',')
            .filter(|param| !param.trim().is_empty())
            .map(|param| param.split_once(':').expect("parameter has a type").1.trim().to_string())
            .collect();
        let return_type = declaration[close + 1..].trim().trim_start_matches("->").trim();
        functions.insert(declaration[..open].to_string(), function_text(&params, return_type));
    }
    functions
}

// MARK: enums and structs

/// `AUIHostSurfaceGLArea` -> `AUI_HOST_SURFACE_GL_AREA`: an underscore before each capital that
/// follows a small letter, or that starts a word after an acronym.
fn rust_constant_name(c_name: &str) -> String {
    let rest: Vec<char> = c_name.strip_prefix("AUI").expect("AUI prefix").chars().collect();
    let mut name = String::from("AUI");
    for (index, &c) in rest.iter().enumerate() {
        let previous = if index > 0 { Some(rest[index - 1]) } else { None };
        let next = rest.get(index + 1).copied();
        let starts_word = c.is_ascii_uppercase()
            && (index == 0
                || previous.is_some_and(|p| p.is_ascii_lowercase())
                || (previous.is_some_and(|p| p.is_ascii_uppercase()) && next.is_some_and(|n| n.is_ascii_lowercase())));
        if starts_word {
            name.push('_');
        }
        name.push(c.to_ascii_uppercase());
    }
    name
}

/// The statements of a struct body or a file, split at `;` outside parentheses and braces.
fn split_statements(code: &str) -> Vec<String> {
    let mut statements = Vec::new();
    let mut depth = 0;
    let mut current = String::new();
    for c in code.chars() {
        match c {
            '(' | '{' => depth += 1,
            ')' | '}' => depth -= 1,
            _ => {}
        }
        if c == ';' && depth == 0 {
            statements.push(squeeze(&current));
            current.clear();
        } else {
            current.push(c);
        }
    }
    statements.into_iter().filter(|statement| !statement.is_empty()).collect()
}

fn enum_values(body: &str, type_name: &str, types: &mut Declarations) {
    for entry in body.split(',') {
        let entry = entry.trim();
        if entry.is_empty() {
            continue;
        }
        let (c_name, value) = entry.split_once('=').expect("enum value is written out");
        let constant = rust_constant_name(c_name.trim());
        types.insert(constant.clone(), format!("const {constant}: {type_name} = {}", value.trim()));
    }
}

/// Every enum type, enum value and struct of the C header, as comparable text.
fn header_types() -> Declarations {
    let mut code = without_comments(&read(C_HEADER));
    // The extern "C" guard for C++ opens a brace that closes at the end of the file.
    while let Some(start) = code.find("#ifdef __cplusplus") {
        let end = start + code[start..].find("#endif").expect("#ifdef is closed") + "#endif".len();
        code.replace_range(start..end, "");
    }
    let mut types = Declarations::new();
    for statement in split_statements(&code) {
        let Some(start) = statement.find("typedef ").or_else(|| statement.find("enum {")) else {
            continue;
        };
        let statement = &statement[start..];
        let open = statement.find('{').expect("type has a body");
        let close = statement.rfind('}').expect("type has a body");
        let body = &statement[open + 1..close];
        let name = statement[close + 1..].trim();
        if statement.starts_with("enum {") {
            // The unnamed modifier bits: u32, the type of AUIHostInputEvent.modifiers.
            enum_values(body, "u32", &mut types);
        } else if statement.starts_with("typedef enum") {
            types.insert(name.to_string(), format!("type {name} = enum"));
            enum_values(body, name, &mut types);
        } else if statement.starts_with("typedef struct") {
            let mut fields = Vec::new();
            for field in split_statements(body) {
                if let Some(star) = field.find("(*") {
                    let name_end = star + field[star..].find(')').expect("function pointer field");
                    let field_name = field[star + 2..name_end].trim();
                    let params_text = field[name_end + 1..].trim().trim_start_matches('(').trim_end_matches(')');
                    let params: Vec<String> = params_text
                        .split(',')
                        .map(|param| rust_type_for_c(&split_trailing_identifier(param).0))
                        .collect();
                    let return_type = rust_type_for_c(&field[..star]);
                    fields.push(format!("{field_name}: Option<unsafe extern \"C\" {}>", function_text(&params, &return_type)));
                } else {
                    // "double x, y" declares two fields.
                    let (first_type, first_name) = split_trailing_identifier(field.split(',').next().unwrap());
                    let rust_type = rust_type_for_c(&first_type);
                    fields.push(format!("{first_name}: {rust_type}"));
                    for more in field.split(',').skip(1) {
                        fields.push(format!("{}: {rust_type}", more.trim()));
                    }
                }
            }
            types.insert(name.to_string(), format!("struct {name} {{ {} }}", fields.join(", ")));
        }
    }
    types
}

fn rust_types() -> Declarations {
    let code = without_comments(RUST_SOURCE);
    let mut types = Declarations::new();
    for statement in split_statements(&code) {
        if let Some(alias) = statement.strip_prefix("pub type ") {
            let (name, definition) = alias.split_once('=').expect("type alias has a definition");
            assert_eq!(definition.trim(), "c_int", "an enum type is a c_int alias");
            types.insert(name.trim().to_string(), format!("type {} = enum", name.trim()));
        } else if let Some(constant) = statement.split("pub const ").nth(1) {
            let (name, _) = constant.split_once(':').expect("constant has a type");
            types.insert(name.trim().to_string(), format!("const {}", squeeze(constant)));
        }
    }
    // Structs: #[repr(C)] pub struct Name { pub field: Type, ... }
    let mut rest = code.as_str();
    while let Some(start) = rest.find("pub struct ") {
        // The attributes since the previous item: the field order is the C layout only with
        // a plain repr(C) (no packed, no align).
        let attributes_start = rest[..start].rfind(['}', ';']).map_or(0, |index| index + 1);
        let attributes = squeeze(&rest[attributes_start..start]);
        let after = &rest[start + "pub struct ".len()..];
        let struct_name = after[..after.find('{').expect("struct has a body")].trim();
        assert!(
            attributes.split("#[").any(|attribute| attribute.trim() == "repr(C)]")
                && attributes.matches("repr(").count() == 1,
            "{struct_name} must be #[repr(C)] and nothing more; its attributes are: {attributes}"
        );
        let open = after.find('{').expect("struct has a body");
        let name = after[..open].trim();
        let mut depth = 0;
        let mut close = open;
        for (index, c) in after[open..].char_indices() {
            match c {
                '{' => depth += 1,
                '}' => {
                    depth -= 1;
                    if depth == 0 {
                        close = open + index;
                        break;
                    }
                }
                _ => {}
            }
        }
        // Every field, public or not, so that an extra private field also shows as a difference.
        let fields: Vec<String> = after[open + 1..close]
            .lines()
            .map(str::trim)
            .filter(|line| !line.is_empty() && !line.starts_with("#["))
            .map(|line| line.strip_prefix("pub ").unwrap_or(line))
            .map(|field| squeeze(field.trim_end_matches(',')))
            .collect();
        types.insert(name.to_string(), format!("struct {name} {{ {} }}", fields.join(", ")));
        rest = &after[close..];
    }
    types
}

fn differences(in_headers: &Declarations, in_rust: &Declarations) -> Vec<String> {
    let mut problems = Vec::new();
    for (name, header_text) in in_headers {
        match in_rust.get(name) {
            None => problems.push(format!("missing in src/host_surface.rs: {header_text}")),
            Some(rust_text) if rust_text != header_text => {
                problems.push(format!("differs:\n    header: {header_text}\n    rust:   {rust_text}"))
            }
            Some(_) => {}
        }
    }
    for (name, rust_text) in in_rust {
        if !in_headers.contains_key(name) {
            problems.push(format!("not in the header: {rust_text}"));
        }
    }
    problems
}

#[test]
fn functions_match_the_generated_header() {
    let in_headers = header_functions();
    assert_eq!(in_headers.len(), 5, "functions in the generated header: {in_headers:?}");
    let problems = differences(&in_headers, &rust_functions());
    assert!(problems.is_empty(), "src/host_surface.rs and the generated header disagree:\n{}", problems.join("\n"));
}

#[test]
fn types_match_the_c_header() {
    let in_headers = header_types();
    let structs = in_headers.values().filter(|text| text.starts_with("struct ")).count();
    assert_eq!(structs, 3, "structs found in the C header; the header format may have changed");
    assert!(in_headers.len() > 50, "only {} types and values found in the C header", in_headers.len());
    let problems = differences(&in_headers, &rust_types());
    assert!(problems.is_empty(), "src/host_surface.rs and the C header disagree:\n{}", problems.join("\n"));
}

#[test]
fn the_add_on_links() {
    use actionui_sys::host_surface::*;
    // Off the main thread both calls are refused without touching the main thread.
    let delegate = AUIHostSurfaceDelegate {
        structSize: std::mem::size_of::<AUIHostSurfaceDelegate>() as u32,
        ..Default::default()
    };
    let bound = unsafe { actionUIHostSurfaceSetDelegate(c"viewport".as_ptr(), &delegate, std::ptr::null_mut()) };
    assert!(!bound, "SetDelegate must refuse a call off the main thread");
    let cursor_set = unsafe { actionUIHostSurfaceSetCursor(1, AUI_HOST_CURSOR_CROSSHAIR) };
    assert!(!cursor_set, "SetCursor must refuse a call off the main thread");
}
