import { expect, test } from "vitest";
import { cleanUsername, isUsername } from "../../shared/src/username.js";

// The username rule both the server and the forms use: any visible characters, 3 to 32 of them.

test.each([
  ["aJAY Gamin'"],
  ["ówner"],
  ["own/er"],
  ["the owner"],
  ["!@#$%^&*()"],
  ["Ünïcødé ☆"],
  ["\u{1F642}".repeat(32)],
  ["abc"],
  ["a".repeat(32)],
])("%s is a username", (name) => {
  expect(isUsername(cleanUsername(name))).toBe(true);
});

test.each([
  ["two characters", "ab"],
  ["33 characters", "a".repeat(33)],
  ["33 emoji", "\u{1F642}".repeat(33)],
  ["only spaces", "     "],
  ["a tab inside", "own\ter"],
  ["a line break inside", "own\ner"],
  ["a zero-width space", "own​er"],
  ["a zero-width joiner", "own‍er"],
  ["a soft hyphen", "own­er"],
  ["a Hangul filler", "ownㅤer"],
  ["a private-use character", "owner"],
])("a name with %s is not a username", (_what, name) => {
  expect(isUsername(cleanUsername(name))).toBe(false);
});

test("spaces at the start and end are dropped, and a run of spaces inside counts as one", () => {
  expect(cleanUsername(" aJAY Gamin' ")).toBe("aJAY Gamin'");
  expect(cleanUsername(" aJAY   Gamin'　")).toBe("aJAY Gamin'");
});

test("curly quotes count as straight ones", () => {
  expect(cleanUsername("aJAY Gamin’")).toBe("aJAY Gamin'");
  expect(cleanUsername("‘Ace’ “Bolt”")).toBe("'Ace' \"Bolt\"");
});

test("an accent typed as one character or as two is the same name", () => {
  expect(cleanUsername("José")).toBe(cleanUsername("José"));
});

test("capitals are kept as typed (sign-in ignores them separately)", () => {
  expect(cleanUsername("aJAY")).toBe("aJAY");
});
