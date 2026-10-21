import { AnswersForm } from "./AnswersForm";
import { PasswordForm } from "./PasswordForm";
import { ProfileCard } from "./ProfileCard";

/** The account: who it is, and the two ways to change how it is protected. */
export function AccountSection() {
  return (
    <>
      <ProfileCard />
      <PasswordForm />
      <AnswersForm />
    </>
  );
}
