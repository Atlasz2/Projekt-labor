import { describe, expect, it } from "vitest";
import { normalizePhotosFromDoc, buildPhotoFields } from "./photoHelpers";

describe("normalizePhotosFromDoc", () => {
  it("reads from photos[{url}]", () => {
    const result = normalizePhotosFromDoc({ photos: [{ url: "a.jpg" }, { url: "b.jpg" }] });
    expect(result).toEqual(["a.jpg", "b.jpg"]);
  });

  it("reads from photoUrls[]", () => {
    const result = normalizePhotosFromDoc({ photoUrls: ["c.jpg", "d.jpg"] });
    expect(result).toEqual(["c.jpg", "d.jpg"]);
  });

  it("reads from imageUrl", () => {
    const result = normalizePhotosFromDoc({ imageUrl: "e.jpg" });
    expect(result).toEqual(["e.jpg"]);
  });

  it("deduplicates across all three sources", () => {
    const result = normalizePhotosFromDoc({
      photos: [{ url: "x.jpg" }],
      photoUrls: ["x.jpg", "y.jpg"],
      imageUrl: "x.jpg",
    });
    expect(result).toEqual(["x.jpg", "y.jpg"]);
  });

  it("caps output at 6 photos", () => {
    const photos = Array.from({ length: 10 }, (_, i) => ({ url: `img${i}.jpg` }));
    const result = normalizePhotosFromDoc({ photos });
    expect(result).toHaveLength(6);
  });

  it("returns empty array for empty input", () => {
    expect(normalizePhotosFromDoc({})).toEqual([]);
  });
});

describe("buildPhotoFields", () => {
  it("sets all three fields consistently", () => {
    const out = buildPhotoFields(["a.jpg", "b.jpg"]);
    expect(out.imageUrl).toBe("a.jpg");
    expect(out.photoUrls).toEqual(["a.jpg", "b.jpg"]);
    expect(out.photos).toEqual([{ url: "a.jpg" }, { url: "b.jpg" }]);
  });

  it("returns empty fields for empty array", () => {
    const out = buildPhotoFields([]);
    expect(out.imageUrl).toBe("");
    expect(out.photoUrls).toEqual([]);
    expect(out.photos).toEqual([]);
  });

  it("filters out falsy entries", () => {
    const out = buildPhotoFields(["good.jpg", "", null, "also.jpg"]);
    expect(out.photoUrls).toEqual(["good.jpg", "also.jpg"]);
  });
});
