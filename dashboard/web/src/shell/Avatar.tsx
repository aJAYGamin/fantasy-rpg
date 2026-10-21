import { useState } from "react";
import type { User } from "../../../shared/src/api";
import { usePictureVersion } from "../api/hooks";
import styles from "./Avatar.module.css";

const PICTURE_URL = "/api/account/avatar";

/** Up to two letters from the display name: the first word's and the last word's ("Test Owner" → "TO"). */
export function initialsOf(name: string): string {
  const words = name.trim().split(/\s+/).filter(Boolean);
  const picked = words.length > 1 ? [words[0], words[words.length - 1]] : words;
  // By code point, so a name starting with an emoji keeps it whole.
  return picked.map((word) => [...word][0]).join("").toLocaleUpperCase();
}

/** Where the picture comes from. The version only moves when the picture changes, so a new one is asked for afresh. */
export function pictureUrl(version: number): string {
  return version === 0 ? PICTURE_URL : `${PICTURE_URL}?v=${version}`;
}

function Initials({ name }: { name: string }) {
  return <span className={styles.initials}>{initialsOf(name)}</span>;
}

// Its own component so that it can be started over: a picture that failed to load stays failed for as long as this
// lives, and a new version of the picture (the key it is given) must not inherit that.
function Picture({ name, version }: { name: string; version: number }) {
  const [broken, setBroken] = useState(false);
  if (broken) return <Initials name={name} />;
  return <img className={styles.picture} src={pictureUrl(version)} alt="" onError={() => setBroken(true)} />;
}

/**
 * The account's picture, or its initials when there is none (or it fails to load). It fills whatever circle it is
 * put in; that circle sets the size, colors and clipping.
 */
export function Avatar({ user }: { user: User }) {
  const version = usePictureVersion();
  if (!user.hasAvatar) return <Initials name={user.displayName} />;
  return <Picture key={version} name={user.displayName} version={version} />;
}
