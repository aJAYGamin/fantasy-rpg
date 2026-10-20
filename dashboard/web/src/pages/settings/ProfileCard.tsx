import { Trash2, Upload } from "lucide-react";
import { type ChangeEvent, useRef, useState } from "react";
import { AVATAR_MAX_BYTES, AVATAR_TYPES } from "../../../../shared/src/constants";
import { useAuthState, useRemoveAvatar, useUpdateDisplayName, useUploadAvatar } from "../../api/hooks";
import { Alert } from "../../auth/Alert";
import { refusalOf } from "../../auth/refusal";
import { checkDisplayName } from "../../auth/validation";
import { Button, Card } from "../../components";
import { Avatar } from "../../shell/Avatar";
import { CommitField } from "./CommitField";
import { SavedStatus } from "./SavedStatus";
import styles from "./ProfileCard.module.css";
import { useSavedNotice } from "./useSavedNotice";

const WRONG_TYPE = "Pictures must be PNG, JPEG or WebP.";
const TOO_BIG = `Pictures can be at most ${AVATAR_MAX_BYTES / (1024 * 1024)} MB.`;
const ACCEPT = AVATAR_TYPES.join(",");

// The same two rules the server enforces, checked first so a wrong file isn't sent for nothing.
function problemWithPicture(file: File): string | undefined {
  if (!(AVATAR_TYPES as readonly string[]).includes(file.type)) return WRONG_TYPE;
  return file.size > AVATAR_MAX_BYTES ? TOO_BIG : undefined;
}

// What the server said about a picture, in the same words (R34); nothing for a session that has ended. A size or
// type refusal that isn't in the server's own words (a page from something in between) is known by its status.
function problemWithUpload(error: unknown): string | undefined {
  const refusal = refusalOf(error);
  if (refusal === null) return "Something went wrong.";
  switch (refusal.body.error) {
    case "too_large":
      return TOO_BIG;
    case "unsupported_media_type":
      return WRONG_TYPE;
    case "signed_out":
      return undefined;
  }
  if (refusal.status === 413) return TOO_BIG;
  if (refusal.status === 415) return WRONG_TYPE;
  return refusal.body.message;
}

/** The account itself: its picture (or initials), display name, and the username, which can't be changed. */
export function ProfileCard() {
  const user = useAuthState().data?.user;
  const { saved, flash } = useSavedNotice();
  const rename = useUpdateDisplayName();
  const upload = useUploadAvatar();
  const remove = useRemoveAvatar();
  const chooser = useRef<HTMLInputElement>(null);
  const uploadButton = useRef<HTMLButtonElement>(null);
  const [pictureProblem, setPictureProblem] = useState<string>();

  if (!user) return null;

  function chosen(event: ChangeEvent<HTMLInputElement>) {
    const input = event.currentTarget;
    const file = input.files?.[0];
    // Cleared so that choosing the same file again (after fixing it, say) still counts as a change.
    input.value = "";
    if (!file) return;
    const found = problemWithPicture(file);
    setPictureProblem(found);
    if (found !== undefined) return;
    upload.mutate(file, { onSuccess: flash, onError: (error) => setPictureProblem(problemWithUpload(error)) });
  }

  function removePicture() {
    setPictureProblem(undefined);
    remove.mutate(undefined, {
      onSuccess: () => {
        flash();
        // The button that was pressed is gone now; the cursor goes to its neighbour rather than to nowhere.
        uploadButton.current?.focus();
      },
      onError: (error) => setPictureProblem(problemWithUpload(error)),
    });
  }

  return (
    <Card title="Account" actions={<SavedStatus saved={saved} />}>
      <div className={styles.picture}>
        <div className={styles.preview}>
          <Avatar user={user} />
        </div>
        <div className={styles.pictureSide}>
          <p className={styles.label}>Profile picture</p>
          <div className={styles.buttons}>
            <Button ref={uploadButton} loading={upload.isPending} onClick={() => chooser.current?.click()}>
              <Upload aria-hidden="true" />
              Upload picture
            </Button>
            {user.hasAvatar && (
              <Button loading={remove.isPending} onClick={removePicture}>
                <Trash2 aria-hidden="true" />
                Remove picture
              </Button>
            )}
          </div>
          <p className={styles.hint}>PNG, JPEG or WebP, up to {AVATAR_MAX_BYTES / (1024 * 1024)} MB.</p>
        </div>
        {/* The Upload button stands for it; opened by the button, so it needs no place in the Tab order. */}
        <input
          ref={chooser}
          type="file"
          hidden
          accept={ACCEPT}
          aria-label="Choose a picture"
          onChange={chosen}
        />
      </div>
      {pictureProblem !== undefined && (
        <Alert tone="bad" className={styles.problem}>
          {pictureProblem}
        </Alert>
      )}

      <CommitField
        label="Display name"
        saved={user.displayName}
        check={checkDisplayName}
        save={async (displayName) => {
          await rename.mutateAsync({ displayName });
          flash();
        }}
        autoComplete="name"
        className={styles.field}
      />

      <div className={styles.username}>
        <p className={styles.label}>Username</p>
        <p className={styles.value}>{user.username}</p>
        <p className={styles.hint}>Your username can't be changed.</p>
      </div>
    </Card>
  );
}
