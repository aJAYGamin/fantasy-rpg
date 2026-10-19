import { act, fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { Settings } from "lucide-react";
import { type FormEvent, StrictMode, useState } from "react";
import { afterEach, describe, expect, test, vi } from "vitest";
import {
  Button,
  Card,
  Checkbox,
  Countdown,
  Dialog,
  Field,
  IconButton,
  Input,
  PasswordInput,
  Pill,
  Popover,
  Ring,
  Segmented,
  Toggle,
} from "../src/components";

function PopoverDemo() {
  return (
    <>
      <Popover label="Colour theme" trigger={(props) => <Button {...props}>Theme</Button>}>
        <Button>Amethyst</Button>
      </Popover>
      <Button>Elsewhere</Button>
    </>
  );
}

function DialogDemo() {
  const [open, setOpen] = useState(false);
  const close = () => setOpen(false);
  return (
    <>
      <Button onClick={() => setOpen(true)}>Reset everything</Button>
      <Dialog
        open={open}
        onClose={close}
        title="Reset to before debugging?"
        footer={
          <>
            <Button onClick={close}>Cancel</Button>
            <Button variant="danger">Reset</Button>
          </>
        }
      >
        <p>This rewinds the game to before your first change.</p>
      </Dialog>
    </>
  );
}

describe("Popover and Dialog", () => {
  test("popover and dialog close on Escape and return focus", async () => {
    const user = userEvent.setup();
    render(
      <>
        <PopoverDemo />
        <DialogDemo />
      </>,
    );

    const themeButton = screen.getByRole("button", { name: "Theme" });
    await user.click(themeButton);
    const popover = screen.getByRole("dialog", { name: "Colour theme" });
    expect(themeButton).toHaveAttribute("aria-expanded", "true");
    expect(popover).toContainElement(document.activeElement as HTMLElement);
    await user.keyboard("{Escape}");
    expect(screen.queryByRole("dialog", { name: "Colour theme" })).toBeNull();
    expect(themeButton).toHaveAttribute("aria-expanded", "false");
    expect(themeButton).toHaveFocus();

    const resetButton = screen.getByRole("button", { name: "Reset everything" });
    await user.click(resetButton);
    const dialog = screen.getByRole("dialog", { name: "Reset to before debugging?" });
    expect(dialog).toHaveAttribute("aria-modal", "true");
    expect(dialog).toContainElement(document.activeElement as HTMLElement);
    await user.keyboard("{Escape}");
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(resetButton).toHaveFocus();
  });

  test("a popover closes when you click outside it", async () => {
    const user = userEvent.setup();
    render(<PopoverDemo />);
    await user.click(screen.getByRole("button", { name: "Theme" }));
    expect(screen.getByRole("dialog", { name: "Colour theme" })).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Elsewhere" }));
    expect(screen.queryByRole("dialog", { name: "Colour theme" })).toBeNull();
    expect(screen.getByRole("button", { name: "Elsewhere" })).toHaveFocus();
  });

  test("a press outside that doesn't move focus still closes it (Safari never focuses a clicked button)", async () => {
    const user = userEvent.setup();
    render(<PopoverDemo />);
    await user.click(screen.getByRole("button", { name: "Theme" }));
    fireEvent.pointerDown(document.body);
    expect(screen.queryByRole("dialog", { name: "Colour theme" })).toBeNull();
    expect(screen.getByRole("button", { name: "Theme" })).toHaveFocus();
  });

  test("a popover closes when Tab leaves it", async () => {
    const user = userEvent.setup();
    render(<PopoverDemo />);
    await user.click(screen.getByRole("button", { name: "Theme" }));
    expect(screen.getByRole("button", { name: "Amethyst" })).toHaveFocus();
    await user.tab();
    expect(screen.queryByRole("dialog", { name: "Colour theme" })).toBeNull();
  });

  test("Tab stays inside an open dialog", async () => {
    const user = userEvent.setup();
    render(<DialogDemo />);
    await user.click(screen.getByRole("button", { name: "Reset everything" }));
    const dialog = screen.getByRole("dialog");
    for (let i = 0; i < 6; i++) {
      await user.tab();
      expect(dialog).toContainElement(document.activeElement as HTMLElement);
    }
    for (let i = 0; i < 6; i++) {
      await user.tab({ shift: true });
      expect(dialog).toContainElement(document.activeElement as HTMLElement);
    }
  });

  test("while a dialog is open the page behind it is inert", async () => {
    const root = document.createElement("div");
    root.id = "root";
    document.body.append(root);
    try {
      const user = userEvent.setup();
      render(<DialogDemo />, { container: root });
      const resetButton = screen.getByRole("button", { name: "Reset everything" });
      await user.click(resetButton);
      expect(root).toHaveAttribute("inert");
      await user.keyboard("{Escape}");
      expect(root).not.toHaveAttribute("inert");
      expect(resetButton).toHaveFocus();
    } finally {
      root.remove();
    }
  });

  test("the dialog's close button closes it", async () => {
    const user = userEvent.setup();
    render(<DialogDemo />);
    await user.click(screen.getByRole("button", { name: "Reset everything" }));
    await user.click(screen.getByRole("button", { name: "Close" }));
    expect(screen.queryByRole("dialog")).toBeNull();
  });
});

describe("controls", () => {
  test("Segmented is a radio group the arrow keys move through", async () => {
    function Appearance() {
      const [value, setValue] = useState<"light" | "dark" | "system">("light");
      return (
        <Segmented
          label="Appearance"
          value={value}
          onChange={setValue}
          options={[
            { value: "light", label: "Light" },
            { value: "dark", label: "Dark" },
            { value: "system", label: "Follow my Mac" },
          ]}
        />
      );
    }
    const user = userEvent.setup();
    render(
      <>
        <Button>Before</Button>
        <Appearance />
        <Button>After</Button>
      </>,
    );
    const radio = (name: string) => screen.getByRole("radio", { name });
    expect(screen.getByRole("radiogroup", { name: "Appearance" })).toBeInTheDocument();
    expect(radio("Light")).toHaveAttribute("aria-checked", "true");
    expect(radio("Dark")).toHaveAttribute("aria-checked", "false");

    await user.tab();
    await user.tab();
    expect(radio("Light")).toHaveFocus();
    await user.keyboard("{ArrowRight}");
    expect(radio("Dark")).toHaveFocus();
    expect(radio("Dark")).toHaveAttribute("aria-checked", "true");
    expect(radio("Light")).toHaveAttribute("aria-checked", "false");
    await user.keyboard("{ArrowRight}{ArrowRight}");
    expect(radio("Light")).toHaveAttribute("aria-checked", "true");
    await user.keyboard("{ArrowLeft}");
    expect(radio("Follow my Mac")).toHaveAttribute("aria-checked", "true");

    // Only the chosen option is a Tab stop: coming back in lands on it, and one Tab leaves the group.
    await user.click(screen.getByRole("button", { name: "Before" }));
    await user.tab();
    expect(radio("Follow my Mac")).toHaveFocus();
    await user.tab();
    expect(screen.getByRole("button", { name: "After" })).toHaveFocus();

    await user.click(radio("Dark"));
    expect(radio("Dark")).toHaveAttribute("aria-checked", "true");
  });

  test("Toggle is a switch that flips by click and by Space", async () => {
    function Reconnect() {
      const [on, setOn] = useState(true);
      return <Toggle label="Reconnect automatically" checked={on} onChange={setOn} />;
    }
    const user = userEvent.setup();
    render(<Reconnect />);
    const toggle = screen.getByRole("switch", { name: "Reconnect automatically" });
    expect(toggle).toHaveAttribute("aria-checked", "true");
    await user.click(toggle);
    expect(toggle).toHaveAttribute("aria-checked", "false");
    await user.keyboard(" ");
    expect(toggle).toHaveAttribute("aria-checked", "true");
  });

  test("Checkbox is a real checkbox with its label", async () => {
    const user = userEvent.setup();
    render(<Checkbox label="Keep me signed in" defaultChecked />);
    const box = screen.getByRole("checkbox", { name: "Keep me signed in" });
    expect(box).toBeChecked();
    await user.click(screen.getByText("Keep me signed in"));
    expect(box).not.toBeChecked();
  });

  test("Field ties its label, hint and error to the input", () => {
    render(
      <Field label="Port" hint="The game listens here." error="Use a port from 1024 to 65535.">
        <Input defaultValue="80" />
      </Field>,
    );
    const input = screen.getByLabelText("Port");
    expect(input).toHaveAttribute("aria-invalid", "true");
    expect(input).toHaveAccessibleDescription("The game listens here. Use a port from 1024 to 65535.");
  });

  test("a Field's error waits for a pause by default, and interrupts only when asked to", () => {
    const { rerender } = render(
      <Field label="Port" error="Use a port from 1024 to 65535.">
        <Input defaultValue="80" />
      </Field>,
    );
    // Checks that run as someone types are polite: no alert.
    expect(screen.queryByRole("alert")).toBeNull();
    expect(screen.getByText("Use a port from 1024 to 65535.")).toHaveAttribute("aria-live", "polite");

    // An error that appears because of something the person just did (a failed submit) is an alert.
    rerender(
      <Field label="Port" error="Use a port from 1024 to 65535." announce="assertive">
        <Input defaultValue="80" />
      </Field>,
    );
    expect(screen.getByRole("alert")).toHaveTextContent("Use a port from 1024 to 65535.");
    expect(screen.getByRole("alert")).not.toHaveAttribute("aria-live");
  });

  test("PasswordInput's switch is named for its field and says whether it is showing", async () => {
    const user = userEvent.setup();
    render(
      <>
        <Field label="Password">
          <PasswordInput showLabel="Show password" />
        </Field>
        <Field label="Confirm password">
          <PasswordInput showLabel="Show confirm password" />
        </Field>
      </>,
    );
    const input = screen.getByLabelText("Password");
    const show = screen.getByRole("button", { name: "Show password" });
    expect(screen.getByRole("button", { name: "Show confirm password" })).toHaveAttribute("aria-pressed", "false");
    expect(input).toHaveAttribute("type", "password");
    expect(show).toHaveAttribute("aria-pressed", "false");
    await user.click(show);
    expect(input).toHaveAttribute("type", "text");
    expect(show).toHaveAttribute("aria-pressed", "true");
    expect(show).toHaveAccessibleName("Show password");
    await user.click(show);
    expect(input).toHaveAttribute("type", "password");
    expect(show).toHaveAttribute("aria-pressed", "false");
  });

  test("a loading Button keeps keyboard focus, is busy, and ignores presses until it's done", async () => {
    const onClick = vi.fn();
    const onSubmit = vi.fn((event: FormEvent) => event.preventDefault());
    function Save() {
      const [busy, setBusy] = useState(false);
      return (
        <form onSubmit={onSubmit}>
          <Button
            type="submit"
            loading={busy}
            onClick={() => {
              onClick();
              setBusy(true);
            }}
          >
            Save
          </Button>
        </form>
      );
    }
    const user = userEvent.setup();
    render(<Save />);
    await user.tab();
    await user.keyboard("{Enter}");
    const button = screen.getByRole("button", { name: "Save" });
    expect(onClick).toHaveBeenCalledTimes(1);
    expect(onSubmit).toHaveBeenCalledTimes(1);
    expect(button).toHaveFocus();
    expect(button).toHaveAttribute("aria-busy", "true");
    expect(button).toHaveAttribute("aria-disabled", "true");
    expect(button).not.toBeDisabled();

    await user.keyboard("{Enter}");
    await user.click(button);
    expect(onClick).toHaveBeenCalledTimes(1);
    expect(onSubmit).toHaveBeenCalledTimes(1);
  });

  test("IconButton is named for screen readers", () => {
    render(
      <IconButton label="Settings">
        <Settings />
      </IconButton>,
    );
    expect(screen.getByRole("button", { name: "Settings" })).toBeInTheDocument();
  });
});

describe("display", () => {
  test("Card titles its section", () => {
    render(
      <Card title="Game Status" actions={<Pill tone="warn">Waiting</Pill>}>
        <p>Body</p>
      </Card>,
    );
    expect(screen.getByRole("region", { name: "Game Status" })).toHaveTextContent("Waiting");
  });

  test("Ring tells screen readers what its centre says, e.g. the time left", () => {
    render(<Ring percent={82} size="lg" label="4:06" aria-label="Time left" valueText="4 minutes 6 seconds" />);
    expect(screen.getByRole("progressbar", { name: "Time left" })).toHaveAttribute("aria-valuetext", "4 minutes 6 seconds");
  });

  test("Ring shows its label and reports its value, kept within 0–100", () => {
    render(
      <>
        <Ring percent={72} label="72%" aria-label="Party HP" />
        <Ring percent={140} label="Full" aria-label="Over" />
      </>,
    );
    expect(screen.getByRole("progressbar", { name: "Party HP" })).toHaveAttribute("aria-valuenow", "72");
    expect(screen.getByText("72%")).toBeInTheDocument();
    expect(screen.getByRole("progressbar", { name: "Over" })).toHaveAttribute("aria-valuenow", "100");
  });
});

describe("Countdown", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  test("re-reads the clock when the page becomes visible again, since a hidden tab's timers run late", () => {
    vi.useFakeTimers({ now: new Date("2026-10-19T10:00:00.000Z") });
    const onDone = vi.fn();
    render(<Countdown until={new Date("2026-10-19T10:05:00.000Z")} onDone={onDone} />);
    vi.setSystemTime(new Date("2026-10-19T10:03:20.000Z")); // the clock moves; the timers don't run
    expect(screen.getByRole("timer")).toHaveTextContent("5:00");
    act(() => {
      document.dispatchEvent(new Event("visibilitychange"));
    });
    expect(screen.getByRole("timer")).toHaveTextContent("1:40");
    vi.setSystemTime(new Date("2026-10-19T10:06:00.000Z"));
    act(() => {
      document.dispatchEvent(new Event("visibilitychange"));
    });
    expect(screen.getByRole("timer")).toHaveTextContent("0:00");
    expect(onDone).toHaveBeenCalledTimes(1);
  });

  test("counts down in m:ss and says when it is done, once", () => {
    vi.useFakeTimers({ now: new Date("2026-10-19T10:00:00.000Z") });
    const onDone = vi.fn();
    render(<Countdown until={new Date("2026-10-19T10:05:00.000Z")} onDone={onDone} />);
    expect(screen.getByRole("timer")).toHaveTextContent("5:00");
    act(() => vi.advanceTimersByTime(1_000));
    expect(screen.getByRole("timer")).toHaveTextContent("4:59");
    act(() => vi.advanceTimersByTime(4 * 60_000 + 50_000));
    expect(screen.getByRole("timer")).toHaveTextContent("0:09");
    expect(onDone).not.toHaveBeenCalled();
    act(() => vi.advanceTimersByTime(9_000));
    expect(screen.getByRole("timer")).toHaveTextContent("0:00");
    expect(onDone).toHaveBeenCalledTimes(1);
    act(() => vi.advanceTimersByTime(10_000));
    expect(onDone).toHaveBeenCalledTimes(1);
  });

  test("a time already past shows 0:00 and is done straight away, once even in StrictMode", () => {
    vi.useFakeTimers({ now: new Date("2026-10-19T10:00:00.000Z") });
    const onDone = vi.fn();
    render(
      <StrictMode>
        <Countdown until={new Date("2026-10-19T09:59:00.000Z")} onDone={onDone} />
      </StrictMode>,
    );
    expect(screen.getByRole("timer")).toHaveTextContent("0:00");
    expect(onDone).toHaveBeenCalledTimes(1);
  });
});

// A type-level check (run by `npm run typecheck`): every Ring must be named for screen readers.
function UnnamedRing() {
  // @ts-expect-error a Ring without an aria-label does not compile
  return <Ring percent={1} label="1" />;
}
