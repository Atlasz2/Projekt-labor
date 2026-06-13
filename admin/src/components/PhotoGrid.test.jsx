import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import PhotoGrid from "./PhotoGrid";

const idleFeedback = { type: "idle", text: "" };
const errorFeedback = { type: "error", text: "Feltöltési hiba" };

describe("PhotoGrid", () => {
  it("shows photo count and thumbnails", () => {
    render(
      <PhotoGrid
        photos={["a.jpg", "b.jpg"]}
        uploading={false}
        feedback={idleFeedback}
        onUpload={vi.fn()}
        onRemove={vi.fn()}
      />
    );
    expect(screen.getByText("2/6")).toBeInTheDocument();
    expect(document.querySelectorAll("img")).toHaveLength(2);
  });

  it("marks the first image as cover (Boritokep)", () => {
    render(
      <PhotoGrid
        photos={["a.jpg", "b.jpg"]}
        uploading={false}
        feedback={idleFeedback}
        onUpload={vi.fn()}
        onRemove={vi.fn()}
      />
    );
    expect(screen.getByText("Boritokep")).toBeInTheDocument();
  });

  it("hides add button when 6 photos are present", () => {
    const sixPhotos = Array.from({ length: 6 }, (_, i) => `img${i}.jpg`);
    render(
      <PhotoGrid
        photos={sixPhotos}
        uploading={false}
        feedback={idleFeedback}
        onUpload={vi.fn()}
        onRemove={vi.fn()}
      />
    );
    expect(screen.queryByText("+ Kep")).not.toBeInTheDocument();
  });

  it("shows upload button when fewer than 6 photos", () => {
    render(
      <PhotoGrid
        photos={["a.jpg"]}
        uploading={false}
        feedback={idleFeedback}
        onUpload={vi.fn()}
        onRemove={vi.fn()}
      />
    );
    expect(screen.getByText("+ Kep")).toBeInTheDocument();
  });

  it("shows uploading text while uploading", () => {
    render(
      <PhotoGrid
        photos={[]}
        uploading={true}
        feedback={idleFeedback}
        onUpload={vi.fn()}
        onRemove={vi.fn()}
      />
    );
    expect(screen.getByText("Feltoltes...")).toBeInTheDocument();
  });

  it("shows feedback message when type is not idle", () => {
    render(
      <PhotoGrid
        photos={[]}
        uploading={false}
        feedback={errorFeedback}
        onUpload={vi.fn()}
        onRemove={vi.fn()}
      />
    );
    expect(screen.getByText("Feltöltési hiba")).toBeInTheDocument();
  });

  it("hides feedback message when type is idle", () => {
    render(
      <PhotoGrid
        photos={[]}
        uploading={false}
        feedback={idleFeedback}
        onUpload={vi.fn()}
        onRemove={vi.fn()}
      />
    );
    expect(screen.queryByText("Feltöltési hiba")).not.toBeInTheDocument();
    expect(screen.queryByText("Sikeres feltöltés")).not.toBeInTheDocument();
  });

  it("does not render an <img> for an empty url but keeps the thumb removable", () => {
    render(
      <PhotoGrid
        photos={["", "b.jpg"]}
        uploading={false}
        feedback={idleFeedback}
        onUpload={vi.fn()}
        onRemove={vi.fn()}
      />
    );
    const imgs = document.querySelectorAll("img");
    expect(imgs).toHaveLength(1);
    expect(imgs[0].getAttribute("src")).toBe("b.jpg");
    // both entries still render their remove button
    expect(screen.getAllByText("x")).toHaveLength(2);
  });

  it("calls onRemove with correct index when remove button is clicked", async () => {
    const onRemove = vi.fn();
    render(
      <PhotoGrid
        photos={["a.jpg", "b.jpg"]}
        uploading={false}
        feedback={idleFeedback}
        onUpload={vi.fn()}
        onRemove={onRemove}
      />
    );
    const removeButtons = screen.getAllByText("x");
    await userEvent.click(removeButtons[1]);
    expect(onRemove).toHaveBeenCalledWith(1);
  });
});

