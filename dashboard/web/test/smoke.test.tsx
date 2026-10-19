import { render, screen } from "@testing-library/react";
import { expect, test } from "vitest";
import { App } from "../src/App";

test("the app renders the product name", () => {
  render(<App />);
  expect(screen.getByText("Amethyst Dashboard")).toBeInTheDocument();
});
