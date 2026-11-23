// The host's configuration of ActionUI, for every window on the page: limits, trust settings and
// settings for add-ons, with the same keys as on the other platforms. Only host code sets it,
// never ActionUI JSON, so content cannot raise its own limits or trust itself. It is set early,
// before the first window is made, and fixed after that: a later change is refused, so every
// window and every load sees the same settings.
//
//   configure({
//       limits: { maximumJSONSize: 16777216,                 // bytes of ActionUI JSON one load takes (16 MB)
//                 loadBudget: { loads: 256, seconds: 60 },   // LoadableView loads per window in any span
//                 maximumNestingDepth: 16,                   // LoadableViews inside LoadableViews
//                 maximumDownloadTime: 120 },                // seconds one fetch of ActionUI JSON may take (null: no limit)
//       trust: { trustedOrigins: ["https://ui.example.com"] },  // servers whose JSON is trusted
//       resourceFolder: null,                                // no meaning on the web (see below)
//       addOns: { SomeAddOn: {} },                            // each add-on reads its own section
//   });
//
// Each key is optional: a change names only the keys it changes and keeps the rest. A key
// ActionUI does not know, a value of the wrong type or out of range, or a trusted origin that is
// not an https origin refuses the whole change (a ConfigurationError), which then keeps the
// configuration as it was.
//
// Trusted origins: ActionUI JSON from one of these servers is trusted as the page's own,
// provided the content around it is trusted too (a window's root, or a LoadableView in trusted
// content), so less-trusted content cannot name the server and get trusted content inside
// itself. An origin is a scheme, host and port; only https is accepted, with no path, query,
// fragment or user name. The address that counts is the one the ActionUI JSON finally came from,
// after redirects (the fetch Response's url). The server must still allow the page to read it
// (CORS), as any fetch from another origin needs.
//
// maximumDownloadTime: the longest one fetch of ActionUI JSON (a window's, a menu bar's, a
// LoadableView's) may take, in seconds, however slowly the server sends; null removes it. On the
// other platforms it also covers the images the renderer loads itself; on the web the browser
// loads images, without it.
//
// The page's own origin holds the app's resources, so there is no resource folder on the web:
// "resourceFolder" is accepted only as null, and a path is refused rather than ignored.
//
// The host may raise the limits above the defaults: host code is trusted. The trust policy
// (setTrustPolicy) stays a separate setter, since it is code; its byDefault trust already counts
// the trusted origins.

export class ConfigurationError extends Error {
    constructor(message) {
        super(message);
        this.name = "ConfigurationError";
    }
}

const DEFAULTS = Object.freeze({
    limits: Object.freeze({
        maximumJSONSize: 16 * 1024 * 1024,
        loadBudget: Object.freeze({ loads: 256, seconds: 60 }),
        maximumNestingDepth: 16,
        maximumDownloadTime: 120,
    }),
    trust: Object.freeze({ trustedOrigins: Object.freeze([]) }),
    resourceFolder: null,
    addOns: Object.freeze({}),
});

let current = DEFAULTS;
let fixed = false;

const FIXED = "the configuration is fixed once a window has loaded its ActionUI JSON; set it before";

// A frozen copy of `value` (plain JSON data), so neither the host nor ActionUI can change a stored
// configuration in place.
function frozenCopy(value) {
    if (Array.isArray(value)) return Object.freeze(value.map(frozenCopy));
    if (value !== null && typeof value === "object") {
        const copy = {};
        for (const [key, item] of Object.entries(value)) copy[key] = frozenCopy(item);
        return Object.freeze(copy);
    }
    return value;
}

// A plain, unfrozen copy of `value`, for a host to read.
function plainCopy(value) {
    return JSON.parse(JSON.stringify(value));
}

const isPlainObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

function objectOf(value, name, keys) {
    if (!isPlainObject(value)) throw new ConfigurationError(`${name} must be an object`);
    const unknown = Object.keys(value).sort().find((key) => !keys.includes(key));
    if (unknown !== undefined) {
        throw new ConfigurationError(`unknown configuration key ${name === "the configuration" ? "" : `${name}.`}${unknown}`);
    }
    return value;
}

function integer(value, name) {
    if (typeof value !== "number" || !Number.isSafeInteger(value)) throw new ConfigurationError(`${name} must be a whole number`);
    return value;
}

function number(value, name) {
    if (typeof value !== "number") throw new ConfigurationError(`${name} must be a number`);
    return value;
}

