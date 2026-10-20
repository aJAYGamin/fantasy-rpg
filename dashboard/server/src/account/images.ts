import type { AVATAR_TYPES } from "../../../shared/src/constants.js";

export type ImageType = (typeof AVATAR_TYPES)[number];

const startsWith = (bytes: Buffer, signature: readonly number[], at = 0) =>
  bytes.length >= at + signature.length && signature.every((byte, i) => bytes[at + i] === byte);

// What the file really is, from its first bytes alone (never from its name or what the sender says it is). Null for
// anything that is not a png, jpeg or webp.
export function sniffImageType(bytes: Buffer): ImageType | null {
  if (startsWith(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return "image/png";
  if (startsWith(bytes, [0xff, 0xd8, 0xff])) return "image/jpeg";
  // WebP is a RIFF file whose form type, after the 4-byte length, is "WEBP".
  const riff = startsWith(bytes, [0x52, 0x49, 0x46, 0x46]);
  if (riff && startsWith(bytes, [0x57, 0x45, 0x42, 0x50], 8)) return "image/webp";
  return null;
}
