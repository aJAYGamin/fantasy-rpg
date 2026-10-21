// Which host names this server answers to (R43). A page on some other site can point one of its own names at
// 127.0.0.1 (DNS rebinding) and then talk to this server as if it were that site, even claim the owner account at
// first-run setup; the Host header still carries its name, so anything not on this list is turned away.

// What a browser on this computer uses. "::1" is how [::1] reads once its brackets are off.
const LOOPBACK = ["localhost", "127.0.0.1", "::1"];
// Listening on every address isn't a name anyone browses to.
const EVERY_ADDRESS = new Set(["0.0.0.0", "::"]);

const NAME = /^[a-z0-9._-]+$/;
const IPV6 = /^[0-9a-f:.]+$/;
const PORT = /^:\d{1,5}$/;

/**
 * The host name in a Host header or a configured entry, lower-cased, without its port and an IPv6 address's
 * brackets ("[::1]:4517" is "::1"), or null when it isn't one. A bare IPv6 address (more than one colon, no brackets)
 * is read whole, as an address written in a setting would be.
 */
export function hostnameOf(value: string): string | null {
  const text = value.trim().toLowerCase();
  if (text.startsWith("[")) {
    const end = text.indexOf("]");
    const address = text.slice(1, end);
    const rest = text.slice(end + 1);
    return end > 1 && IPV6.test(address) && (rest === "" || PORT.test(rest)) ? address : null;
  }
  const colons = text.split(":").length - 1;
  if (colons > 1) return IPV6.test(text) ? text : null;
  const [name = "", port] = text.split(":");
  if (port !== undefined && !PORT.test(`:${port}`)) return null;
  return NAME.test(name) ? name : null;
}

/** The loopback names, the address the server listens on (unless that is every address) and the extra ones. */
export function allowedHostnames(config: { host: string; allowedHosts: readonly string[] }): ReadonlySet<string> {
  const allowed = new Set(LOOPBACK);
  for (const entry of [config.host, ...config.allowedHosts]) {
    const name = hostnameOf(entry);
    if (name !== null && !EVERY_ADDRESS.has(name)) allowed.add(name);
  }
  return allowed;
}

/** Whether a request's Host header (port ignored) names a host this server answers to. No header never does. */
export function isAllowedHost(header: string | undefined, allowed: ReadonlySet<string>): boolean {
  const name = header === undefined ? null : hostnameOf(header);
  return name !== null && allowed.has(name);
}