// Why `address` is not a trusted origin, or null when it is one: https, a host, and at most a
// port after it.
export function trustedOriginProblem(address) {
    let url;
    try {
        url = new URL(address);
    } catch {
        return "is not an https address";
    }
    if (url.protocol !== "https:") return "is not an https address";
    if (url.hostname === "") return "has no host";
    if (url.username !== "" || url.password !== "") return "has a user name or password";
    // The URL parser makes an empty path "/", so "/" is what an origin with nothing after it has.
    if (url.pathname !== "/" || /^https:\/\/[^/?#]*\/[^?#]/i.test(String(address))) {
        return "has a path; an origin is the scheme, host and port only";
    }
    if (url.search !== "" || url.hash !== "" || /[?#]/.test(String(address))) return "has a query or fragment";
    return null;
}

function validate(configuration) {
    const { limits } = configuration;
    if (limits.maximumJSONSize <= 0) throw new ConfigurationError("limits.maximumJSONSize must be more than 0");
    if (limits.loadBudget.loads < 0) throw new ConfigurationError("limits.loadBudget.loads must not be negative");
    if (!Number.isFinite(limits.loadBudget.seconds) || limits.loadBudget.seconds <= 0) {
        throw new ConfigurationError("limits.loadBudget.seconds must be a number more than 0");
    }
    if (limits.maximumNestingDepth < 0) throw new ConfigurationError("limits.maximumNestingDepth must not be negative");
    if (limits.maximumDownloadTime !== null && !(Number.isFinite(limits.maximumDownloadTime) && limits.maximumDownloadTime > 0)) {
        throw new ConfigurationError("limits.maximumDownloadTime must be a number more than 0, or null for no limit");
    }
    for (const origin of configuration.trust.trustedOrigins) {
        const problem = trustedOriginProblem(origin);
        if (problem !== null) throw new ConfigurationError(`trust.trustedOrigins: ${origin} ${problem}`);
    }
}

// The configuration `base` with the keys `settings` names changed.
function applied(settings, base) {
    const top = objectOf(settings, "the configuration", ["limits", "trust", "resourceFolder", "addOns"]);
    const next = plainCopy(base);
    if (top.limits !== undefined) {
        const limits = objectOf(top.limits, "limits", ["maximumJSONSize", "loadBudget", "maximumNestingDepth", "maximumDownloadTime"]);
        if (limits.maximumJSONSize !== undefined) next.limits.maximumJSONSize = integer(limits.maximumJSONSize, "limits.maximumJSONSize");
        if (limits.loadBudget !== undefined) {
            const budget = objectOf(limits.loadBudget, "limits.loadBudget", ["loads", "seconds"]);
            if (budget.loads !== undefined) next.limits.loadBudget.loads = integer(budget.loads, "limits.loadBudget.loads");
            if (budget.seconds !== undefined) next.limits.loadBudget.seconds = number(budget.seconds, "limits.loadBudget.seconds");
        }
        if (limits.maximumNestingDepth !== undefined) {
            next.limits.maximumNestingDepth = integer(limits.maximumNestingDepth, "limits.maximumNestingDepth");
        }
        if (limits.maximumDownloadTime !== undefined) {
            next.limits.maximumDownloadTime = limits.maximumDownloadTime === null
                ? null : number(limits.maximumDownloadTime, "limits.maximumDownloadTime");
        }
    }
    if (top.trust !== undefined) {
        const trust = objectOf(top.trust, "trust", ["trustedOrigins"]);
        if (trust.trustedOrigins !== undefined) {
            if (!Array.isArray(trust.trustedOrigins)) throw new ConfigurationError("trust.trustedOrigins must be an array of strings");
            next.trust.trustedOrigins = trust.trustedOrigins.map((origin) => {
                if (typeof origin !== "string") {
                    throw new ConfigurationError("trust.trustedOrigins must be an array of https origins, such as \"https://ui.example.com\"");
                }
                return origin;
            });
        }
    }
    if (top.resourceFolder !== undefined && top.resourceFolder !== null) {
        throw new ConfigurationError("resourceFolder has no meaning on the web: the page's own origin holds the app's resources; pass null or leave it out");
    }
    if (top.addOns !== undefined) {
        if (!isPlainObject(top.addOns)) throw new ConfigurationError("addOns must be an object");
        for (const [name, section] of Object.entries(top.addOns)) {
            // Assigning to "__proto__" would replace the object's prototype instead of storing a
            // section, so the section would vanish without a word: refuse the name instead.
            if (name === "__proto__") throw new ConfigurationError("addOns: a section may not be named __proto__");
            if (section === null) delete next.addOns[name];
            else next.addOns[name] = plainCopy(section);
        }
    }
    return next;
}

// Changes the keys `settings` names in the configuration (see the header). Throws, changing
// nothing: a TypeError for settings that are not an object, a ConfigurationError for an unknown
// key, a wrong value, an origin that is not https, or a configuration already fixed.
export function configure(settings) {
    if (!isPlainObject(settings)) throw new TypeError("configure takes an object of settings");
    if (fixed) throw new ConfigurationError(FIXED);
    let next;
    try {
        // A value JSON cannot hold (a function, a cycle, NaN) is not a setting.
        next = applied(JSON.parse(JSON.stringify(settings)), current);
    } catch (error) {
        if (error instanceof ConfigurationError) throw error;
        throw new ConfigurationError(`the configuration is not plain JSON data: ${error.message}`);
    }
    validate(next);
    current = frozenCopy(next);
}

// The configuration in effect, with every key, as a copy the host may change freely.
export function getConfiguration() {
    return plainCopy(current);
}

// The configuration in effect, frozen, for ActionUI's own reads.
export function currentConfiguration() {
    return current;
}

// Whether the configuration is fixed: a window has been made.
export function isConfigurationFixed() {
    return fixed;
}

// Fixes the configuration: called when the first window is made.
export function fixConfiguration() {
    fixed = true;
}

// For tests, which make windows and change settings in any order: the defaults (or `settings`
// applied to them), settable again.
export function resetConfigurationForTesting(settings = null, { fixed: isFixed = false } = {}) {
    current = settings == null ? DEFAULTS : frozenCopy(applied(settings, DEFAULTS));
    fixed = isFixed;
}

// Whether ActionUI JSON from `address` (absolute) comes from one of the trusted origins.
export function isTrustedOrigin(address) {
    let url;
    try {
        url = new URL(address);
    } catch {
        return false;
    }
    if (url.protocol !== "https:") return false;
    return current.trust.trustedOrigins.some((origin) => {
        try {
            return new URL(origin).origin === url.origin;
        } catch {
            return false;
        }
    });
}
