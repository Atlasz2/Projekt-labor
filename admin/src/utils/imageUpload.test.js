import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("firebase/storage", () => ({
  ref: (_storage, path) => ({ path }),
  uploadBytes: vi.fn(),
  getDownloadURL: vi.fn(),
}));

import { getDownloadURL, uploadBytes } from "firebase/storage";
import { shrinkImageForUpload, uploadImageWithFallback } from "./imageUpload";

const smallFile = () => new File(["kicsi kép"], "vár fotó (1).jpg", { type: "image/jpeg" });

describe("uploadImageWithFallback", () => {
  beforeEach(() => vi.clearAllMocks());
  afterEach(() => vi.useRealTimers());

  it("Storage-ba tölt, biztonságos fájlnévvel", async () => {
    uploadBytes.mockResolvedValueOnce({ ref: "snapref" });
    getDownloadURL.mockResolvedValueOnce("https://storage/url");
    const res = await uploadImageWithFallback({ file: smallFile(), storage: {}, folder: "stations" });
    expect(res).toMatchObject({ url: "https://storage/url", mode: "storage" });
    const path = uploadBytes.mock.calls[0][0].path;
    expect(path).toMatch(/^stations\/\d+_v_r_fot___1_\.jpg$/);
  });

  it("Storage-hiba esetén beágyazott képre esik vissza, figyelmeztetéssel", async () => {
    uploadBytes.mockRejectedValueOnce(new Error("storage/unauthorized"));
    const res = await uploadImageWithFallback({ file: smallFile(), storage: {}, folder: "stations" });
    expect(res.mode).toBe("inline");
    expect(res.url.startsWith("data:image/jpeg;base64,")).toBe(true);
    expect(res.message).toMatch(/FIGYELEM/);
  });

  it("ha a Storage nem válaszol, 30 másodperc után a tartalékra vált (nem akad el)", async () => {
    vi.useFakeTimers();
    uploadBytes.mockReturnValueOnce(new Promise(() => {})); // soha nem tér vissza
    const pending = uploadImageWithFallback({ file: smallFile(), storage: {}, folder: "stations" });
    await vi.advanceTimersByTimeAsync(30_000);
    await vi.runAllTimersAsync(); // a tartalék fájlolvasása is időzítőn fut
    const res = await pending;
    expect(res.mode).toBe("inline");
  });

  it("fájl nélkül hibát dob", async () => {
    await expect(uploadImageWithFallback({ file: null, storage: {}, folder: "x" })).rejects.toThrow(
      "Nincs kiválasztott fájl.",
    );
  });
});

describe("shrinkImageForUpload", () => {
  const bigFile = (type = "image/jpeg", name = "nagy.jpeg") =>
    new File([new Uint8Array(2_000_000)], name, { type });

  let drawn;
  beforeEach(() => {
    drawn = null;
    // A jsdom nem dekódol képet és nem rajzol: a böngészőt utánozzuk.
    vi.stubGlobal(
      "Image",
      class {
        width = 4000;
        height = 3000;
        set src(_v) { setTimeout(() => this.onload?.(), 0); }
      },
    );
    const realCreate = document.createElement.bind(document);
    vi.spyOn(document, "createElement").mockImplementation((tag) => {
      if (tag !== "canvas") return realCreate(tag);
      const canvas = {
        getContext: () => ({ drawImage: (_i, _x, _y, w, h) => { drawn = { w, h }; } }),
        toBlob: (cb, type) => cb(new Blob([new Uint8Array(250_000)], { type })),
      };
      return canvas;
    });
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("a nagy fotót legfeljebb 1600 px-re kicsinyíti, JPEG-ként", async () => {
    const out = await shrinkImageForUpload(bigFile());
    expect(drawn).toEqual({ w: 1600, h: 1200 });
    expect(out.type).toBe("image/jpeg");
    expect(out.name).toBe("nagy.jpg");
    expect(out.size).toBe(250_000);
  });

  it("a PNG PNG marad (átlátszóság)", async () => {
    const out = await shrinkImageForUpload(bigFile("image/png", "logo.png"));
    expect(out.type).toBe("image/png");
    expect(out.name).toBe("logo.png");
  });

  it("a kis fájlhoz és a GIF-hez nem nyúl", async () => {
    const small = new File(["x"], "kicsi.jpg", { type: "image/jpeg" });
    expect(await shrinkImageForUpload(small)).toBe(small);
    const gif = bigFile("image/gif", "anim.gif");
    expect(await shrinkImageForUpload(gif)).toBe(gif);
    expect(drawn).toBeNull();
  });

  it("dekódolási hiba esetén az eredeti fájl megy fel", async () => {
    vi.stubGlobal(
      "Image",
      class { set src(_v) { setTimeout(() => this.onerror?.(), 0); } },
    );
    const file = bigFile();
    expect(await shrinkImageForUpload(file)).toBe(file);
  });

  it("a feltöltés már a kicsinyített képet küldi", async () => {
    uploadBytes.mockResolvedValueOnce({ ref: "snapref" });
    getDownloadURL.mockResolvedValueOnce("https://storage/url");
    await uploadImageWithFallback({ file: bigFile(), storage: {}, folder: "stations" });
    const [storageRef, sent] = uploadBytes.mock.calls.at(-1);
    expect(sent.size).toBe(250_000);
    expect(storageRef.path).toMatch(/_nagy\.jpg$/);
  });
});
